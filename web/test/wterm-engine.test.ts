import { describe, expect, it, vi } from 'vitest';

const terminals = vi.hoisted(() => [] as Array<{ renderingPaused: boolean; calls: boolean[] }>);

vi.mock('@wterm/dom', () => {
  class WTerm {
    renderingPaused = false;
    calls: boolean[] = [];

    constructor(...args: unknown[]) {
      void args;
      terminals.push(this);
    }

    async init(): Promise<void> {}

    fit(): void {}

    focus(): void {}

    resize(...args: unknown[]): void {
      void args;
    }

    async readText(): Promise<string> {
      return '';
    }

    destroy(): void {}

    write(...args: unknown[]): void {
      void args;
    }

    setRenderingPaused(paused: boolean): void {
      this.renderingPaused = paused;
      this.calls.push(paused);
    }
  }

  return { WTerm };
});

import { WTermEngine } from '../src/terminal/wterm-engine';

describe('WTerm engine rendering pause', () => {
  it('pauses and resumes the underlying terminal renderer', () => {
    terminals.length = 0;
    const element = { parentElement: null } as unknown as HTMLElement;
    const engine = new WTermEngine(element, { transport: { send: () => undefined } });

    engine.setRenderingPaused(true);
    engine.setRenderingPaused(false);

    expect(terminals).toHaveLength(1);
    expect(terminals[0]!.calls).toEqual([true, false]);
    expect(terminals[0]!.renderingPaused).toBe(false);
  });
});
