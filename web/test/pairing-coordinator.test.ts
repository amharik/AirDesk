import { describe, expect, it } from 'vitest';
import {
  AdPairCoordinator,
  DeviceRegistry,
  MemoryKeyStore,
  bytesToBase64Url,
  createBrowserIdentity,
  exporterChannelBinding,
  type BrowserDeviceIdentity
} from '../src/identity';

async function identity(): Promise<BrowserDeviceIdentity> {
  return createBrowserIdentity({ store: new MemoryKeyStore() });
}

function binding(fill: number) {
  return exporterChannelBinding(new Uint8Array(32).fill(fill));
}

describe('browser pairing coordinator', () => {
  it('completes a PIN pairing and derives matching session keys', async () => {
    const hostIdentity = await identity();
    const controllerIdentity = await identity();
    const host = new AdPairCoordinator('initiator', hostIdentity);

    const start = host.startInitiator('pin', binding(1), 60_000, 'host-ticket', ['display']);
    expect(start.challenge.pin).toMatch(/^\d{6}$/);

    const controller = new AdPairCoordinator('responder', controllerIdentity);
    const join = await controller.joinResponder(
      start.challenge.serialized,
      start.challenge.pin,
      60_000,
      'controller-ticket',
      ['control']
    );

    const shareP = await host.acceptResponse(join.responseData);
    const reply = await controller.respond(shareP);
    const initiator = await host.finishInitiator(
      reply.share,
      reply.confirmation,
      reply.signature
    );
    const responder = await controller.finishResponder(
      initiator.confirmation,
      initiator.signature
    );

    expect(host.state).toBe('completed');
    expect(controller.state).toBe('completed');
    expect(initiator.result.shortAuthenticationString).toMatch(/^\d{6}$/);
    expect(initiator.result.shortAuthenticationString).toBe(
      responder.result.shortAuthenticationString
    );
    expect(Array.from(initiator.result.sessionKeys.transport.bytes)).toEqual(
      Array.from(responder.result.sessionKeys.transport.bytes)
    );
    expect(initiator.result.requestedCapabilities).toEqual(['control', 'display']);
  });

  it('completes a QR-secret pairing without a PIN', async () => {
    const host = new AdPairCoordinator('initiator', await identity());
    const controller = new AdPairCoordinator('responder', await identity());
    const start = host.startInitiator('qr-secret', binding(2));

    const join = await controller.joinResponder(start.challenge.serialized);
    const reply = await controller.respond(await host.acceptResponse(join.responseData));
    const initiator = await host.finishInitiator(
      reply.share,
      reply.confirmation,
      reply.signature
    );
    const responder = await controller.finishResponder(
      initiator.confirmation,
      initiator.signature
    );

    expect(initiator.result.shortAuthenticationString).toBe(
      responder.result.shortAuthenticationString
    );
  });

  it('rejects a wrong PIN during the PAKE exchange', async () => {
    const host = new AdPairCoordinator('initiator', await identity());
    const controller = new AdPairCoordinator('responder', await identity());
    const start = host.startInitiator('pin', binding(3));
    const wrongPin = start.challenge.pin === '000000' ? '000001' : '000000';

    const join = await controller.joinResponder(start.challenge.serialized, wrongPin);
    const reply = await controller.respond(await host.acceptResponse(join.responseData));

    await expect(
      host.finishInitiator(reply.share, reply.confirmation, reply.signature)
    ).rejects.toBeDefined();
  });

  it('rejects a revoked initiator before joining', async () => {
    const hostIdentity = await identity();
    const controllerIdentity = await identity();
    const registry = new DeviceRegistry();
    registry.pair({
      deviceId: hostIdentity.deviceId,
      publicKey: bytesToBase64Url(hostIdentity.publicKeySpki)
    });
    registry.revoke(hostIdentity.deviceId);
    const host = new AdPairCoordinator('initiator', hostIdentity);
    const controller = new AdPairCoordinator('responder', controllerIdentity, { registry });
    const start = host.startInitiator('pin', binding(4));

    await expect(
      controller.joinResponder(start.challenge.serialized, start.challenge.pin)
    ).rejects.toMatchObject({ code: 'revoked-device' });
  });

  it('requires the expected role and message order', async () => {
    const host = new AdPairCoordinator('initiator', await identity());
    await expect(host.respond(new Uint8Array())).rejects.toMatchObject({
      code: 'invalid-state'
    });
    await expect(host.acceptResponse('{}')).rejects.toMatchObject({ code: 'invalid-state' });

    const controller = new AdPairCoordinator('responder', await identity());
    expect(() => controller.startInitiator('pin', binding(5))).toThrowError(
      expect.objectContaining({ code: 'invalid-state' })
    );
  });
});
