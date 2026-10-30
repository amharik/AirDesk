import { BashShell } from '@wterm/just-bash';
import { describe, expect, it } from 'vitest';

async function waitForOutput(chunks: string[], marker: string, timeout = 3_000): Promise<boolean> {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (chunks.join('').includes(marker)) return true;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  return chunks.join('').includes(marker);
}

describe('just-bash terminal session', () => {
  it('runs commands against the virtual filesystem', async () => {
    const chunks: string[] = [];
    const shell = new BashShell({
      files: {
        '/home/user/hello.txt': 'hello from just-bash\n'
      },
      greeting: 'ready',
      prompt: () => '$ '
    });

    await shell.attach((data) => chunks.push(data));
    await shell.handleInput('cat hello.txt\r');

    expect(await waitForOutput(chunks, 'hello from just-bash')).toBe(true);
    expect(chunks.join('')).toContain('ready');
  });

  it('updates the working directory after cd', async () => {
    const chunks: string[] = [];
    const shell = new BashShell({
      files: {
        '/home/user/projects/readme.txt': 'project\n'
      },
      prompt: (cwd) => `${cwd}$ `
    });

    await shell.attach((data) => chunks.push(data));
    await shell.handleInput('cd projects\r');
    await shell.handleInput('pwd\r');

    expect(shell.cwd).toBe('/home/user/projects');
    expect(await waitForOutput(chunks, '/home/user/projects')).toBe(true);
  });

  it('echoes the self-test marker', async () => {
    const chunks: string[] = [];
    const shell = new BashShell({ prompt: () => '$ ' });
    await shell.attach((data) => chunks.push(data));
    await shell.handleInput('echo wterm-ok\r');

    expect(await waitForOutput(chunks, 'wterm-ok')).toBe(true);
  });
});
