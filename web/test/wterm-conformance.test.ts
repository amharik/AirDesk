import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { WasmBridge } from '@wterm/core';
import type { CellData, TerminalCore } from '@wterm/core';
import { GhosttyCore } from '@wterm/ghostty';
import { describe, expect, it } from 'vitest';

const ghosttyWasmPath = resolve(process.cwd(), 'node_modules/@wterm/ghostty/wasm/ghostty-vt.wasm');
const ghosttyWasmURL = `data:application/wasm;base64,${readFileSync(ghosttyWasmPath).toString('base64')}`;

interface CoreExpectation {
  name: string;
  create: () => Promise<TerminalCore>;
  paletteForeground: { index: number; rgb: number };
  scrollbackDiscarded: 'positive' | 'zero';
}

const cores: CoreExpectation[] = [
  {
    name: 'built-in',
    create: async () => {
      const core = await WasmBridge.load();
      core.init(20, 4);
      return core;
    },
    paletteForeground: { index: 1, rgb: 0xcc6666 },
    scrollbackDiscarded: 'positive'
  },
  {
    name: 'ghostty',
    create: async () => {
      const core = await GhosttyCore.load({
        wasmPath: ghosttyWasmURL,
        scrollbackLimit: 16 * 1024 * 1024
      });
      core.init(20, 4);
      return core;
    },
    paletteForeground: { index: 1, rgb: 0xcc6666 },
    scrollbackDiscarded: 'zero'
  }
];

function cellText(cell: CellData): string {
  return cell.chars ?? String.fromCodePoint(cell.char || 32);
}

function rowText(core: TerminalCore, row: number, columns: number): string {
  let text = '';
  for (let column = 0; column < columns; column += 1) {
    text += cellText(core.getCell(row, column));
  }
  return text;
}

function scrollbackText(core: TerminalCore, offset: number, columns: number): string {
  let text = '';
  for (let column = 0; column < columns; column += 1) {
    text += cellText(core.getScrollbackCell(offset, column));
  }
  return text;
}

async function createCore(coreCase: CoreExpectation, columns: number, rows: number): Promise<TerminalCore> {
  const core = await coreCase.create();
  if (columns !== 20 || rows !== 4) core.resize(columns, rows);
  return core;
}

describe.each(cores)('wterm VT conformance ($name)', (coreCase) => {
  it('renders wide, emoji, combining, Devanagari, and Arabic clusters', async () => {
    const core = await createCore(coreCase, 20, 4);
    core.writeString('A中😀e\u0301\r\nनमस्ते\r\nمرحبا');

    expect(cellText(core.getCell(0, 0))).toBe('A');
    expect(cellText(core.getCell(0, 1))).toBe('中');
    expect(core.getCell(0, 1).width).toBe(2);
    expect(rowText(core, 0, 20)).toContain('😀');
    expect(rowText(core, 0, 20)).toContain('e\u0301');
    expect(rowText(core, 1, 20).trim()).toBe('नमस्ते');
    expect(rowText(core, 2, 20).trim()).toBe('مرحبا');
    expect(core.getUnhandledSequences()).toEqual([]);
  });

  it('tracks alternate screen state and restores primary content', async () => {
    const core = await createCore(coreCase, 10, 3);
    core.writeString('main');
    core.writeString('\x1b[?1049h');

    expect(core.usingAltScreen()).toBe(true);
    core.writeString('ALT');
    expect(rowText(core, 0, 10)).toBe('    ALT   ');

    core.writeString('\x1b[?1049l');
    expect(core.usingAltScreen()).toBe(false);
    expect(rowText(core, 0, 10)).toContain('main');
  });

  it('retains scrollback and reports history accounting', async () => {
    const core = await createCore(coreCase, 10, 4);
    for (let index = 0; index < 1_100; index += 1) {
      core.writeString(`L${index}\r\n`);
    }

    expect(core.getScrollbackCount()).toBeGreaterThanOrEqual(1_000);
    if (coreCase.scrollbackDiscarded === 'positive') {
      expect(core.getScrollbackDiscardedCount!()).toBeGreaterThan(0);
    } else {
      expect(core.getScrollbackDiscardedCount!()).toBe(0);
    }
    expect(scrollbackText(core, 0, 10)).toMatch(/^L\d+ +$/);
  });

  it('tracks bracketed paste, mouse, focus, cursor keys, and title modes', async () => {
    const core = await createCore(coreCase, 10, 3);
    core.writeString('\x1b[?2004h\x1b[?1002h\x1b[?1006h\x1b[?1004h\x1b[?1h');
    core.writeString('\x1b]0;Conformance\x07');
    core.writeString('\x1b[?2026h');

    expect(core.bracketedPaste()).toBe(true);
    expect(core.mouseTracking!()).toBe(1002);
    expect(core.mouseSgr!()).toBe(true);
    expect(core.mouseEncoding!()).toBe('sgr');
    expect(core.focusEvents!()).toBe(true);
    expect(core.cursorKeysApp()).toBe(true);
    expect(core.synchronizedOutput!()).toBe(true);
    expect(core.getTitle()).toBe('Conformance');
    expect(core.getUnhandledSequences()).toEqual([]);
  });

  it('applies palette and true-color SGR without leaking state', async () => {
    const core = await createCore(coreCase, 10, 3);
    core.writeString('\x1b[31mR\x1b[38;2;10;20;30mT\x1b[48;2;40;50;60mB\x1b[0mN');

    const palette = core.getCell(0, 0);
    expect(palette.fg === coreCase.paletteForeground.index || palette.fgRgb === coreCase.paletteForeground.rgb).toBe(true);
    expect(core.getCell(0, 1).fgRgb).toBe(0x0a141e);
    expect(core.getCell(0, 2).bgRgb).toBe(0x28323c);
    expect(core.getCell(0, 3).fg).toBe(256);
    expect(core.getCell(0, 3).bg).toBe(256);
  });

  it('resizes the grid while retaining cell content', async () => {
    const core = await createCore(coreCase, 10, 3);
    core.writeString('abc');
    core.resize(20, 5);

    expect(core.getCols()).toBe(20);
    expect(core.getRows()).toBe(5);
    expect(rowText(core, 0, 3)).toBe('abc');
  });
});
