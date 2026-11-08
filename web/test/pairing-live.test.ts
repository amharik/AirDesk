import { describe, expect, it } from 'vitest';
import {
  AdPairLiveSession,
  DeviceRegistry,
  MemoryKeyStore,
  bytesToBase64Url,
  createBrowserIdentity,
  exporterChannelBinding,
  type BrowserDeviceIdentity
} from '../src/identity';
import { decryptSyncEnvelope, encryptSyncEnvelope } from '../src/sync/envelope';

async function identity(): Promise<BrowserDeviceIdentity> {
  return createBrowserIdentity({ store: new MemoryKeyStore() });
}

describe('browser live pairing session', () => {
  it('drives the native pairing-wire exchange to a matching SAS', async () => {
    const hostIdentity = await identity();
    const controllerIdentity = await identity();
    const hostRegistry = new DeviceRegistry();
    const controllerRegistry = new DeviceRegistry();
    const host = new AdPairLiveSession('initiator', hostIdentity, {
      registry: hostRegistry
    });
    const controller = new AdPairLiveSession('responder', controllerIdentity, {
      registry: controllerRegistry
    });
    const start = host.startInitiator(
      'pin',
      exporterChannelBinding(new Uint8Array(32).fill(7))
    );

    const response = await controller.joinResponder(start.code, start.pin);
    expect(host.state).toBe('waiting-for-response');
    expect(controller.state).toBe('awaiting-share');

    const [share] = await host.receive(response);
    const [verifier] = await controller.receive(share!);
    const [initiatorFinish] = await host.receive(verifier!);
    const [responderFinish] = await controller.receive(initiatorFinish!);

    expect(host.state).toBe('awaiting-sas');
    expect(controller.state).toBe('awaiting-sas');
    expect(await host.receive(responderFinish!)).toEqual([]);
    expect(hostRegistry.isTrusted(controllerIdentity.deviceId)).toBe(false);
    expect(controllerRegistry.isTrusted(hostIdentity.deviceId)).toBe(false);

    const hostResult = host.confirmShortAuthenticationString(host.shortAuthenticationString!);
    const controllerResult = controller.confirmShortAuthenticationString(
      controller.shortAuthenticationString!
    );

    expect(hostRegistry.isTrusted(controllerIdentity.deviceId)).toBe(true);
    expect(controllerRegistry.isTrusted(hostIdentity.deviceId)).toBe(true);
    expect(hostResult.shortAuthenticationString).toBe(
      controllerResult.shortAuthenticationString
    );
    expect(bytesToBase64Url(hostResult.sessionKeys.transport.bytes)).toBe(
      bytesToBase64Url(controllerResult.sessionKeys.transport.bytes)
    );

    const hostSyncKey = await host.workspaceSyncKey();
    const controllerSyncKey = await controller.workspaceSyncKey();
    const envelope = await encryptSyncEnvelope({
      key: hostSyncKey,
      workspaceId: 'paired-workspace',
      senderDeviceId: hostIdentity.deviceId,
      hostEpoch: 1,
      syncSeq: 1,
      plaintext: 'automatic pairing key'
    });
    await expect(
      decryptSyncEnvelope({
        key: controllerSyncKey,
        envelope,
        expected: { workspaceId: 'paired-workspace', hostEpoch: 1 }
      })
    ).resolves.toBeTruthy();

    expect(host.state).toBe('completed');
    expect(controller.state).toBe('completed');
  });

  it('rejects the SAS before returning session keys', async () => {
    const host = new AdPairLiveSession('initiator', await identity());
    const controller = new AdPairLiveSession('responder', await identity());
    const start = host.startInitiator(
      'qr-secret',
      exporterChannelBinding(new Uint8Array(32).fill(8))
    );
    const response = await controller.joinResponder(start.code);
    const [share] = await host.receive(response);
    const [verifier] = await controller.receive(share!);
    const [initiatorFinish] = await host.receive(verifier!);
    await controller.receive(initiatorFinish!);

    const wrong = host.shortAuthenticationString === '000000' ? '000001' : '000000';
    expect(() => host.confirmShortAuthenticationString(wrong)).toThrowError(
      expect.objectContaining({ code: 'sas-mismatch' })
    );
    expect(host.state).toBe('failed');
    expect(host.result?.sessionKeys.transport.bytes.length).toBe(32);
  });

  it('rejects out-of-order wire messages and wrong roles', async () => {
    const host = new AdPairLiveSession('initiator', await identity());
    await expect(host.receive(new Uint8Array())).rejects.toMatchObject({ code: 'malformed' });
    expect(host.state).toBe('failed');

    await expect(host.workspaceSyncKey()).rejects.toMatchObject({ code: 'invalid-state' });

    const responder = new AdPairLiveSession('responder', await identity());
    expect(() =>
      responder.startInitiator(
        'pin',
        exporterChannelBinding(new Uint8Array(32).fill(9))
      )
    ).toThrowError(expect.objectContaining({ code: 'invalid-state' }));
  });
});
