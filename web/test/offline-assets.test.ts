import { readFileSync, statSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const shellRoot = resolve(process.cwd(), '../AirDesk/Resources/DesktopShell');

describe('offline DesktopShell assets', () => {
  it('ships the Wanix runtime, kernel, and rc shell locally', () => {
    for (const asset of ['wanix/wanix.min.js', 'wanix/wanix.wasm', 'wanix/rc.wasm']) {
      expect(statSync(resolve(shellRoot, asset)).size).toBeGreaterThan(0);
    }

    for (const entry of ['index.html', 'wanix-live.html', 'wanix-shell.js']) {
      expect(readFileSync(resolve(shellRoot, entry), 'utf8')).not.toMatch(/https?:\/\//);
    }
  });
});
