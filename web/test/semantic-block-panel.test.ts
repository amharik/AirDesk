// @vitest-environment jsdom
import { describe, expect, it } from 'vitest';
import {
  SemanticBlockPanel,
  SemanticTerminalModel
} from '../src/terminal/semantic-blocks';

describe('semantic block panel', () => {
  it('renders exit aura and wires copy and markdown actions', () => {
    const model = new SemanticTerminalModel();
    model.consume('\x1b]133;A\x07');
    model.consume('\x1b]133;B\x07');
    model.consume('make test\r');
    model.consume('\x1b]133;C\x07');
    model.consume('ok\r\n');
    model.consume('\x1b]133;D;0\x07');

    const copied: string[] = [];
    const panel = new SemanticBlockPanel({
      onCopy: (text) => {
        copied.push(text);
      },
      resolveBlock: (id) => model.snapshot().blocks.find((block) => block.id === id)
    });
    panel.render(model.snapshot());

    expect(panel.element.hidden).toBe(false);
    expect(panel.element.querySelector('.semantic-aura-success')).not.toBeNull();
    const buttons = panel.element.querySelectorAll('button');
    expect(buttons).toHaveLength(2);
    buttons[0]?.click();
    expect(copied).toEqual(['ok']);
    buttons[1]?.click();
    expect(panel.element.querySelector('.semantic-block-markdown')?.textContent).toContain('### make test');
    panel.destroy();
  });

  it('hides prompt-only state and disables unconfirmed input actions', () => {
    const model = new SemanticTerminalModel();
    const panel = new SemanticBlockPanel();
    panel.render(model.snapshot());
    expect(panel.element.hidden).toBe(true);

    model.consume('\x1b]133;A\x07');
    model.consume('\x1b]133;B\x07');
    model.consume('rm -rf /');
    panel.render(model.snapshot());
    const buttons = panel.element.querySelectorAll('button');
    expect(buttons[0]?.disabled).toBe(true);
    expect(buttons[1]?.disabled).toBe(true);
  });
});
