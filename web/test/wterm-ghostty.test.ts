import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { GhosttyCore } from '@wterm/ghostty';
import { describe, expect, it } from 'vitest';

const wasmPath = resolve(process.cwd(), 'node_modules/@wterm/ghostty/wasm/ghostty-vt.wasm');
const wasmURL = `data:application/wasm;base64,${readFileSync(wasmPath).toString('base64')}`;
const SCROLLBACK_LIMIT = 16 * 1024 * 1024;

function cellText(cell: { char: number; chars?: string }): string {
  return cell.chars ?? String.fromCodePoint(cell.char || 32);
}

function rowText(core: GhosttyCore, row: number, columns: number): string {
  let text = '';
  for (let column = 0; column < columns; column += 1) {
    text += cellText(core.getCell(row, column));
  }
  return text;
}

function scrollbackText(core: GhosttyCore, offset: number, columns: number): string {
  let text = '';
  for (let column = 0; column < columns; column += 1) {
    text += cellText(core.getScrollbackCell(offset, column));
  }
  return text;
}

async function createCore(columns = 20, rows = 4): Promise<GhosttyCore> {
  const core = await GhosttyCore.load({ wasmPath: wasmURL, scrollbackLimit: SCROLLBACK_LIMIT });
  core.init(columns, rows);
  return core;
}

describe('wterm Ghostty production core', () => {
  it('retains the 5,000-line scrollback gate without discarding history', async () => {
    const core = await createCore(80, 24);
    for (let index = 0; index < 6_000; index += 1) {
      core.writeString(`L${index}\r\n`);
    }

    expect(core.getScrollbackCount()).toBeGreaterThanOrEqual(5_000);
    expect(core.getScrollbackDiscardedCount()).toBe(0);
    expect(scrollbackText(core, 0, 80)).toMatch(/^L\d+ +$/);
    core.dispose();
  });

  it('renders complex clusters, modes, alternate screen, and resize', async () => {
    const core = await createCore(20, 4);
    core.writeString('A中😀e\u0301नमस्ते مرحبا\x1b[?2004h\x1b[?1002h\x1b[?1006h\x1b[?1004h\x1b[?1h');
    core.writeString('\x1b]0;Conformance\x07');

    expect(cellText(core.getCell(0, 1))).toBe('中');
    expect(core.getCell(0, 1).width).toBe(2);
    expect(cellText(core.getCell(0, 3))).toBe('😀');
    expect(cellText(core.getCell(0, 5))).toBe('e\u0301');
    expect(cellText(core.getCell(0, 6))).toBe('न');
    expect(cellText(core.getCell(0, 8))).toBe('स्ते');
    expect(core.bracketedPaste()).toBe(true);
    expect(core.mouseTracking()).toBe(1002);
    expect(core.mouseSgr()).toBe(true);
    expect(core.focusEvents()).toBe(true);
    expect(core.cursorKeysApp()).toBe(true);
    expect(core.getTitle()).toBe('Conformance');

    core.writeString('\x1b[?1049hALT');
    expect(core.usingAltScreen()).toBe(true);
    expect(rowText(core, 0, 20)).toContain('ALT');
    core.writeString('\x1b[?1049l');
    expect(core.usingAltScreen()).toBe(false);

    core.resize(30, 6);
    expect(core.getCols()).toBe(30);
    expect(core.getRows()).toBe(6);
    expect(cellText(core.getCell(0, 0))).toBe('A');
    expect(cellText(core.getCell(0, 1))).toBe('中');
    core.dispose();
  });
});
