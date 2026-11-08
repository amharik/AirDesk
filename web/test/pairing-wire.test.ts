import { describe, expect, it } from 'vitest';
import {
  PairingWireError,
  decodePairingWireMessage,
  encodePairingWireMessage,
  pairingWireInitiatorFinish,
  pairingWireResponse,
  pairingWireResponderFinish,
  pairingWireShare,
  pairingWireVerifierResponse
} from '../src/identity';

function failureCode(action: () => unknown): string {
  try {
    action();
  } catch (error) {
    if (error instanceof PairingWireError) return error.code;
    throw error;
  }
  throw new Error('expected pairing wire failure');
}

describe('AD-PAIR-1 pairing wire codec', () => {
  it('decodes the native response and share fixtures', () => {
    expect(
      decodePairingWireMessage(
        '{"protocol":"adpair-wire","version":1,"kind":"response","response":"AAEC"}'
      )
    ).toEqual({
      protocol: 'adpair-wire',
      version: 1,
      kind: 'response',
      response: new Uint8Array([0, 1, 2])
    });
    expect(
      decodePairingWireMessage(
        '{"protocol":"adpair-wire","version":1,"kind":"share","share":"AwQF"}'
      )
    ).toMatchObject({ kind: 'share', share: new Uint8Array([3, 4, 5]) });
  });

  it('round-trips every message kind with standard base64 payloads', () => {
    const messages = [
      pairingWireResponse(new Uint8Array([0, 1, 2])),
      pairingWireShare(new Uint8Array([3, 4, 5])),
      pairingWireVerifierResponse(
        new Uint8Array([6]),
        new Uint8Array([7]),
        new Uint8Array([8])
      ),
      pairingWireInitiatorFinish(new Uint8Array([9]), new Uint8Array([10])),
      pairingWireResponderFinish(new Uint8Array([11]), new Uint8Array([12]))
    ];

    for (const message of messages) {
      const encoded = encodePairingWireMessage(message);
      expect(decodePairingWireMessage(encoded)).toEqual(message);
      expect(JSON.parse(new TextDecoder().decode(encoded))).toMatchObject({
        protocol: 'adpair-wire',
        version: 1,
        kind: message.kind
      });
    }
  });

  it('uses padded base64 compatible with Foundation Data encoding', () => {
    const encoded = encodePairingWireMessage(pairingWireShare(new Uint8Array([0, 1])));
    expect(JSON.parse(new TextDecoder().decode(encoded)).share).toBe('AAE=');
  });

  it('rejects malformed JSON, protocol and version mismatches', () => {
    expect(failureCode(() => decodePairingWireMessage('{'))).toBe('malformed');
    expect(failureCode(() => decodePairingWireMessage('[]'))).toBe('malformed');
    expect(
      failureCode(() =>
        decodePairingWireMessage(
          '{"protocol":"other","version":1,"kind":"response","response":"AAEC"}'
        )
      )
    ).toBe('unsupported-protocol');
    expect(
      failureCode(() =>
        decodePairingWireMessage(
          '{"protocol":"adpair-wire","version":2,"kind":"response","response":"AAEC"}'
        )
      )
    ).toBe('unsupported-version');
  });

  it('rejects payloads that do not match the message kind', () => {
    expect(
      failureCode(() =>
        decodePairingWireMessage(
          '{"protocol":"adpair-wire","version":1,"kind":"share","share":"AAEC","response":"AAEC"}'
        )
      )
    ).toBe('invalid-payload');
    expect(
      failureCode(() =>
        decodePairingWireMessage(
          '{"protocol":"adpair-wire","version":1,"kind":"verifier-response","share":"AAEC","confirmation":"AAEC"}'
        )
      )
    ).toBe('invalid-payload');
    expect(
      failureCode(() => decodePairingWireMessage('{"protocol":"adpair-wire","version":1,"kind":"unknown"}'))
    ).toBe('invalid-payload');
  });

  it('rejects empty, invalid and oversized payloads', () => {
    expect(
      failureCode(() =>
        decodePairingWireMessage(
          '{"protocol":"adpair-wire","version":1,"kind":"response","response":""}'
        )
      )
    ).toBe('invalid-payload');
    expect(
      failureCode(() =>
        decodePairingWireMessage(
          '{"protocol":"adpair-wire","version":1,"kind":"response","response":"***"}'
        )
      )
    ).toBe('invalid-payload');
    expect(failureCode(() => pairingWireResponse(new Uint8Array()))).toBe('invalid-payload');
    expect(failureCode(() => pairingWireResponse(new Uint8Array(1_048_577)))).toBe(
      'invalid-payload'
    );
  });
});
