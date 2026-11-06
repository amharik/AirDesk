import { PairingValidationError } from './pairing-payload';

export interface NonceReplayGuardOptions {
  now?: () => number;
}

export class NonceReplayGuard {
  private readonly seen = new Map<string, number>();
  private readonly now: () => number;

  constructor(options: NonceReplayGuardOptions = {}) {
    this.now = options.now ?? Date.now;
  }

  has(nonce: string): boolean {
    this.prune();
    return this.seen.has(nonce);
  }

  consume(nonce: string, expiresAt: number): void {
    this.prune();
    if (this.seen.has(nonce)) {
      throw new PairingValidationError('replayed-nonce', 'pairing nonce was already used');
    }
    this.seen.set(nonce, expiresAt);
  }

  prune(): void {
    const now = this.now();
    for (const [nonce, expiresAt] of this.seen) {
      if (expiresAt <= now) this.seen.delete(nonce);
    }
  }

  clear(): void {
    this.seen.clear();
  }
}
