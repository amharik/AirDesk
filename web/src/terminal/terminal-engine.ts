export interface TerminalTransport {
  send(data: string): void;
  sendBinary?(data: Uint8Array): void;
  resize?(cols: number, rows: number): void;
}

export interface TerminalEngine {
  readonly element: HTMLElement;
  connect(): Promise<void>;
  write(data: string | Uint8Array): void;
  input(data: string): void;
  paste(data: string): void;
  fit(): void;
  focus(): void;
  resize(cols: number, rows: number): void;
  readText(): Promise<string>;
  destroy(): void;
}
