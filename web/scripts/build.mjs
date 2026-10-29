import { readFile } from 'node:fs/promises';
import { basename, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repositoryRoot = resolve(webRoot, '..');
const outputDirectory = resolve(repositoryRoot, 'AirDesk/Resources/DesktopShell');
const entryPoint = resolve(webRoot, 'src/bridge/entry.ts');
const check = process.argv.includes('--check');

const options = {
  entryPoints: [entryPoint],
  outfile: resolve(outputDirectory, 'bridge.js'),
  bundle: true,
  format: 'iife',
  platform: 'browser',
  target: ['safari17'],
  sourcemap: 'linked',
  sourcesContent: true,
  legalComments: 'none',
  logLevel: 'info'
};

if (!check) {
  await build(options);
} else {
  const result = await build({ ...options, write: false });
  for (const output of result.outputFiles) {
    const name = basename(output.path);
    const committed = await readFile(resolve(outputDirectory, name), 'utf8');
    if (committed !== output.text) {
      console.error(`Committed bundle is stale: AirDesk/Resources/DesktopShell/${name}`);
      process.exit(1);
    }
  }
  console.log('Committed DesktopShell bundle matches web/src.');
}
