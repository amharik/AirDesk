import type { SemanticTerminalModel } from './semantic-blocks';
import type {
  AgentCapabilityGrant,
  AgentControlAction,
  AgentControlDecision,
  AgentSupervisionModel,
  AgentSupervisionSnapshot
} from './agent-supervision';

export interface TerminalTransport {
  send(data: string): void;
  sendBinary?(data: Uint8Array): void;
  resize?(cols: number, rows: number): void;
}

export interface TerminalEngine {
  readonly element: HTMLElement;
  readonly semanticBlocks?: SemanticTerminalModel;
  readonly agentSupervision?: AgentSupervisionModel;
  connect(): Promise<void>;
  write(data: string | Uint8Array): void;
  input(data: string): void;
  paste(data: string): void;
  fit(): void;
  focus(): void;
  resize(cols: number, rows: number): void;
  readText(): Promise<string>;
  destroy(): void;
  agentSnapshot?(now?: number): AgentSupervisionSnapshot;
  agentControl?(
    action: AgentControlAction,
    payload: string,
    grant: AgentCapabilityGrant | null | undefined,
    now?: number
  ): AgentControlDecision;
}
