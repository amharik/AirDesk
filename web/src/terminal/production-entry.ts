import './terminal.css';
import { GhosttyCore } from '@wterm/ghostty';
import { WTermEngine } from './wterm-engine';
import type { WTermEngineOptions } from './wterm-engine';
import type { TerminalEngine } from './terminal-engine';

export const GHOSTTY_SCROLLBACK_LIMIT = 16 * 1024 * 1024;

export interface AirDeskWTermRuntime {
  create(element: HTMLElement, options: WTermEngineOptions): Promise<TerminalEngine>;
}

declare global {
  interface Window {
    AirDeskWTerm?: AirDeskWTermRuntime;
  }
}

function coreURL(): string {
  return new URL('terminal-core.wasm', document.baseURI).href;
}

window.AirDeskWTerm = {
  async create(element, options) {
    const core = await GhosttyCore.load({
      wasmPath: coreURL(),
      scrollbackLimit: GHOSTTY_SCROLLBACK_LIMIT
    });
    return new WTermEngine(element, { ...options, core });
  }
};
