declare module 'winbox/src/js/winbox.js' {
  import type { WinBoxInstance, WinBoxOptions } from './window-manager';

  const WinBox: new (options: WinBoxOptions) => WinBoxInstance;
  export default WinBox;
}
