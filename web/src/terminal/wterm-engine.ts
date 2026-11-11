import { WTerm } from '@wterm/dom';
import type { WTermOptions } from '@wterm/dom';
import {
  SemanticBlockPanel,
  SemanticTerminalModel
} from './semantic-blocks';
import type {
  SemanticBlockPanelOptions,
  SemanticBlockSnapshot
} from './semantic-blocks';
import {
  AgentSupervisionBadge,
  AgentSupervisionModel
} from './agent-supervision';
import type {
  AgentCapabilityGrant,
  AgentControlAction,
  AgentControlDecision,
  AgentSupervisionSnapshot
} from './agent-supervision';
import type { TerminalEngine, TerminalTransport } from './terminal-engine';

export interface WTermEngineOptions extends WTermOptions {
  transport: TerminalTransport;
  semanticBlocks?: boolean | SemanticBlockPanelOptions;
  onSemanticBlocks?: (snapshot: SemanticBlockSnapshot) => void;
  agentBadge?: boolean;
  onAgentSupervision?: (snapshot: AgentSupervisionSnapshot) => void;
}

export class WTermEngine implements TerminalEngine {
  readonly element: HTMLElement;
  readonly semanticBlocks = new SemanticTerminalModel();
  readonly agentSupervision = new AgentSupervisionModel();
  private readonly transport: TerminalTransport;
  private readonly terminal: WTerm;
  private readonly panel?: SemanticBlockPanel;
  private readonly badge?: AgentSupervisionBadge;
  private readonly onSemanticBlocks?: (snapshot: SemanticBlockSnapshot) => void;
  private readonly onAgentSupervision?: (snapshot: AgentSupervisionSnapshot) => void;
  private readonly pending: Array<string | Uint8Array> = [];
  private ready = false;

  constructor(element: HTMLElement, options: WTermEngineOptions) {
    const {
      transport,
      onData,
      onBinary,
      onResize,
      semanticBlocks,
      onSemanticBlocks,
      agentBadge,
      onAgentSupervision,
      ...terminalOptions
    } = options;
    this.element = element;
    this.transport = transport;
    this.onSemanticBlocks = onSemanticBlocks;
    this.onAgentSupervision = onAgentSupervision;
    this.agentSupervision.setConnected(false);
    const parent = element.parentElement;
    if (agentBadge || semanticBlocks) {
      this.badge = new AgentSupervisionBadge();
      if (parent) parent.insertBefore(this.badge.element, element.nextSibling);
      else element.appendChild(this.badge.element);
    }
    if (semanticBlocks) {
      this.panel = new SemanticBlockPanel({
        ...(semanticBlocks === true ? {} : semanticBlocks),
        resolveBlock: (id) => this.semanticBlocks.snapshot().blocks.find((block) => block.id === id)
      });
      if (parent) parent.insertBefore(this.panel.element, element.nextSibling);
      else element.appendChild(this.panel.element);
    }
    this.terminal = new WTerm(element, {
      autoResize: true,
      ...terminalOptions,
      onData: (data) => {
        this.semanticBlocks.noteInput(data);
        this.publishAgent();
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
    this.agentSupervision.setConnected(true);
    this.publishAgent();
    for (const data of this.pending.splice(0)) this.terminal.write(data);
  }

  write(data: string | Uint8Array): void {
    this.publishSemantic(this.semanticBlocks.consume(data));
    if (!this.ready) {
      this.pending.push(data);
      return;
    }
    this.terminal.write(data);
  }

  input(data: string): void {
    this.semanticBlocks.noteInput(data);
    this.publishAgent();
    this.transport.send(data);
  }

  paste(data: string): void {
    this.semanticBlocks.noteInput(data);
    this.publishAgent();
    this.transport.send(data);
  }

  agentSnapshot(now = Date.now()): AgentSupervisionSnapshot {
    return this.agentSupervision.snapshot(now);
  }

  agentControl(
    action: AgentControlAction,
    payload: string,
    grant: AgentCapabilityGrant | null | undefined,
    now = Date.now()
  ): AgentControlDecision {
    const decision = this.agentSupervision.apply(
      action,
      payload,
      grant,
      (data) => this.transport.send(data),
      now
    );
    if (decision.authorized) {
      this.semanticBlocks.noteInput(payload);
      this.publishAgent();
    }
    return decision;
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

  setRenderingPaused(paused: boolean): void {
    this.terminal.setRenderingPaused(paused);
  }

  readText(): Promise<string> {
    return this.terminal.readText();
  }

  destroy(): void {
    this.ready = false;
    this.pending.length = 0;
    this.agentSupervision.setConnected(false);
    this.publishAgent();
    this.panel?.destroy();
    this.badge?.destroy();
    this.terminal.destroy();
  }

  private publishSemantic(changed: ReturnType<SemanticTerminalModel['consume']>): void {
    if (changed.length === 0) return;
    const snapshot = this.semanticBlocks.snapshot();
    this.onSemanticBlocks?.(snapshot);
    this.panel?.render(snapshot);
    this.publishAgent();
  }

  private publishAgent(): void {
    this.agentSupervision.observe(this.semanticBlocks.snapshot());
    if (!this.badge && !this.onAgentSupervision) return;
    const snapshot = this.agentSupervision.snapshot();
    this.badge?.render(snapshot);
    this.onAgentSupervision?.(snapshot);
  }
}
