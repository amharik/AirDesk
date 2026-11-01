export const TERMINAL_TRANSCRIPT_KEY = 'airdesk.terminal.transcript.v1';
export const TERMINAL_TRANSCRIPT_LIMIT = 200_000;
export const TERMINAL_TRANSCRIPT_MARKER = 'Restored terminal history';
export const TERMINAL_TRANSCRIPT_DATABASE = 'airdesk.terminal.v1';
export const TERMINAL_TRANSCRIPT_STORE = 'transcripts';

export interface TranscriptStore {
  read(key: string): Promise<string | null>;
  write(key: string, value: string): Promise<void>;
  remove(key: string): Promise<void>;
}

interface TranscriptRecord {
  sessionId: string;
  savedAt: number;
  text: string;
}

export function trimTranscript(text: string, limit = TERMINAL_TRANSCRIPT_LIMIT): string {
  if (limit <= 0) return '';
  if (text.length <= limit) return text;
  let start = text.length - limit;
  const code = text.charCodeAt(start);
  if (code >= 0xdc00 && code <= 0xdfff) start += 1;
  return text.slice(start);
}

function memoryFallback(): TranscriptStore {
  const values = new Map<string, string>();
  return {
    async read(key) { return values.get(key) ?? null; },
    async write(key, value) { values.set(key, value); },
    async remove(key) { values.delete(key); }
  };
}

export function createIndexedDBTranscriptStore(
  factory: IDBFactory | undefined = globalThis.indexedDB,
  databaseName = TERMINAL_TRANSCRIPT_DATABASE
): TranscriptStore {
  if (!factory) return memoryFallback();
  let database: Promise<IDBDatabase> | null = null;

  const open = (): Promise<IDBDatabase> => {
    if (database) return database;
    const pending = new Promise<IDBDatabase>((resolve, reject) => {
      const request = factory.open(databaseName, 1);
      request.onupgradeneeded = () => {
        const db = request.result;
        if (!db.objectStoreNames.contains(TERMINAL_TRANSCRIPT_STORE)) {
          db.createObjectStore(TERMINAL_TRANSCRIPT_STORE);
        }
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error ?? new Error('Transcript database could not be opened.'));
      request.onblocked = () => reject(new Error('Transcript database is blocked.'));
    }).catch((error: unknown): never => {
      database = null;
      throw error;
    });
    database = pending;
    return pending;
  };

  return {
    async read(key) {
      const db = await open();
      return new Promise((resolve, reject) => {
        const transaction = db.transaction(TERMINAL_TRANSCRIPT_STORE, 'readonly');
        const request = transaction.objectStore(TERMINAL_TRANSCRIPT_STORE).get(key);
        request.onsuccess = () => resolve(typeof request.result === 'string' ? request.result : null);
        request.onerror = () => reject(request.error ?? new Error('Transcript read failed.'));
        transaction.onerror = () => reject(transaction.error ?? new Error('Transcript read failed.'));
      });
    },
    async write(key, value) {
      const db = await open();
      return new Promise((resolve, reject) => {
        const transaction = db.transaction(TERMINAL_TRANSCRIPT_STORE, 'readwrite');
        transaction.objectStore(TERMINAL_TRANSCRIPT_STORE).put(value, key);
        transaction.oncomplete = () => resolve();
        transaction.onerror = () => reject(transaction.error ?? new Error('Transcript write failed.'));
        transaction.onabort = () => reject(transaction.error ?? new Error('Transcript write aborted.'));
      });
    },
    async remove(key) {
      const db = await open();
      return new Promise((resolve, reject) => {
        const transaction = db.transaction(TERMINAL_TRANSCRIPT_STORE, 'readwrite');
        transaction.objectStore(TERMINAL_TRANSCRIPT_STORE).delete(key);
        transaction.oncomplete = () => resolve();
        transaction.onerror = () => reject(transaction.error ?? new Error('Transcript delete failed.'));
        transaction.onabort = () => reject(transaction.error ?? new Error('Transcript delete aborted.'));
      });
    }
  };
}

export async function readTranscript(
  store: TranscriptStore,
  sessionId: string,
  limit = TERMINAL_TRANSCRIPT_LIMIT
): Promise<string> {
  try {
    const raw = await store.read(TERMINAL_TRANSCRIPT_KEY);
    if (!raw) return '';
    const record = JSON.parse(raw) as Partial<TranscriptRecord>;
    if (record.sessionId !== sessionId || typeof record.text !== 'string') return '';
    return trimTranscript(record.text, limit);
  } catch {
    return '';
  }
}

export async function saveTranscript(
  store: TranscriptStore,
  text: string,
  sessionId: string,
  limit = TERMINAL_TRANSCRIPT_LIMIT
): Promise<string> {
  const trimmed = trimTranscript(text, limit);
  try {
    if (trimmed.trim()) {
      const record: TranscriptRecord = { sessionId, savedAt: Date.now(), text: trimmed };
      await store.write(TERMINAL_TRANSCRIPT_KEY, JSON.stringify(record));
    } else {
      await store.remove(TERMINAL_TRANSCRIPT_KEY);
      return '';
    }
  } catch {
    return '';
  }
  return trimmed;
}

export function formatTranscriptReplay(
  text: string,
  limit = TERMINAL_TRANSCRIPT_LIMIT
): string {
  const trimmed = trimTranscript(text, limit).replace(/\s+$/, '');
  if (!trimmed) return '';
  const normalized = trimmed
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .replace(/\n/g, '\r\n');
  return `\r\n\x1b[2m${TERMINAL_TRANSCRIPT_MARKER}\x1b[0m\r\n${normalized}\r\n`;
}
