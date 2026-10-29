export interface BridgeMessage extends Record<string, unknown> {
  version?: number;
  type?: string;
  sessionId?: string;
  generation?: number;
}

export interface BridgeInputEvent extends BridgeMessage {
  seq?: number;
}

export interface BridgeControlMessage extends BridgeMessage {
  appearance?: string;
}

export type InputHandler = (event: BridgeInputEvent) => void;
export type ControlHandler = (message: BridgeControlMessage) => void;

export interface AirDeskBridge {
  receive(event: unknown): void;
  receiveControl(message: unknown): void;
}

export interface AirDeskAPI {
  sessionId: string;
  generation: number;
  host: string;
  runtime: string;
  device: string;
  native: boolean;
  appearance: string;
  post(message: BridgeMessage): boolean;
  ready(): void;
  viewport(width?: number, height?: number): void;
  notice(text?: string): void;
  state(name?: string): void;
  error(message?: string): void;
  onInput(handler: InputHandler): void;
  onControl(handler: ControlHandler): void;
}

declare global {
  interface Window {
    AirDeskBridge?: AirDeskBridge;
    AD?: AirDeskAPI;
    AirDeskKernel?: { persistence?: () => string };
    AIRDESK_SESSION_ID?: string;
    AIRDESK_GENERATION?: string | number;
    AIRDESK_HOST?: string;
    AIRDESK_PARENT_ORIGIN?: string;
    AIRDESK_RUNTIME?: string;
    AIRDESK_APPEARANCE?: string;
    AIRDESK_DEVICE_NAME?: string;
  }
}
