export type AuditAction =
  | 'member.added'
  | 'member.role-changed'
  | 'member.revoked'
  | 'resource.added'
  | 'resource.access-changed'
  | 'session.opened'
  | 'session.joined';

export interface AuditEvent {
  seq: number;
  workspaceId: string;
  action: AuditAction;
  actorId: string;
  targetId: string;
  at: number;
  detail?: Record<string, unknown>;
}

export interface AuditInput {
  action: AuditAction;
  actorId: string;
  targetId: string;
  detail?: Record<string, unknown>;
  at?: number;
}

function cloneEvent(event: AuditEvent): AuditEvent {
  return {
    ...event,
    ...(event.detail ? { detail: { ...event.detail } } : {})
  };
}

export class AuditLog {
  private readonly eventsList: AuditEvent[] = [];
  private sequence = 0;

  constructor(private readonly workspaceId: string) {}

  append(input: AuditInput): AuditEvent {
    this.sequence += 1;
    const event: AuditEvent = {
      seq: this.sequence,
      workspaceId: this.workspaceId,
      action: input.action,
      actorId: input.actorId,
      targetId: input.targetId,
      at: input.at ?? Date.now(),
      ...(input.detail ? { detail: { ...input.detail } } : {})
    };
    this.eventsList.push(event);
    return cloneEvent(event);
  }

  get events(): readonly AuditEvent[] {
    return this.eventsList.map(cloneEvent);
  }

  get lastSeq(): number {
    return this.sequence;
  }
}
