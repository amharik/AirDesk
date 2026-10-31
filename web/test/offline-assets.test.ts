import { readFileSync, statSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const shellRoot = resolve(process.cwd(), '../AirDesk/Resources/DesktopShell');
const pages = ['index.html', 'wanix-live.html', 'winbox-preview.html', 'wterm-preview.html'];
const offlineEntries = [...pages, 'wanix-shell.js', 'wanix-live.js'];

describe('offline DesktopShell assets', () => {
  it('ships the Wanix runtime, kernel, and rc shell locally', () => {
    for (const asset of ['wanix/wanix.min.js', 'wanix/wanix.wasm', 'wanix/rc.wasm']) {
      expect(statSync(resolve(shellRoot, asset)).size).toBeGreaterThan(0);
    }

    for (const entry of offlineEntries) {
      expect(readFileSync(resolve(shellRoot, entry), 'utf8')).not.toMatch(/https?:\/\//);
    }
  });

  it('applies a restrictive content security policy to every desktop page', () => {
    for (const page of pages) {
      const html = readFileSync(resolve(shellRoot, page), 'utf8');
      expect(html).toContain('http-equiv="Content-Security-Policy"');
      expect(html).toContain("default-src 'self'");
      expect(html).toContain("script-src 'self' 'unsafe-eval' 'wasm-unsafe-eval'");
      expect(html).toContain("'sha256-a5qOmWtV4zivHG9TzYCcBDIYXWtamE0rSi+b/aPFeYw='");
      expect(html).toContain("'sha256-vWvTHbd5URFC6ZXdJfBcriueY7hIyWP2o0+8ycL5u40='");
      expect(html).toContain("object-src 'none'");
      expect(html).not.toMatch(/script-src[^;]*'unsafe-inline'/);
    }
  });
});
