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

export interface Spake2PlusPrimitive {
  readonly suite: 'SPAKE2+-P256-SHA256';
  exchange(input: Spake2PlusExchangeInput): Promise<Spake2PlusEvidence>;
}
