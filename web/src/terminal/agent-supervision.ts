import { sanitizeTerminalText } from './semantic-blocks';
import type { SemanticBlockSnapshot } from './semantic-blocks';

export const AGENT_INPUT_CAPABILITY = 'airdesk://agent/input';
export const AGENT_SNAPSHOT_LIMIT = 50;
export const AGENT_SNAPSHOT_TEXT_LIMIT = 8_192;
export const AGENT_CONTROL_TEXT_LIMIT = 65_536;
export const AGENT_AUDIT_LIMIT = 100;

export type AgentBadge = 'offline' | 'idle' | 'working' | 'waiting' | 'blocked' | 'failed';
export type AgentControlAction = 'write' | 'inject';

export interface AgentCapabilityGrant {
  capability: string;
  leaseId: string;
  expiresAt: number;
  actions?: readonly AgentControlAction[];
}

export type AgentControlDenial =
  | 'offline'
  | 'missing-capability'
  | 'wrong-capability'
  | 'missing-lease'
  | 'expired-lease'
  | 'action-not-granted'
  | 'empty-payload'
  | 'payload-too-large'
  | 'unsafe-control-sequence';

export interface AgentControlDecision {
  authorized: boolean;
  reason?: AgentControlDenial;
}

export interface AgentControlAuditEvent {
  timestamp: number;
  action: AgentControlAction;
  capability: string | null;
  leaseId: string | null;
  byteCount: number;
  accepted: boolean;
  reason?: AgentControlDenial;
}

export interface AgentSnapshotBlock {
  id: number;
  state: string;
  output: string;
}

export interface AgentSupervisionSnapshot {
  badge: AgentBadge;
  blocks: AgentSnapshotBlock[];
  generatedAt: number;
  redacted: boolean;
  unconfirmedInputBytes: number;
}

const BADGE_LABELS: Record<AgentBadge, string> = {
  offline: 'Agent offline',
  idle: 'Agent idle',
  working: 'Agent working',
  waiting: 'Agent waiting',
  blocked: 'Agent blocked',
  failed: 'Agent failed'
};

export function agentBadgeLabel(badge: AgentBadge): string {
  return BADGE_LABELS[badge];
}

export function badgeForSemanticSnapshot(
  snapshot: SemanticBlockSnapshot,
  connected = true
): AgentBadge {
  if (!connected) return 'offline';
  const latest = [...snapshot.blocks].reverse().find((block) => block.state !== 'prompt');
  if (!latest) return snapshot.unconfirmedInputBytes > 0 ? 'waiting' : 'idle';
  switch (latest.state) {
    case 'running':
      return 'working';
    case 'interrupted':
      return 'blocked';
    case 'finished':
      return latest.exitCode === 0 ? 'idle' : 'failed';
    case 'input':
      return 'waiting';
    default:
      return 'idle';
  }
}

function sensitivePatterns(): RegExp[] {
  return [
    /\bAuthorization\s*:\s*(?:Bearer\s+)?[^\s]+/gi,
    /\bBearer\s+[A-Za-z0-9._~+/=-]+/gi,
    /(password|passwd|pwd|token|secret|api[-_]?key)\s*[:=]\s*[^\s]+/gi,
    /-----BEGIN [^-]*PRIVATE KEY-----[\s\S]*?-----END [^-]*PRIVATE KEY-----/g,
    /https?:\/\/[^\s/@:]+:[^\s/@]+@/g,
    /\b(?:gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,})\b/g
  ];
}

export function redactSensitiveText(value: string): { text: string; redacted: boolean } {
  let text = sanitizeTerminalText(value);
  let redacted = false;
  for (const pattern of sensitivePatterns()) {
    text = text.replace(pattern, (_match: string, key?: string) => {
      redacted = true;
      return key ? `${key}=[redacted]` : '[redacted]';
    });
  }
  return { text, redacted };
}

function unsafeControlSequence(value: string): boolean {
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code === 9 || code === 10 || code === 13) continue;
    if (code < 0x20 || code === 0x7f) return true;
  }
  return false;
}

export class AgentSupervisionModel {
  private connected = true;
  private badge: AgentBadge = 'idle';
  private semantic: SemanticBlockSnapshot = {
    blocks: [],
    activeBlockId: null,
    lastSequence: 0,
    unconfirmedInputBytes: 0
  };
  private audit: AgentControlAuditEvent[] = [];

