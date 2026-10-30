import { readFile } from 'node:fs/promises';
import { basename, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repositoryRoot = resolve(webRoot, '..');
const outputDirectory = resolve(repositoryRoot, 'AirDesk/Resources/DesktopShell');
const check = process.argv.includes('--check');

const entries = [
  { name: 'bridge', entryPoint: resolve(webRoot, 'src/bridge/entry.ts') },
  { name: 'window-manager', entryPoint: resolve(webRoot, 'src/desktop/shell-entry.ts') },
  { name: 'winbox-preview', entryPoint: resolve(webRoot, 'src/winbox-preview/entry.ts') },
  { name: 'wterm-preview', entryPoint: resolve(webRoot, 'src/wterm-preview/entry.ts') }
];

for (const { name, entryPoint } of entries) {
  const options = {
    entryPoints: [entryPoint],
    outfile: resolve(outputDirectory, `${name}.js`),
    bundle: true,
    format: 'iife',
    platform: 'browser',
    target: ['safari17'],
    loader: { '.svg': 'dataurl' },
    alias: { 'node:zlib': resolve(webRoot, 'src/shims/node-zlib.ts') },
    sourcemap: 'linked',
    sourcesContent: true,
    legalComments: 'none',
    logLevel: 'info'
  };

  if (!check) {
    await build(options);
    continue;
  }

  const result = await build({ ...options, write: false });
  for (const output of result.outputFiles) {
    const fileName = basename(output.path);
    const committed = await readFile(resolve(outputDirectory, fileName), 'utf8');
    if (committed !== output.text) {
      console.error(`Committed bundle is stale: AirDesk/Resources/DesktopShell/${fileName}`);
      process.exit(1);
    }
  }
  console.log(`Committed DesktopShell bundle matches web/src: ${name}`);
}
