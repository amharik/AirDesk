import { describe, expect, it } from 'vitest';
import {
  SEMANTIC_BLOCK_LIMIT,
  SemanticTerminalModel,
  copyBlockOutput,
  exitAura,
  formatBlockMarkdown,
  isConfirmedBlock,
  sanitizeTerminalText
} from '../src/terminal/semantic-blocks';

function runCommand(model: SemanticTerminalModel, command: string, output: string, exitCode: number): void {
  model.consume('\x1b]133;A\x07');
  model.consume('\x1b]133;B\x07');
  model.consume(`${command}\r`);
  model.consume('\x1b]133;C\x1b\\');
  model.consume(output);
  model.consume(`\x1b]133;D;${exitCode}\x07`);
}

describe('semantic terminal command blocks', () => {
  it('tracks phases, exit aura, copy output and markdown', () => {
    const model = new SemanticTerminalModel();
    model.consume('\x1b]133;A\x07');
    expect(model.snapshot().blocks[0]?.state).toBe('prompt');

    model.consume('\x1b]133;B\x07');
    model.consume('ls\r');
    expect(model.snapshot().activeBlockId).toBe(1);

    model.consume('\x1b]133;C\x07');
    model.consume('file.txt\r\n');
    const running = model.snapshot().blocks[0];
    expect(running?.state).toBe('running');
    expect(running && exitAura(running)).toBe('running');
    expect(running && isConfirmedBlock(running)).toBe(true);

    model.consume('\x1b]133;D;0\x07');
    const done = model.snapshot().blocks[0];
    expect(done?.state).toBe('finished');
    expect(done?.exitCode).toBe(0);
    expect(done?.command).toBe('ls');
    expect(done && exitAura(done)).toBe('success');
    expect(model.copyOutput(1)).toBe('file.txt');
    expect(model.markdown(1)).toContain('### ls');
    expect(model.markdown(1)).toContain('Status: exit 0');
    expect(model.markdown(1)).toContain('file.txt');
  });

  it('parses split controls and both BEL and ST terminators', () => {
    const model = new SemanticTerminalModel();
    model.consume('\x1b]1');
    expect(model.snapshot().blocks).toHaveLength(0);
    model.consume('33;A\x07');
    model.consume('\x1b]133');
    model.consume(';B\x1b\\');
    model.consume('echo ok\r');
    model.consume('\x1b]133;C\x07');
    model.consume('ok\r\n');
    model.consume('\x1b]133;D;7\x1b\\');

    const block = model.snapshot().blocks[0];
    expect(block?.command).toBe('echo ok');
    expect(block && copyBlockOutput(block)).toBe('ok');
    expect(block?.exitCode).toBe(7);
    expect(block && exitAura(block)).toBe('failure');
  });

  it('does not turn unconfirmed local input into a command or retry', () => {
    const model = new SemanticTerminalModel();
    model.noteInput('curl -H "Authorization: secret" https://example.test\r');
    const snapshot = model.snapshot();
    expect(snapshot.blocks).toHaveLength(0);
    expect(snapshot.unconfirmedInputBytes).toBeGreaterThan(0);
    expect(JSON.stringify(snapshot)).not.toContain('secret');
    expect(model.allowsAutomaticRetry).toBe(false);
    expect('retry' in model).toBe(false);
  });

  it('interrupts an unconfirmed or running block and bounds history', () => {
    const model = new SemanticTerminalModel();
    model.consume('\x1b]133;A\x07');
    model.consume('\x1b]133;B\x07');
    model.consume('sleep 60');
    model.noteInput('\x03');
    expect(model.snapshot().blocks[0]?.state).toBe('interrupted');
    expect(model.snapshot().activeBlockId).toBeNull();

    for (let index = 0; index < SEMANTIC_BLOCK_LIMIT + 5; index += 1) {
      runCommand(model, `echo ${index}`, `${index}\r\n`, 0);
    }
    const blocks = model.snapshot().blocks;
    expect(blocks).toHaveLength(SEMANTIC_BLOCK_LIMIT);
    expect(blocks[blocks.length - 1]?.command).toBe(`echo ${SEMANTIC_BLOCK_LIMIT + 4}`);
  });

  it('strips terminal controls and never exposes output for unconfirmed blocks', () => {
    const output = sanitizeTerminalText('\x1b[32mgreen\x1b[0m\r\nline\x07');
    expect(output).toBe('green\nline');

    const model = new SemanticTerminalModel();
    model.consume('\x1b]133;A\x07');
    model.consume('\x1b]133;B\x07');
    model.consume('secret-command');
    const pending = model.snapshot().blocks[0];
    expect(pending && copyBlockOutput(pending)).toBe('');
    expect(pending && formatBlockMarkdown(pending)).toBe('');
  });
});
