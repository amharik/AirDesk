import { WTerm } from '@wterm/dom';
import type { WTermOptions } from '@wterm/dom';
import type { TerminalEngine, TerminalTransport } from './terminal-engine';

export interface WTermEngineOptions extends WTermOptions {
  transport: TerminalTransport;
}

export class WTermEngine implements TerminalEngine {
  readonly element: HTMLElement;
  private readonly transport: TerminalTransport;
  private readonly terminal: WTerm;
  private readonly pending: Array<string | Uint8Array> = [];
  private ready = false;

  constructor(element: HTMLElement, options: WTermEngineOptions) {
    const { transport, onData, onBinary, onResize, ...terminalOptions } = options;
    this.element = element;
    this.transport = transport;
    this.terminal = new WTerm(element, {
      autoResize: true,
      ...terminalOptions,
      onData: (data) => {
        onData?.(data);
        transport.send(data);
      },
      onBinary: (data) => {
        onBinary?.(data);
        transport.sendBinary?.(data);
      },
      onResize: (cols, rows) => {
        onResize?.(cols, rows);
        transport.resize?.(cols, rows);
      }
    });
  }

  async connect(): Promise<void> {
    await this.terminal.init();
    this.terminal.fit();
    this.ready = true;
    for (const data of this.pending.splice(0)) this.terminal.write(data);
  }

  write(data: string | Uint8Array): void {
    if (!this.ready) {
      this.pending.push(data);
      return;
    }
    this.terminal.write(data);
  }

  input(data: string): void {
    this.transport.send(data);
  }

  paste(data: string): void {
    this.transport.send(data);
  }

  fit(): void {
    if (this.ready) this.terminal.fit();
  }

  focus(): void {
    if (this.ready) this.terminal.focus();
  }

  resize(cols: number, rows: number): void {
    if (this.ready) this.terminal.resize(cols, rows);
  }

  readText(): Promise<string> {
    return this.terminal.readText();
  }

  destroy(): void {
    this.ready = false;
    this.pending.length = 0;
    this.terminal.destroy();
  }
}
