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
});
