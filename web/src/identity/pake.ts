export interface Spake2PlusExchangeInput {
  protocolVersion: string;
  secret: Uint8Array;
  initiatorDeviceId: string;
  responderDeviceId: string;
}

export interface Spake2PlusEvidence {
  initiatorShare: string;
  responderShare: string;
  initiatorConfirmation: string;
  responderConfirmation: string;
}

/**
 * The PAKE implementation supplies the raw shared secret as base64url. The
 * secret is deliberately kept out of the canonical transcript; only the public
 * shares and confirmation tags are transcript inputs.
 */
export interface Spake2PlusExchangeResult extends Spake2PlusEvidence {
  sharedSecret: string;
}

export interface Spake2PlusPrimitive {
  readonly suite: 'SPAKE2+-P256-SHA256';
  exchange(input: Spake2PlusExchangeInput): Promise<Spake2PlusExchangeResult>;
}
