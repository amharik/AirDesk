export const SEMANTIC_BLOCK_LIMIT = 200;
export const SEMANTIC_TEXT_LIMIT = 65_536;
export const SEMANTIC_CONTROL_LIMIT = 4_096;

const OSC133_PREFIX = '\x1b]133;';

export type SemanticCommandState = 'prompt' | 'input' | 'running' | 'finished' | 'interrupted';
export type SemanticExitAura = 'pending' | 'running' | 'success' | 'failure' | 'interrupted';

export interface SemanticCommandBlock {
  id: number;
  state: SemanticCommandState;
  command: string;
  output: string;
  exitCode: number | null;
  startedAtSequence: number;
  updatedAtSequence: number;
}

export interface SemanticBlockSnapshot {
  blocks: SemanticCommandBlock[];
  activeBlockId: number | null;
  lastSequence: number;
  unconfirmedInputBytes: number;
}

export interface SemanticBlockPanelOptions {
  onCopy?: (text: string) => void | Promise<void>;
  maximumVisible?: number;
  resolveBlock?: (id: number) => SemanticCommandBlock | undefined;
}

function trimText(value: string): string {
  return value.length <= SEMANTIC_TEXT_LIMIT ? value : value.slice(0, SEMANTIC_TEXT_LIMIT);
}

function partialPrefixLength(value: string): number {
  const maximum = Math.min(OSC133_PREFIX.length - 1, value.length);
  for (let length = maximum; length > 0; length -= 1) {
    if (value.endsWith(OSC133_PREFIX.slice(0, length))) return length;
  }
  return 0;
}

function sanitizeControlSequences(value: string): string {
  const escape = String.fromCharCode(27);
  const bell = String.fromCharCode(7);
  let text = '';
  let index = 0;
  while (index < value.length) {
    const character = value[index]!;
    if (character === escape) {
      const next = value[index + 1];
      if (next === ']') {
        index += 2;
        while (index < value.length) {
          if (value[index] === bell) {
            index += 1;
            break;
          }
          if (value[index] === escape && value[index + 1] === '\\') {
            index += 2;
            break;
          }
          index += 1;
        }
        continue;
      }
      if (next === 'P' || next === '^' || next === '_') {
        index += 2;
        while (index < value.length) {
          if (value[index] === escape && value[index + 1] === '\\') {
            index += 2;
            break;
          }
          index += 1;
        }
        continue;
      }
      if (next === '[') {
        index += 2;
        while (index < value.length) {
          const code = value.charCodeAt(index);
          index += 1;
          if (code >= 0x40 && code <= 0x7e) break;
        }
        continue;
      }
      index += next === '(' || next === ')' ? 3 : 2;
      continue;
    }
    if (character === '\r') {
      if (value[index + 1] !== '\n') text += '\n';
      index += 1;
      continue;
    }
    const code = value.charCodeAt(index);
    if ((code < 0x20 && character !== '\n' && character !== '\t') || (code >= 0x7f && code < 0xa0)) {
      index += 1;
      continue;
    }
    text += character;
    index += 1;
  }
  return text.replace(/\n{3,}/g, '\n\n');
}

export function sanitizeTerminalText(value: string): string {
  return sanitizeControlSequences(value).trim();
}

export function isConfirmedBlock(block: SemanticCommandBlock): boolean {
  return block.state === 'running' || block.state === 'finished' || block.state === 'interrupted';
}

export function exitAura(block: SemanticCommandBlock): SemanticExitAura {
  if (block.state === 'interrupted') return 'interrupted';
  if (block.state === 'prompt' || block.state === 'input') return 'pending';
  if (block.state === 'running') return 'running';
  return block.exitCode === 0 ? 'success' : 'failure';
}

export function copyBlockOutput(block: SemanticCommandBlock): string {
  if (!isConfirmedBlock(block)) return '';
  return sanitizeTerminalText(block.output);
}

