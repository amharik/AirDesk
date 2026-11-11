// @vitest-environment jsdom
import { describe, expect, it } from 'vitest';
import { AgentSupervisionBadge, AgentSupervisionModel } from '../src/terminal/agent-supervision';
import { SemanticTerminalModel } from '../src/terminal/semantic-blocks';

describe('agent supervision badge', () => {
  it('renders accessible read-only state and updates from command blocks', () => {
    const badge = new AgentSupervisionBadge();
    expect(badge.element.getAttribute('role')).toBe('status');
    expect(badge.element.getAttribute('aria-live')).toBe('polite');
    expect(badge.element.dataset.state).toBe('idle');
    expect(badge.element.textContent).toBe('Agent idle');

    const semantic = new SemanticTerminalModel();
    semantic.consume('\x1b]133;A\x07');
    semantic.consume('\x1b]133;B\x07');
    semantic.consume('\x1b]133;C\x07');
    const supervisor = new AgentSupervisionModel();
    supervisor.observe(semantic.snapshot());
    badge.render(supervisor.snapshot());

    expect(badge.element.dataset.state).toBe('working');
    expect(badge.element.textContent).toBe('Agent working');
    expect(badge.element.title).toContain('Read-only');

    badge.destroy();
    expect(badge.element.isConnected).toBe(false);
  });

  it('renders offline and redaction state', () => {
    const badge = new AgentSupervisionBadge();
    const semantic = new SemanticTerminalModel();
    semantic.consume('\x1b]133;A\x07');
    semantic.consume('\x1b]133;B\x07');
    semantic.consume('echo ok\r');
    semantic.consume('\x1b]133;C\x07');
    semantic.consume('token=super-secret\r\n');
    semantic.consume('\x1b]133;D;0\x07');

    const supervisor = new AgentSupervisionModel();
    supervisor.observe(semantic.snapshot());
    supervisor.setConnected(false);
    badge.render(supervisor.snapshot());

    expect(badge.element.dataset.state).toBe('offline');
    expect(badge.element.textContent).toBe('Agent offline');
    expect(badge.element.title).toContain('redacts');
  });
});
