import WinBox from 'winbox/src/js/winbox.js';
import type { WinBoxFactory } from './window-manager';

export const createWinBox: WinBoxFactory = (options) => new WinBox(options);
