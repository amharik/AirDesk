import { JSDOM } from 'jsdom';
import { afterEach, beforeAll, describe, expect, it } from 'vitest';
import { WinBoxWindowManager } from '../src/desktop/window-manager';
import type { WinBoxFactory } from '../src/desktop/window-manager';

let factory: WinBoxFactory;
let dom: JSDOM;

beforeAll(async () => {
  dom = new JSDOM('<!doctype html><html><body></body></html>', {
    pretendToBeVisual: true,
    url: 'https://airdesk.test/'
  });
  for (const key of [
    'window',
    'document',
    'navigator',
    'HTMLElement',
    'Element',
    'Node',
    'MouseEvent',
    'Event',
    'CustomEvent',
    'getComputedStyle',
    'requestAnimationFrame',
    'cancelAnimationFrame'
  ] as const) {
    Object.defineProperty(globalThis, key, {
      value: dom.window[key as keyof typeof dom.window],
      configurable: true,
      writable: true
    });
  }
  const { createWinBox } = await import('../src/desktop/winbox');
  factory = createWinBox;
});

const managers: WinBoxWindowManager[] = [];

afterEach(() => {
  for (const manager of managers.splice(0)) {
    for (const id of manager.getFocusOrder()) manager.get(id)?.close();
  }
});

function createManager(): { manager: WinBoxWindowManager; root: HTMLElement } {
  const root = document.createElement('section');
  document.body.appendChild(root);
  const manager = new WinBoxWindowManager({ root, factory });
  managers.push(manager);
  return { manager, root };
}

function openTerminal(manager: WinBoxWindowManager): ReturnType<WinBoxWindowManager['open']> {
  const content = document.createElement('div');
  content.textContent = 'terminal canvas';
  return manager.open({
    id: 'terminal',
    title: 'Terminal',
    appName: 'Wanix Terminal',
    bounds: { x: 24, y: 60, width: 420, height: 300 },
    content
  });
}

describe('WinBox window manager', () => {
  it('uses AirDesk chrome while WinBox owns window mechanics', () => {
    const { manager, root } = createManager();
    const handle = openTerminal(manager);

    expect(root.querySelector('.winbox.airdesk-window')).toBe(handle.element);
    expect(handle.element.getAttribute('data-app')).toBe('terminal');
    expect(handle.element.getAttribute('role')).toBe('dialog');
    expect(handle.element.getAttribute('aria-label')).toBe('Wanix Terminal');
    expect(handle.element.querySelector('.wb-title')?.textContent).toBe('Terminal');
    expect(handle.element.querySelector('.airdesk-window-body')?.textContent).toBe('terminal canvas');

    const traffic = [...handle.element.querySelectorAll<HTMLButtonElement>('.traffic button')];
    expect(traffic.map((button) => button.dataset.windowAction)).toEqual([
      'close',
      'minimize',
      'maximize'
    ]);
    expect(traffic.map((button) => button.getAttribute('aria-label'))).toEqual([
      'Close',
      'Minimize',
      'Maximize'
    ]);

    for (const handleClass of ['wb-drag', 'wb-n', 'wb-s', 'wb-w', 'wb-e', 'wb-nw', 'wb-ne', 'wb-se', 'wb-sw']) {
      expect(handle.element.querySelectorAll(`.${handleClass}`)).toHaveLength(1);
    }
  });

  it('tracks focus order and exposes normalized input conversion', () => {
    const { manager } = createManager();
    const terminal = openTerminal(manager);
    const notes = manager.open({
      id: 'notes',
      title: 'Notes',
      bounds: { x: 80, y: 80, width: 360, height: 260 }
    });

    expect(manager.getFocusOrder()).toEqual(['terminal', 'notes']);
    expect(manager.topmost()?.id).toBe('notes');

    terminal.focus();
    expect(manager.getFocusOrder()).toEqual(['notes', 'terminal']);
    expect(manager.topmost()?.id).toBe('terminal');
    expect(notes.element.classList.contains('focus')).toBe(false);

    Object.defineProperty(terminal.element, 'getBoundingClientRect', {
      value: () => ({ left: 100, top: 50, width: 200, height: 100, right: 300, bottom: 150 })
    });
    expect(manager.clientToWindowPoint('terminal', 150, 75)).toEqual({ x: 50, y: 25 });
  });

  it('routes AirDesk traffic lights through WinBox lifecycle', () => {
    const { manager } = createManager();
    const handle = openTerminal(manager);
    const click = (action: string): void => {
      handle.element.querySelector<HTMLButtonElement>(`[data-window-action="${action}"]`)!.click();
    };

    click('minimize');
    expect(handle.element.classList.contains('min')).toBe(true);
    expect(manager.getFocusOrder()).toEqual([]);
    expect(manager.topmost()).toBeUndefined();

    handle.restore();
    click('maximize');
    expect(handle.element.classList.contains('max')).toBe(true);
    click('maximize');
    expect(handle.element.classList.contains('max')).toBe(false);

    click('close');
    expect(handle.closed).toBe(true);
    expect(manager.get('terminal')).toBeUndefined();
    expect(handle.element.isConnected).toBe(false);
  });

  it('honors close vetoes and replaces duplicate ids with a focus call', () => {
    const { manager } = createManager();
    let veto = true;
    const handle = manager.open({
      id: 'settings',
      title: 'Settings',
      bounds: { x: 10, y: 40, width: 380, height: 260 },
      onBeforeClose: () => !veto
    });

    handle.close();
    expect(handle.closed).toBe(false);
    expect(manager.get('settings')).toBe(handle);

    veto = false;
    expect(
      manager.open({
        id: 'settings',
        title: 'Duplicate',
        bounds: { x: 10, y: 40, width: 380, height: 260 }
      })
    ).toBe(handle);
    handle.close();
    expect(handle.closed).toBe(true);
  });

  it('clamps windows back into view after rotation or inset changes', () => {
    const { manager } = createManager();
    const handle = manager.open({
      id: 'terminal',
      title: 'Terminal',
      bounds: { x: 820, y: 620, width: 460, height: 320 }
    });

    Object.defineProperty(dom.window, 'innerWidth', { value: 600, configurable: true, writable: true });
    Object.defineProperty(dom.window, 'innerHeight', { value: 700, configurable: true, writable: true });
    try {
      handle.setViewportInsets({ top: 39, right: 0, bottom: 96, left: 0 });

      const left = parseFloat(handle.element.style.left);
      const top = parseFloat(handle.element.style.top);
      expect(left).toBeGreaterThanOrEqual(0);
      expect(left).toBeLessThanOrEqual(480);
      expect(top).toBeGreaterThanOrEqual(39);
      expect(top).toBeLessThanOrEqual(524);
    } finally {
      Object.defineProperty(dom.window, 'innerWidth', { value: 1024, configurable: true, writable: true });
      Object.defineProperty(dom.window, 'innerHeight', { value: 768, configurable: true, writable: true });
    }
  });
});
