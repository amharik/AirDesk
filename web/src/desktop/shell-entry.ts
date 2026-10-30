import WinBox from 'winbox/src/js/winbox.js';
import { WinBoxWindowManager, type WindowInsets } from './window-manager';
import './shell-runtime.css';

export interface AirDeskWinBoxRuntimeOptions {
  root: HTMLElement;
  insets?: Partial<WindowInsets>;
}

export interface AirDeskWinBoxRuntime {
  createManager(options: AirDeskWinBoxRuntimeOptions): WinBoxWindowManager;
}

declare global {
  interface Window {
    AirDeskWinBox?: AirDeskWinBoxRuntime;
  }
}

window.AirDeskWinBox = {
  createManager(options) {
    return new WinBoxWindowManager({
      root: options.root,
      factory: (settings) => new WinBox(settings),
      insets: options.insets
    });
  }
};
