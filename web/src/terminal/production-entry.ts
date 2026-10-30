import './terminal.css';
import { WTermEngine } from './wterm-engine';
import type { WTermEngineOptions } from './wterm-engine';
import type { TerminalEngine } from './terminal-engine';

export interface AirDeskWTermRuntime {
  create(element: HTMLElement, options: WTermEngineOptions): TerminalEngine;
}

declare global {
  interface Window {
    AirDeskWTerm?: AirDeskWTermRuntime;
  }
}

window.AirDeskWTerm = {
  create(element, options) {
    return new WTermEngine(element, options);
  }
};