function fenceFor(value: string): string {
  let longest = 0;
  for (const match of value.matchAll(/`+/g)) longest = Math.max(longest, match[0].length);
  return '`'.repeat(Math.max(3, longest + 1));
}

export function formatBlockMarkdown(block: SemanticCommandBlock): string {
  if (!isConfirmedBlock(block)) return '';
  const command = sanitizeTerminalText(block.command);
  const output = copyBlockOutput(block);
  const commandFence = fenceFor(command);
  const outputFence = fenceFor(output);
  const status = block.state === 'finished'
    ? `exit ${block.exitCode ?? 'unknown'}`
    : block.state;
  return [
    `### ${command.split('\n')[0] || 'Command'}`,
    '',
    `${commandFence}sh`,
    command,
    commandFence,
    '',
    `Status: ${status}`,
    '',
    `${outputFence}text`,
    output,
    outputFence
  ].join('\n');
}

export class SemanticTerminalModel {
  readonly allowsAutomaticRetry = false;

  private readonly decoder = new TextDecoder();
  private pending = '';
  private blocks: SemanticCommandBlock[] = [];
  private currentId: number | null = null;
  private nextId = 1;
  private sequence = 0;
  private unconfirmedInputBytes = 0;

  get lastSequence(): number {
    return this.sequence;
  }

  consume(data: string | Uint8Array, sequence?: number): SemanticCommandBlock[] {
    this.sequence = Math.max(this.sequence, sequence ?? this.sequence + 1);
    const text = typeof data === 'string' ? data : this.decoder.decode(data, { stream: true });
    if (!text) return [];
    const changed = new Set<number>();
    this.pending += text;

    for (;;) {
      const start = this.pending.indexOf(OSC133_PREFIX);
      if (start < 0) {
        const keep = partialPrefixLength(this.pending);
        this.appendOutput(this.pending.slice(0, this.pending.length - keep));
        this.pending = this.pending.slice(this.pending.length - keep);
        break;
      }

      const payloadStart = start + OSC133_PREFIX.length;
      const bell = this.pending.indexOf('\x07', payloadStart);
      const terminator = this.pending.indexOf('\x1b\\', payloadStart);
      let end = -1;
      let terminatorLength = 0;
      if (bell >= 0 && (terminator < 0 || bell < terminator)) {
        end = bell;
        terminatorLength = 1;
      } else if (terminator >= 0) {
        end = terminator;
        terminatorLength = 2;
      }

      this.appendOutput(this.pending.slice(0, start));
      if (end < 0) {
        this.pending = this.pending.slice(start, start + SEMANTIC_CONTROL_LIMIT);
        break;
      }

      this.handleControl(this.pending.slice(payloadStart, end), changed);
      this.pending = this.pending.slice(end + terminatorLength);
    }

    return this.blocks.filter((block) => changed.has(block.id)).map((block) => ({ ...block }));
  }

  noteInput(data: string): void {
    if (!data) return;
    this.unconfirmedInputBytes = Math.min(SEMANTIC_TEXT_LIMIT, this.unconfirmedInputBytes + data.length);
    if (data.includes('\x03')) this.interruptActive();
  }

  interruptActive(): void {
    if (this.currentId === null) return;
    const block = this.block(this.currentId);
    if (!block || block.state === 'finished') return;
    block.state = 'interrupted';
    block.updatedAtSequence = this.sequence;
    this.currentId = null;
  }

  snapshot(): SemanticBlockSnapshot {
    const active = this.currentId === null ? null : this.block(this.currentId);
    return {
      blocks: this.blocks.map((block) => ({ ...block })),
      activeBlockId: active && active.state !== 'finished' ? active.id : null,
      lastSequence: this.sequence,
      unconfirmedInputBytes: this.unconfirmedInputBytes
    };
  }

  copyOutput(id: number): string {
    const block = this.block(id);
    return block ? copyBlockOutput(block) : '';
  }

  markdown(id: number): string {
    const block = this.block(id);
    return block ? formatBlockMarkdown(block) : '';
  }

  private block(id: number): SemanticCommandBlock | undefined {
    return this.blocks.find((candidate) => candidate.id === id);
  }

  private startBlock(state: SemanticCommandState): SemanticCommandBlock {
    if (this.currentId !== null) {
      const previous = this.block(this.currentId);
      if (previous && previous.state !== 'finished') {
        previous.state = 'interrupted';
        previous.updatedAtSequence = this.sequence;
      }
    }
    const block: SemanticCommandBlock = {
      id: this.nextId,
      state,
      command: '',
      output: '',
      exitCode: null,
      startedAtSequence: this.sequence,
      updatedAtSequence: this.sequence
    };
    this.nextId += 1;
    this.blocks.push(block);
    this.currentId = block.id;
    if (this.blocks.length > SEMANTIC_BLOCK_LIMIT) {
      const dropped = this.blocks.splice(0, this.blocks.length - SEMANTIC_BLOCK_LIMIT);
      if (dropped.some((candidate) => candidate.id === this.currentId)) this.currentId = null;
    }
    return block;
  }

  private current(state?: SemanticCommandState): SemanticCommandBlock {
    const existing = this.currentId === null ? undefined : this.block(this.currentId);
    if (!existing || existing.state === 'finished' || existing.state === 'interrupted') {
      return this.startBlock(state ?? 'input');
    }
    if (state) existing.state = state;
    existing.updatedAtSequence = this.sequence;
    return existing;
  }

  private handleControl(payload: string, changed: Set<number>): void {
    const marker = payload[0];
    if (marker === 'A') {
      this.unconfirmedInputBytes = 0;
      const block = this.startBlock('prompt');
      changed.add(block.id);
      return;
    }
    if (marker === 'B') {
      this.unconfirmedInputBytes = 0;
      const block = this.current('input');
      block.command = '';
      block.output = '';
      block.exitCode = null;
      changed.add(block.id);
      return;
    }
    if (marker === 'C') {
      this.unconfirmedInputBytes = 0;
      const block = this.current('running');
      block.command = sanitizeTerminalText(block.command);
      block.output = '';
      changed.add(block.id);
      return;
    }
    if (marker === 'D') {
      this.unconfirmedInputBytes = 0;
      const block = this.current('finished');
      const exit = payload.slice(1).split(';').find((part) => /^-?\d+$/.test(part));
      block.state = 'finished';
      block.exitCode = exit === undefined ? null : Number(exit);
      block.command = sanitizeTerminalText(block.command);
      changed.add(block.id);
      this.currentId = null;
    }
  }

  private appendOutput(value: string): void {
    if (!value || this.currentId === null) return;
    const block = this.block(this.currentId);
    if (!block) return;
    if (block.state === 'input') {
      block.command = trimText(block.command + value);
      block.updatedAtSequence = this.sequence;
    } else if (block.state === 'running') {
      block.output = trimText(block.output + value);
      block.updatedAtSequence = this.sequence;
    }
  }
}

export class SemanticBlockPanel {
  readonly element: HTMLElement;
  private readonly onCopy?: (text: string) => void | Promise<void>;
  private readonly maximumVisible: number;
  private readonly resolveBlock?: (id: number) => SemanticCommandBlock | undefined;
  private markdownBlockId: number | null = null;
  private lastSnapshot: SemanticBlockSnapshot = {
    blocks: [],
    activeBlockId: null,
    lastSequence: 0,
    unconfirmedInputBytes: 0
  };

  constructor(options: SemanticBlockPanelOptions = {}) {
    this.onCopy = options.onCopy;
    this.maximumVisible = Math.max(1, options.maximumVisible ?? 8);
    this.resolveBlock = options.resolveBlock;
    this.element = document.createElement('section');
    this.element.className = 'semantic-blocks';
    this.element.setAttribute('aria-label', 'Semantic command blocks');
  }

  render(snapshot: SemanticBlockSnapshot): void {
    this.lastSnapshot = snapshot;
    this.element.replaceChildren();
    const visible = snapshot.blocks
      .filter((block) => block.state !== 'prompt')
      .slice(-this.maximumVisible);
    if (visible.length === 0) {
      this.element.hidden = true;
      return;
    }
    this.element.hidden = false;
    for (const block of visible) this.element.appendChild(this.renderBlock(block));
  }

  destroy(): void {
    this.element.remove();
  }

  private renderBlock(block: SemanticCommandBlock): HTMLElement {
    const article = document.createElement('article');
    article.className = `semantic-block semantic-aura-${exitAura(block)}`;
    article.dataset.blockId = String(block.id);

    const header = document.createElement('header');
    const command = document.createElement('code');
    command.textContent = sanitizeTerminalText(block.command) || block.state;
    const status = document.createElement('span');
    status.className = 'semantic-block-status';
    status.textContent = block.state === 'finished'
      ? `exit ${block.exitCode ?? 'unknown'}`
      : block.state;
    header.append(command, status);

    const actions = document.createElement('div');
    actions.className = 'semantic-block-actions';
    const copy = document.createElement('button');
    copy.type = 'button';
    copy.textContent = 'Copy output';
    copy.disabled = !isConfirmedBlock(block);
    copy.addEventListener('click', () => {
      const current = this.resolveBlock?.(block.id) ?? block;
      const text = copyBlockOutput(current);
      if (!text) return;
      if (this.onCopy) void this.onCopy(text);
      else void navigator.clipboard?.writeText(text);
    });

    const markdown = document.createElement('button');
    markdown.type = 'button';
    markdown.textContent = 'Markdown';
    markdown.disabled = !isConfirmedBlock(block);
    markdown.addEventListener('click', () => {
      this.markdownBlockId = this.markdownBlockId === block.id ? null : block.id;
      this.render(this.lastSnapshot);
    });
    actions.append(copy, markdown);

    article.append(header, actions);
    if (this.markdownBlockId === block.id) {
      const preview = document.createElement('pre');
      preview.className = 'semantic-block-markdown';
      preview.textContent = formatBlockMarkdown(this.resolveBlock?.(block.id) ?? block);
      article.appendChild(preview);
    }
    return article;
  }
}
