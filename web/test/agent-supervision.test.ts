import { describe, expect, it } from 'vitest';
import {
  AGENT_INPUT_CAPABILITY,
  AgentSupervisionModel,
  badgeForSemanticSnapshot,
  redactSensitiveText
} from '../src/terminal/agent-supervision';
import { SemanticTerminalModel } from '../src/terminal/semantic-blocks';

function completedBlock(
  semantic: SemanticTerminalModel,
  command: string,
  output: string,
  exitCode = 0
): void {
  semantic.consume('\x1b]133;A\x07');
  semantic.consume('\x1b]133;B\x07');
  semantic.consume(`${command}\r`);
  semantic.consume('\x1b]133;C\x07');
  semantic.consume(output);
  semantic.consume(`\x1b]133;D;${exitCode}\x07`);
}

describe('agent supervision', () => {
  it('derives badges from command-block state', () => {
    const semantic = new SemanticTerminalModel();
    expect(badgeForSemanticSnapshot(semantic.snapshot())).toBe('idle');

    semantic.consume('\x1b]133;A\x07');
    semantic.consume('\x1b]133;B\x07');
    expect(badgeForSemanticSnapshot(semantic.snapshot())).toBe('waiting');

    semantic.consume('\x1b]133;C\x07');
    expect(badgeForSemanticSnapshot(semantic.snapshot())).toBe('working');

    semantic.consume('\x1b]133;D;2\x07');
    expect(badgeForSemanticSnapshot(semantic.snapshot())).toBe('failed');

    semantic.noteInput('\x03');
    expect(badgeForSemanticSnapshot(semantic.snapshot())).toBe('failed');
    expect(badgeForSemanticSnapshot(semantic.snapshot(), false)).toBe('offline');
  });

  it('returns read-only output snapshots without prompts or secrets', () => {
    const semantic = new SemanticTerminalModel();
    completedBlock(
      semantic,
      'export TOKEN=super-secret-token',
      'Authorization: Bearer abc123secret\r\nvisible line\r\n'
    );
    const supervisor = new AgentSupervisionModel();
    supervisor.observe(semantic.snapshot());
    const snapshot = supervisor.snapshot(123);

    expect(snapshot.badge).toBe('idle');
    expect(snapshot.generatedAt).toBe(123);
    expect(snapshot.redacted).toBe(true);
    expect(snapshot.blocks[0]?.output).toContain('visible line');
    const encoded = JSON.stringify(snapshot);
    expect(encoded).not.toContain('super-secret-token');
    expect(encoded).not.toContain('abc123secret');
    expect(encoded).not.toContain('export TOKEN');
    expect(encoded).not.toContain('$ ');
  });

  it('redacts common credential forms', () => {
    const result = redactSensitiveText(
      'password=hunter2\napi_key: sk-abcdefghijklmnopqrstuvwxyz\nhttps://user:pass@example.test/path'
    );
    expect(result.redacted).toBe(true);
    expect(result.text).not.toContain('hunter2');
    expect(result.text).not.toContain('abcdefghijklmnopqrstuvwxyz');
    expect(result.text).not.toContain('user:pass');
    expect(result.text).toContain('[redacted]');
  });

  it('denies write and inject without a live explicit capability', () => {
    const supervisor = new AgentSupervisionModel();
    supervisor.setConnected(false);
    const grant = {
      capability: AGENT_INPUT_CAPABILITY,
      leaseId: 'lease.agent',
      expiresAt: 1_000,
      actions: ['write'] as const
    };
    expect(supervisor.authorize('write', 'echo ok\r', grant, 0)).toEqual({
      authorized: false,
      reason: 'offline'
    });

    supervisor.setConnected(true);
    expect(supervisor.authorize('write', 'echo ok\r', null, 0)).toEqual({
      authorized: false,
      reason: 'missing-capability'
    });
    expect(supervisor.authorize('write', 'echo ok\r', {
      ...grant,
      capability: 'airdesk://agent/other'
    }, 0)).toEqual({ authorized: false, reason: 'wrong-capability' });
    expect(supervisor.authorize('write', 'echo ok\r', { ...grant, leaseId: ' ' }, 0)).toEqual({
      authorized: false,
      reason: 'missing-lease'
    });
    expect(supervisor.authorize('write', 'echo ok\r', { ...grant, expiresAt: 1 }, 1)).toEqual({
      authorized: false,
      reason: 'expired-lease'
    });
    expect(supervisor.authorize('inject', 'echo ok\r', grant, 0)).toEqual({
      authorized: false,
      reason: 'action-not-granted'
    });
    expect(supervisor.authorize('write', '', grant, 0)).toEqual({
      authorized: false,
      reason: 'empty-payload'
    });
    expect(supervisor.authorize('write', '\x1b]0;title\x07', grant, 0)).toEqual({
      authorized: false,
      reason: 'unsafe-control-sequence'
    });

    const audit = supervisor.auditEvents();
    expect(audit.map((event) => event.accepted)).toEqual([
      false,
      false,
      false,
      false,
      false,
      false,
      false,
      false
    ]);
    expect(JSON.stringify(audit)).not.toContain('title');
    expect(audit[0]?.reason).toBe('offline');
  });

  it('invokes the sink only for an authorized write and keeps an audit trail', () => {
    const supervisor = new AgentSupervisionModel();
    const written: string[] = [];
    const grant = {
      capability: AGENT_INPUT_CAPABILITY,
      leaseId: 'lease.agent',
      expiresAt: 10_000,
      actions: ['write'] as const
    };
    const deny = (data: string): void => {
      written.push(data);
    };
    const denied = supervisor.apply('write', 'rm -rf /', grant, deny, 11_000);
    expect(denied).toEqual({ authorized: false, reason: 'expired-lease' });

    const accepted = supervisor.apply('write', 'echo ok\r', grant, deny, 1_000);
    expect(accepted).toEqual({ authorized: true });
    expect(written).toEqual(['echo ok\r']);

    const audit = supervisor.auditEvents();
    expect(audit).toHaveLength(2);
    expect(audit[0]?.accepted).toBe(false);
    expect(audit[1]?.accepted).toBe(true);
    expect(audit[1]?.byteCount).toBe('echo ok\r'.length);
    expect(JSON.stringify(audit)).not.toContain('rm -rf');
    expect(JSON.stringify(audit)).not.toContain('echo ok');
  });
});
