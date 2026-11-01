import { describe, expect, it } from 'vitest';
import {
  TERMINAL_TRANSCRIPT_KEY,
  TERMINAL_TRANSCRIPT_LIMIT,
  TERMINAL_TRANSCRIPT_MARKER,
  formatTranscriptReplay,
  readTranscript,
  saveTranscript,
  trimTranscript
} from '../src/terminal/terminal-transcript';
import type { TranscriptStore } from '../src/terminal/terminal-transcript';

class MemoryStore implements TranscriptStore {
  private readonly values = new Map<string, string>();

  async read(key: string): Promise<string | null> {
    return this.values.get(key) ?? null;
  }

  async write(key: string, value: string): Promise<void> {
    this.values.set(key, value);
  }

  async remove(key: string): Promise<void> {
    this.values.delete(key);
  }

  peek(key: string): string | undefined {
    return this.values.get(key);
  }
}

describe('terminal transcript replay', () => {
  it('bounds retained text and keeps surrogate pairs intact', () => {
    const text = `a${'b'.repeat(8)}😀`;
    const trimmed = trimTranscript(text, 2);
    expect(trimmed).toBe('😀');
    expect(trimmed.length).toBeLessThanOrEqual(2);
    expect(trimTranscript('short', 10)).toBe('short');
    expect(trimTranscript('short', 0)).toBe('');
  });

  it('stores, reads, caps, and clears a session transcript', async () => {
    const store = new MemoryStore();
    const saved = await saveTranscript(store, `line\n${'x'.repeat(20)}`, 'ads-one', 10);
    expect(saved).toBe('x'.repeat(10));
    expect(store.peek(TERMINAL_TRANSCRIPT_KEY)).toContain('"sessionId":"ads-one"');
    await expect(readTranscript(store, 'ads-one', 10)).resolves.toBe(saved);
    await expect(readTranscript(store, 'ads-two', 10)).resolves.toBe('');

    await expect(saveTranscript(store, '  \n\t ', 'ads-one', 10)).resolves.toBe('');
    expect(store.peek(TERMINAL_TRANSCRIPT_KEY)).toBeUndefined();
    await expect(readTranscript(store, 'ads-one')).resolves.toBe('');
  });

  it('ignores malformed or older transcript records', async () => {
    const store = new MemoryStore();
    await store.write(TERMINAL_TRANSCRIPT_KEY, 'not-json');
    await expect(readTranscript(store, 'ads-one')).resolves.toBe('');
    await store.write(TERMINAL_TRANSCRIPT_KEY, JSON.stringify({ sessionId: 'ads-one', text: 7 }));
    await expect(readTranscript(store, 'ads-one')).resolves.toBe('');
    await store.write(TERMINAL_TRANSCRIPT_KEY, 'plain legacy text');
    await expect(readTranscript(store, 'ads-one')).resolves.toBe('');
  });

  it('survives unavailable or quota-limited storage', async () => {
    const unavailable: TranscriptStore = {
      async read() { throw new Error('blocked'); },
      async write() { throw new Error('quota'); },
      async remove() { throw new Error('blocked'); }
    };
    await expect(readTranscript(unavailable, 'ads-one')).resolves.toBe('');
    await expect(saveTranscript(unavailable, 'output', 'ads-one')).resolves.toBe('');
  });

  it('formats a printable replay without terminal control state', () => {
    const replay = formatTranscriptReplay('one\r\ntwo\nthree', 100);
    expect(replay).toContain(`\x1b[2m${TERMINAL_TRANSCRIPT_MARKER}\x1b[0m`);
    expect(replay).toContain('one\r\ntwo\r\nthree');
    expect(replay.endsWith('\r\n')).toBe(true);
    expect(formatTranscriptReplay(' \n ')).toBe('');
  });

  it('keeps the default transcript limit bounded for local storage', () => {
    expect(TERMINAL_TRANSCRIPT_LIMIT).toBe(200_000);
  });
});
