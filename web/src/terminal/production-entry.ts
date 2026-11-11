import './terminal.css';
import { GhosttyCore } from '@wterm/ghostty';
import {
  createIndexedDBTranscriptStore,
  formatTranscriptReplay,
  readTranscript,
  saveTranscript
} from './terminal-transcript';
import type { TranscriptStore } from './terminal-transcript';
import {
  SemanticTerminalModel,
  copyBlockOutput,
  formatBlockMarkdown
} from './semantic-blocks';
import {
  AgentSupervisionModel,
  agentBadgeLabel,
  redactSensitiveText
} from './agent-supervision';
import { WTermEngine } from './wterm-engine';
import type { WTermEngineOptions } from './wterm-engine';
import type { TerminalEngine } from './terminal-engine';

export const GHOSTTY_SCROLLBACK_LIMIT = 16 * 1024 * 1024;

export interface AirDeskWTermTranscript {
  createStore(): TranscriptStore;
  read(store: TranscriptStore, sessionId: string, limit?: number): Promise<string>;
  save(store: TranscriptStore, text: string, sessionId: string, limit?: number): Promise<string>;
  replay(text: string, limit?: number): string;
}

export interface AirDeskWTermSemantic {
  create(): SemanticTerminalModel;
  copyOutput(block: Parameters<typeof copyBlockOutput>[0]): string;
  markdown(block: Parameters<typeof formatBlockMarkdown>[0]): string;
}

export interface AirDeskWTermAgent {
  create(): AgentSupervisionModel;
  badgeLabel: typeof agentBadgeLabel;
  redact: typeof redactSensitiveText;
}

export interface AirDeskWTermRuntime {
  create(element: HTMLElement, options: WTermEngineOptions): Promise<TerminalEngine>;
  transcript: AirDeskWTermTranscript;
  semantic: AirDeskWTermSemantic;
  agent: AirDeskWTermAgent;
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
  },
  transcript: {
    createStore: () => createIndexedDBTranscriptStore(),
    read: readTranscript,
    save: saveTranscript,
    replay: formatTranscriptReplay
  },
  semantic: {
    create: () => new SemanticTerminalModel(),
    copyOutput: copyBlockOutput,
    markdown: formatBlockMarkdown
  },
  agent: {
    create: () => new AgentSupervisionModel(),
    badgeLabel: agentBadgeLabel,
    redact: redactSensitiveText
  }
};
