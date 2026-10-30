import { BashShell } from '@wterm/just-bash';
import { WTermEngine } from '../terminal/wterm-engine';
import './preview.css';

const host = document.getElementById('terminal');
const status = document.getElementById('wterm-status');
const selfTest = document.getElementById('wterm-self-test');

if (!host) throw new Error('wterm preview host is missing');

const api = window.AD;

function log(message: string): void {
  api?.post({
    version: 1,
    type: 'log',
    sessionId: api.sessionId,
    generation: api.generation,
    message: `wterm ${message}`
  });
}

function setStatus(message: string): void {
  if (status) status.textContent = message;
}

function sleep(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitForOutput(marker: string, timeout = 5_000): Promise<boolean> {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    try {
      const text = await engine.readText();
      if (text.includes(marker)) return true;
    } catch {
      // A write can invalidate an in-flight capture; retry after painting.
    }
    await sleep(100);
  }
  return false;
}

let shell: BashShell | null = null;

const engine = new WTermEngine(host, {
  cols: 80,
  rows: 24,
  autoResize: false,
  transport: {
    send(data) {
      void shell?.handleInput(data).catch((error: unknown) => {
        log(`input error ${String(error)}`);
      });
    }
  },
  announceOutput: true,
  onBell: () => log('bell')
});

function nextFrame(): Promise<void> {
  return new Promise((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
  });
}

async function start(): Promise<void> {
  await nextFrame();
  await engine.connect();
  await nextFrame();
  engine.fit();
  shell = new BashShell({
    files: {
      '/home/user/README.md': '# AirDesk wterm preview\n\nThe terminal is rendered by wterm and executed by just-bash.\n',
      '/home/user/notes.txt': 'wterm 0.5.7\njust-bash 3.6.0\n'
    },
    greeting: [
      'AirDesk wterm preview',
      'wterm 0.5.7 · just-bash 3.6.0 · offline virtual filesystem',
      'Type help, ls, or cat notes.txt.'
    ],
    prompt: (cwd) => `airdesk:${cwd}$ `
  });
  await shell.attach((data) => engine.write(data));
  engine.focus();
  setStatus('Ready · just-bash');
  log('ready bash');
  api?.viewport();
  api?.ready();
  api?.state('wterm-preview-ready');
}

async function runSelfTest(): Promise<void> {
  if (!shell) return;
  setStatus('Running self test…');
  log('self-test start');
  await shell.handleInput("echo wterm-ok\r");
  const passed = await waitForOutput('wterm-ok');
  if (!passed) {
    try {
      const snapshot = await engine.readText();
      log(`self-test snapshot ${JSON.stringify(snapshot.slice(-160))}`);
    } catch (error) {
      log(`self-test read error ${String(error)}`);
    }
  }
  setStatus(passed ? 'Self test passed' : 'Self test failed');
  log(passed ? 'self-test ok' : 'self-test failed');
}

selfTest?.addEventListener('click', () => {
  void runSelfTest();
});

start()
  .then(() => {
    window.setTimeout(() => {
      void runSelfTest();
    }, 250);
  })
  .catch((error: unknown) => {
    const message = String(error instanceof Error ? error.message : error);
    setStatus(`Failed: ${message}`);
    log(`failed ${message}`);
    api?.error(message);
  });
