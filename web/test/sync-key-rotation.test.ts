import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { hexToBytes } from '../src/identity/encoding';
import {
  acceptWorkspaceSyncKeyGrant,
  acceptWorkspaceSyncKeyRotation,
  decryptSyncEnvelope,
  decodeWorkspaceKeyGrant,
  decodeWorkspaceKeyRotation,
  encryptSyncEnvelope,
  grantWorkspaceSyncKey,
  importWorkspaceSyncKey,
  rotateWorkspaceSyncKey,
  WorkspaceKeyRotationError,
  type WorkspaceKeyRotation
} from '../src/sync';

const fixture = JSON.parse(
  readFileSync(
    join(process.cwd(), '..', 'protocol', 'fixtures', 'sync', 'key-rotation-v1.json'),
    'utf8'
  )
) as {
  version: number;
  kind: 'workspace-key-rotation';
  workspaceId: string;
  issuerDeviceId: string;
  generation: number;
  currentKeyHex: string;
  newKeyHex: string;
  nonceBase64: string;
  ciphertextBase64: string;
};

const grantFixture = JSON.parse(
  readFileSync(
    join(process.cwd(), '..', 'protocol', 'fixtures', 'sync', 'key-grant-v1.json'),
    'utf8'
  )
) as {
  version: number;
  kind: 'workspace-key-grant';
  workspaceId: string;
  issuerDeviceId: string;
  generation: number;
  bootstrapKeyHex: string;
  workspaceKeyHex: string;
  nonceBase64: string;
  ciphertextBase64: string;
};

function base64Bytes(value: string): Uint8Array {
  return Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
}

