import { WinBoxWindowManager } from '../desktop/window-manager';
import { createWinBox } from '../desktop/winbox';
import './preview.css';

const layer = document.getElementById('window-layer');
const activeApp = document.getElementById('active-app');
const clock = document.getElementById('clock');

if (!layer) throw new Error('WinBox preview layer is missing');

const api = window.AD;

function log(message: string): void {
  api?.post({
    version: 1,
    type: 'log',
    sessionId: api.sessionId,
    generation: api.generation,
    message: `wm ${message}`
  });
}

function setActive(title: string): void {
  if (activeApp) activeApp.textContent = title;
}

const manager = new WinBoxWindowManager({
  root: layer,
  factory: createWinBox,
  insets: { top: 31, bottom: 96 }
});

manager.open({
  id: 'terminal',
  title: 'Terminal',
  appName: 'Terminal',
  bounds: { x: 72, y: 82, width: 610, height: 380 },
  minWidth: 420,
  minHeight: 240,
  content: `
    <div class="preview-terminal">
      <div class="preview-terminal-head"><span>AirDesk shell</span><span>zsh</span></div>
      <pre>Last login: today on ttys001
airdesk 0.2 · bundled Wanix workspace

The WinBox parity harness is running inside WKWebView.
Window geometry, focus order, and lifecycle events are live.</pre>
      <div class="preview-prompt"><span>airdesk@studio</span> ~ %</div>
    </div>
  `,
  onFocus: () => {
    setActive('Terminal');
    log('focus terminal');
  },
  onMove: (x, y) => log(`move terminal ${Math.round(x)},${Math.round(y)}`),
  onResize: (width, height) => log(`resize terminal ${Math.round(width)}x${Math.round(height)}`),
  onMinimize: () => log('minimize terminal'),
  onMaximize: () => log('maximize terminal'),
  onRestore: () => log('restore terminal'),
  onBeforeClose: () => {
    log('closing terminal');
    return true;
  },
  onClosed: () => log('closed terminal')
});

manager.open({
  id: 'notes',
  title: 'Notes',
  appName: 'Notes',
  bounds: { x: 238, y: 150, width: 560, height: 350 },
  minWidth: 420,
  minHeight: 250,
  content: `
    <div class="preview-notes">
      <aside class="preview-notes-sidebar">
        <strong>Notes</strong>
        <div class="preview-note-item active">WinBox qualification</div>
        <div class="preview-note-item">Input protocol</div>
        <div class="preview-note-item">Display transport</div>
      </aside>
      <div class="preview-note-page">
        <h2>WinBox qualification</h2>
        <p>Upstream WinBox now drives geometry and lifecycle while AirDesk owns the titlebar, glass surfaces, and traffic controls.</p>
        <p>This preview validates the real package in the simulator before the production desktop switches over.</p>
        <div class="preview-pills"><span class="preview-pill">WKWebView</span><span class="preview-pill">AirDesk chrome</span><span class="preview-pill">No fork</span></div>
      </div>
    </div>
  `,
  onFocus: () => {
    setActive('Notes');
    log('focus notes');
  },
  onMove: (x, y) => log(`move notes ${Math.round(x)},${Math.round(y)}`),
  onResize: (width, height) => log(`resize notes ${Math.round(width)}x${Math.round(height)}`),
  onMinimize: () => log('minimize notes'),
  onMaximize: () => log('maximize notes'),
  onRestore: () => log('restore notes'),
  onBeforeClose: () => {
    log('closing notes');
    return true;
  },
  onClosed: () => log('closed notes')
});

manager.open({
  id: 'welcome',
  title: 'Welcome',
  appName: 'Welcome',
  bounds: { x: 350, y: 225, width: 470, height: 330 },
  minWidth: 400,
  minHeight: 280,
  content: `
    <div class="preview-welcome">
      <div class="app-icon app-icon-welcome hero"><span class="app-icon-inner"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M12 3.5 14.4 9l5.6.6-4.2 3.8 1.2 5.6L12 16.2 7 19l1.2-5.6L4 9.6 9.6 9 12 3.5Z"/></svg></span></div>
      <h1>AirDesk</h1>
      <p>A macOS-style workspace for iPad, with native input, external displays, and a portable web runtime.</p>
      <div class="preview-pills"><span class="preview-pill">Window manager harness</span><span class="preview-pill">Simulator ready</span></div>
    </div>
  `,
  onFocus: () => {
    setActive('Welcome');
    log('focus welcome');
  },
  onMove: (x, y) => log(`move welcome ${Math.round(x)},${Math.round(y)}`),
  onResize: (width, height) => log(`resize welcome ${Math.round(width)}x${Math.round(height)}`),
  onMinimize: () => log('minimize welcome'),
  onMaximize: () => log('maximize welcome'),
  onRestore: () => log('restore welcome'),
  onBeforeClose: () => {
    log('closing welcome');
    return true;
  },
  onClosed: () => log('closed welcome')
});

function updateClock(): void {
  if (!clock) return;
  clock.textContent = new Intl.DateTimeFormat(undefined, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit'
  }).format(new Date());
}

function updateInsets(): void {
  const menubar = document.getElementById('menubar');
  const dock = document.getElementById('dock-shell');
  manager.setViewportInsets({
    top: (menubar?.getBoundingClientRect().height ?? 27) + 4,
    bottom: Math.max(0, window.innerHeight - (dock?.getBoundingClientRect().top ?? window.innerHeight - 96) + 10)
  });
}

document.body.dataset.wallpaper = 'aurora';
document.body.dataset.appearance = api?.appearance === 'light' ? 'light' : 'dark';
updateClock();
updateInsets();
setInterval(updateClock, 30_000);
window.addEventListener('resize', updateInsets);

requestAnimationFrame(() => {
  requestAnimationFrame(() => {
    api?.viewport();
    api?.ready();
    log('ready');
    api?.state('winbox-preview-ready');
  });
});
