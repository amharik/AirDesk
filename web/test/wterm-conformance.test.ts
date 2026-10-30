import { WasmBridge } from '@wterm/core';
import { describe, expect, it } from 'vitest';

function cellText(cell: { char: number; chars?: string }): string {
  return cell.chars ?? String.fromCodePoint(cell.char || 32);
}

function rowText(core: WasmBridge, row: number, columns: number): string {
  let text = '';
  for (let column = 0; column < columns; column += 1) {
    text += cellText(core.getCell(row, column));
  }
  return text;
}

function scrollbackText(core: WasmBridge, offset: number, columns: number): string {
  let text = '';
  for (let column = 0; column < columns; column += 1) {
    text += cellText(core.getScrollbackCell(offset, column));
  }
  return text;
}

async function createCore(columns = 20, rows = 4): Promise<WasmBridge> {
  const core = await WasmBridge.load();
  core.init(columns, rows);
  return core;
}

describe('wterm VT conformance', () => {
  it('renders wide, emoji, combining, Devanagari, and Arabic clusters', async () => {
    const core = await createCore();
    core.writeString('A中😀e\u0301नमस्ते مرحبا');

    expect(cellText(core.getCell(0, 0))).toBe('A');
    expect(cellText(core.getCell(0, 1))).toBe('中');
    expect(core.getCell(0, 1).width).toBe(2);
    expect(cellText(core.getCell(0, 3))).toBe('😀');
    expect(core.getCell(0, 3).width).toBe(2);
    expect(cellText(core.getCell(0, 5))).toBe('e\u0301');
    expect(cellText(core.getCell(0, 6))).toBe('न');
    expect(cellText(core.getCell(0, 8))).toBe('स्ते');
    expect(cellText(core.getCell(0, 10))).toBe('م');
    expect(cellText(core.getCell(0, 14))).toBe('ا');
    expect(core.getUnhandledSequences()).toEqual([]);
  });

  it('tracks alternate screen state and restores primary content', async () => {
    const core = await createCore(10, 3);
    core.writeString('main');
    core.writeString('\x1b[?1049h');

    expect(core.usingAltScreen()).toBe(true);
    core.writeString('ALT');
    expect(rowText(core, 0, 10)).toBe('    ALT   ');

    core.writeString('\x1b[?1049l');
    expect(core.usingAltScreen()).toBe(false);
    expect(rowText(core, 0, 10)).toContain('main');
  });

  it('retains scrollback and reports discarded history', async () => {
    const core = await createCore(10, 4);
    for (let index = 0; index < 1_100; index += 1) {
      core.writeString(`L${index}\r\n`);
    }

    expect(core.getScrollbackCount()).toBeGreaterThanOrEqual(1_000);
    expect(core.getScrollbackDiscardedCount()).toBeGreaterThan(0);
    expect(scrollbackText(core, 0, 10)).toMatch(/^L\d+ +$/);
  });

  it('tracks bracketed paste, mouse, focus, cursor keys, and title modes', async () => {
    const core = await createCore(10, 3);
    core.writeString('\x1b[?2004h\x1b[?1002h\x1b[?1006h\x1b[?1004h\x1b[?1h');
    core.writeString('\x1b]0;Conformance\x07');
    core.writeString('\x1b[?2026h');

    expect(core.bracketedPaste()).toBe(true);
    expect(core.mouseTracking()).toBe(1002);
    expect(core.mouseSgr()).toBe(true);
    expect(core.mouseEncoding()).toBe('sgr');
    expect(core.focusEvents()).toBe(true);
    expect(core.cursorKeysApp()).toBe(true);
    expect(core.synchronizedOutput()).toBe(true);
    expect(core.getTitle()).toBe('Conformance');
    expect(core.getUnhandledSequences()).toEqual([]);
  });

  it('applies palette and true-color SGR without leaking state', async () => {
    const core = await createCore(10, 3);
    core.writeString('\x1b[31mR\x1b[38;2;10;20;30mT\x1b[48;2;40;50;60mB\x1b[0mN');

    expect(core.getCell(0, 0).fg).toBe(1);
    expect(core.getCell(0, 1).fgRgb).toBe(0x0a141e);
    expect(core.getCell(0, 2).bgRgb).toBe(0x28323c);
    expect(core.getCell(0, 3).fg).toBe(256);
    expect(core.getCell(0, 3).bg).toBe(256);
  });

  it('resizes the grid while retaining cell content', async () => {
    const core = await createCore(10, 3);
    core.writeString('abc');
    core.resize(20, 5);

    expect(core.getCols()).toBe(20);
    expect(core.getRows()).toBe(5);
    expect(rowText(core, 0, 3)).toBe('abc');
  });
});