describe('workspace sync key rotation', () => {
  it('matches the cross-platform rotation fixture', async () => {
    const currentKey = await importWorkspaceSyncKey(hexToBytes(fixture.currentKeyHex));
    const rotated = await rotateWorkspaceSyncKey({
      currentKey,
      workspaceId: fixture.workspaceId,
      issuerDeviceId: fixture.issuerDeviceId,
      nextGeneration: fixture.generation,
      newKey: hexToBytes(fixture.newKeyHex),
      nonce: Uint8Array.from(
        atob(fixture.nonceBase64),
        (character) => character.charCodeAt(0)
      )
    });

    expect(rotated.message).toMatchObject({
      version: fixture.version,
      kind: fixture.kind,
      workspaceId: fixture.workspaceId,
      issuerDeviceId: fixture.issuerDeviceId,
      generation: fixture.generation,
      nonce: fixture.nonceBase64,
      ciphertext: fixture.ciphertextBase64
    });

    const accepted = await acceptWorkspaceSyncKeyRotation({
      currentKey,
      message: rotated.message,
      workspaceId: fixture.workspaceId,
      currentGeneration: 1,
      expectedIssuerDeviceId: fixture.issuerDeviceId
    });
    expect(Buffer.from(accepted.rawKey).toString('hex')).toBe(fixture.newKeyHex);
    expect(accepted.generation).toBe(fixture.generation);
  });

  it('matches the cross-platform paired key grant fixture', async () => {
    const bootstrapKey = await importWorkspaceSyncKey(hexToBytes(grantFixture.bootstrapKeyHex));
    const message = await grantWorkspaceSyncKey({
      rawKey: hexToBytes(grantFixture.workspaceKeyHex),
      bootstrapKey,
      workspaceId: grantFixture.workspaceId,
      issuerDeviceId: grantFixture.issuerDeviceId,
      generation: grantFixture.generation,
      nonce: base64Bytes(grantFixture.nonceBase64)
    });

    expect(message).toMatchObject({
      version: grantFixture.version,
      kind: grantFixture.kind,
      workspaceId: grantFixture.workspaceId,
      issuerDeviceId: grantFixture.issuerDeviceId,
      generation: grantFixture.generation,
      nonce: grantFixture.nonceBase64,
      ciphertext: grantFixture.ciphertextBase64
    });
    expect(decodeWorkspaceKeyGrant(JSON.stringify(message))).toEqual(message);

    const accepted = await acceptWorkspaceSyncKeyGrant({
      bootstrapKey,
      message,
      workspaceId: grantFixture.workspaceId,
      expectedIssuerDeviceId: grantFixture.issuerDeviceId
    });
    expect(Buffer.from(accepted.rawKey).toString('hex')).toBe(grantFixture.workspaceKeyHex);
    expect(accepted.generation).toBe(grantFixture.generation);

    await expect(
      acceptWorkspaceSyncKeyGrant({
        bootstrapKey,
        message,
        workspaceId: grantFixture.workspaceId,
        expectedIssuerDeviceId: 'device:other'
      })
    ).rejects.toMatchObject({ code: 'InvalidIssuer' });
  });

  it('makes revoked peers unable to use the rotated key', async () => {
    const oldKey = await importWorkspaceSyncKey(hexToBytes(fixture.currentKeyHex));
    const rotated = await rotateWorkspaceSyncKey({
      currentKey: oldKey,
      workspaceId: fixture.workspaceId,
      issuerDeviceId: fixture.issuerDeviceId,
      nextGeneration: fixture.generation,
      newKey: hexToBytes(fixture.newKeyHex),
      nonce: Uint8Array.from(
        atob(fixture.nonceBase64),
        (character) => character.charCodeAt(0)
      )
    });
    const envelope = await encryptSyncEnvelope({
      key: rotated.key,
      workspaceId: fixture.workspaceId,
      senderDeviceId: 'host',
      hostEpoch: 1,
      syncSeq: 1,
      plaintext: 'after rotation'
    });

    await expect(
      decryptSyncEnvelope({
        key: oldKey,
        envelope,
        expected: { workspaceId: fixture.workspaceId, hostEpoch: 1 }
      })
    ).rejects.toMatchObject({ code: 'AuthenticationFailed' });
    await expect(
      decryptSyncEnvelope({
        key: rotated.key,
        envelope,
        expected: { workspaceId: fixture.workspaceId, hostEpoch: 1 }
      })
    ).resolves.toBeTruthy();
  });

  it('rejects replayed, skipped, wrong-issuer and tampered rotations', async () => {
    const currentKey = await importWorkspaceSyncKey(hexToBytes(fixture.currentKeyHex));
    const rotated = await rotateWorkspaceSyncKey({
      currentKey,
      workspaceId: fixture.workspaceId,
      issuerDeviceId: fixture.issuerDeviceId,
      nextGeneration: fixture.generation,
      newKey: hexToBytes(fixture.newKeyHex),
      nonce: Uint8Array.from(
        atob(fixture.nonceBase64),
        (character) => character.charCodeAt(0)
      )
    });
    const base = {
      currentKey,
      message: rotated.message,
      workspaceId: fixture.workspaceId
    };

    await expect(
      acceptWorkspaceSyncKeyRotation({ ...base, currentGeneration: 2 })
    ).rejects.toMatchObject({ code: 'GenerationReplay' });
    await expect(
      acceptWorkspaceSyncKeyRotation({ ...base, currentGeneration: 0 })
    ).rejects.toMatchObject({ code: 'GenerationGap' });
    await expect(
      acceptWorkspaceSyncKeyRotation({
        ...base,
        currentGeneration: 1,
        expectedIssuerDeviceId: 'ad-device:other'
      })
    ).rejects.toMatchObject({ code: 'InvalidIssuer' });
    await expect(
      acceptWorkspaceSyncKeyRotation({
        ...base,
        currentGeneration: 1,
        message: { ...rotated.message, workspaceId: 'ws-2' }
      })
    ).rejects.toMatchObject({ code: 'WorkspaceMismatch' });
    await expect(
      acceptWorkspaceSyncKeyRotation({
        ...base,
        currentGeneration: 1,
        message: {
          ...rotated.message,
          ciphertext: rotated.message.ciphertext.replace(/.$/, (last) =>
            last === 'A' ? 'B' : 'A'
          )
        }
      })
    ).rejects.toBeInstanceOf(WorkspaceKeyRotationError);
  });

  it('validates rotation envelopes and exposes a typed decoder', async () => {
    const currentKey = await importWorkspaceSyncKey(hexToBytes(fixture.currentKeyHex));
    const rotated = await rotateWorkspaceSyncKey({
      currentKey,
      workspaceId: fixture.workspaceId,
      issuerDeviceId: fixture.issuerDeviceId,
      nextGeneration: fixture.generation,
      newKey: hexToBytes(fixture.newKeyHex)
    });
    const decoded = decodeWorkspaceKeyRotation(JSON.stringify(rotated.message));
    expect(decoded.generation).toBe(fixture.generation);
    expect(() => decodeWorkspaceKeyRotation('{')).toThrowError(WorkspaceKeyRotationError);
    const malformed: WorkspaceKeyRotation = { ...rotated.message, version: 2 };
    expect(() => decodeWorkspaceKeyRotation(JSON.stringify(malformed))).toThrowError(
      expect.objectContaining({ code: 'UnsupportedVersion' })
    );
  });
});
