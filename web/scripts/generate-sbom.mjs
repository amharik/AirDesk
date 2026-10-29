import { execFileSync } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const outputDirectory = join(webRoot, 'build');
const outputPath = join(outputDirectory, 'sbom.cdx.json');
const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';

const sbom = execFileSync(
  npm,
  ['sbom', '--sbom-format', 'cyclonedx', '--sbom-type', 'application'],
  {
    cwd: webRoot,
    encoding: 'utf8',
    maxBuffer: 32 * 1024 * 1024,
    stdio: ['ignore', 'pipe', 'inherit']
  }
);

await mkdir(outputDirectory, { recursive: true });
await writeFile(outputPath, sbom);
console.log(`Wrote ${outputPath} (${Buffer.byteLength(sbom)} bytes).`);