  setConnected(connected: boolean): void {
    this.connected = connected;
    this.badge = connected ? badgeForSemanticSnapshot(this.semantic) : 'offline';
  }

  observe(snapshot: SemanticBlockSnapshot): void {
    this.semantic = snapshot;
    this.badge = badgeForSemanticSnapshot(snapshot, this.connected);
  }

  snapshot(now = Date.now(), limit = AGENT_SNAPSHOT_LIMIT): AgentSupervisionSnapshot {
    let redacted = false;
    const blocks = this.semantic.blocks
      .filter((block) => block.state !== 'prompt' && block.output.length > 0)
      .slice(-Math.max(1, limit))
      .map((block) => {
        const result = redactSensitiveText(block.output);
        redacted = redacted || result.redacted;
        return {
          id: block.id,
          state: block.state,
          output: result.text.slice(0, AGENT_SNAPSHOT_TEXT_LIMIT)
        };
      });
    return {
      badge: this.badge,
      blocks,
      generatedAt: now,
      redacted,
      unconfirmedInputBytes: this.semantic.unconfirmedInputBytes
    };
  }

  authorize(
    action: AgentControlAction,
    payload: string,
    grant: AgentCapabilityGrant | null | undefined,
    now = Date.now()
  ): AgentControlDecision {
    const decision = this.validate(action, payload, grant, now);
    this.recordAudit(action, payload, grant, now, decision);
    return decision;
  }

  apply(
    action: AgentControlAction,
    payload: string,
    grant: AgentCapabilityGrant | null | undefined,
    sink: (payload: string) => void | Promise<void>,
    now = Date.now()
  ): AgentControlDecision {
    const decision = this.authorize(action, payload, grant, now);
    if (decision.authorized) void sink(payload);
    return decision;
  }

  auditEvents(): AgentControlAuditEvent[] {
    return this.audit.map((event) => ({ ...event }));
  }

  private validate(
    action: AgentControlAction,
    payload: string,
    grant: AgentCapabilityGrant | null | undefined,
    now: number
  ): AgentControlDecision {
    if (!this.connected) return { authorized: false, reason: 'offline' };
    if (!grant) return { authorized: false, reason: 'missing-capability' };
    if (grant.capability !== AGENT_INPUT_CAPABILITY) {
      return { authorized: false, reason: 'wrong-capability' };
    }
    if (!grant.leaseId.trim()) return { authorized: false, reason: 'missing-lease' };
    if (grant.expiresAt <= now) return { authorized: false, reason: 'expired-lease' };
    if (grant.actions && !grant.actions.includes(action)) {
      return { authorized: false, reason: 'action-not-granted' };
    }
    if (!payload) return { authorized: false, reason: 'empty-payload' };
    if (payload.length > AGENT_CONTROL_TEXT_LIMIT) {
      return { authorized: false, reason: 'payload-too-large' };
    }
    if (unsafeControlSequence(payload)) {
      return { authorized: false, reason: 'unsafe-control-sequence' };
    }
    return { authorized: true };
  }

  private recordAudit(
    action: AgentControlAction,
    payload: string,
    grant: AgentCapabilityGrant | null | undefined,
    now: number,
    decision: AgentControlDecision
  ): void {
    this.audit.push({
      timestamp: now,
      action,
      capability: grant?.capability ?? null,
      leaseId: grant?.leaseId ?? null,
      byteCount: payload.length,
      accepted: decision.authorized,
      reason: decision.reason
    });
    if (this.audit.length > AGENT_AUDIT_LIMIT) {
      this.audit.splice(0, this.audit.length - AGENT_AUDIT_LIMIT);
    }
  }
}

export class AgentSupervisionBadge {
  readonly element: HTMLElement;

  constructor() {
    this.element = document.createElement('span');
    this.element.className = 'agent-supervision-badge';
    this.element.setAttribute('role', 'status');
    this.element.setAttribute('aria-live', 'polite');
    this.render({
      badge: 'idle',
      blocks: [],
      generatedAt: 0,
      redacted: false,
      unconfirmedInputBytes: 0
    });
  }

  render(snapshot: AgentSupervisionSnapshot): void {
    this.element.dataset.state = snapshot.badge;
    this.element.textContent = agentBadgeLabel(snapshot.badge);
    this.element.title = snapshot.redacted
      ? 'Read-only snapshot redacts credential-like text.'
      : 'Read-only agent supervision snapshot.';
  }

  destroy(): void {
    this.element.remove();
  }
}
