import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { DeviceAgent, DeviceAgentContractError } from '../src/capability';
import type {
  DeviceAgentCapability,
  DeviceAgentCapabilityRequest,
  DeviceAgentErrorCode,
  DeviceAgentEvent,
  DeviceAgentHealth,
  DeviceAgentIdentity,
  DeviceAgentPlatformPermissionState
} from '../src/capability';

interface LeaseExpectation {
  ok: true;
  leaseId: string;
  auditId: string;
  capUri: string;
  operations: string[];
  workspaceId: string;
  applicationId: string;
  requesterDeviceId: string;
  sessionId: string;
  issuedAtEpochMillis: number;
  expiresAtEpochMillis: number;
}

interface ErrorExpectation {
  ok: false;
  code: DeviceAgentErrorCode;
  permission?: string;
  operation?: string;
}

interface Fixture {
  nowEpochMillis: number;
  leaseDurationMillis: number;
  identity: DeviceAgentIdentity;
  platformPermissions: Record<string, DeviceAgentPlatformPermissionState>;
  capabilities: DeviceAgentCapability[];
  requestCases: Array<{
    name: string;
    request: DeviceAgentCapabilityRequest;
    expected: LeaseExpectation | ErrorExpectation;
  }>;
  releaseCases: Array<{
    name: string;
    leaseId: string;
    expected: { ok: true } | ErrorExpectation;
  }>;
  subscriptions: {
    eventTypes: string[];
    invalidEventType: string;
  };
  health: DeviceAgentHealth;
}

const fixture = JSON.parse(
  readFileSync(
    join(
      process.cwd(),
      '..',
      'protocol',
      'fixtures',
      'device-agent',
      'contract-v1.json'
    ),
    'utf8'
  )
) as Fixture;

function makeAgent(): DeviceAgent {
  return new DeviceAgent(
    fixture.identity,
    fixture.capabilities,
    fixture.platformPermissions,
    {
      leaseDurationMillis: fixture.leaseDurationMillis,
      now: () => fixture.nowEpochMillis
    }
  );
}

function requestCase(name: string): DeviceAgentCapabilityRequest {
  const item = fixture.requestCases.find((candidate) => candidate.name === name);
  if (item === undefined) throw new Error(`missing request case ${name}`);
  return item.request;
}

describe('device agent contract fixture', () => {
  it('projects identity, capabilities and health without conflating axes', () => {
    const agent = makeAgent();
    expect(agent.state).toBe('starting');
    expect(agent.identity()).toEqual(fixture.identity);

    const capabilities = agent.capabilities();
    expect(capabilities).toHaveLength(fixture.capabilities.length);
    expect(capabilities.map((capability) => capability.capUri)).toEqual(
      capabilities.map((capability) => capability.capUri).sort()
    );

    const documents = capabilities.find(
      (capability) => capability.capUri === 'airdesk://fs/documents/read'
    );
    expect(documents).toMatchObject({
      availability: 'available',
      authorization: 'ungranted'
    });

    const display = capabilities.find(
      (capability) => capability.capUri === 'airdesk://display/output'
    );
    expect(display).toMatchObject({
      availability: 'unavailable',
      authorization: 'granted'
    });

    expect(agent.health()).toMatchObject({
      state: 'starting',
      generation: 0,
      capabilityCount: fixture.capabilities.length
    });

    agent.start();
    expect(agent.health()).toEqual(fixture.health);
  });

  it('grants and rejects fixture request cases with typed errors', () => {
    for (const item of fixture.requestCases) {
      const agent = makeAgent();
      agent.start();
      if (item.expected.ok) {
        const lease = agent.requestCapability(item.request);
        expect(lease).toMatchObject({
          leaseId: item.expected.leaseId,
          auditId: item.expected.auditId,
          capUri: item.expected.capUri,
          operations: item.expected.operations,
          workspaceId: item.expected.workspaceId,
          applicationId: item.expected.applicationId,
          requesterDeviceId: item.expected.requesterDeviceId,
          sessionId: item.expected.sessionId,
          issuedAtEpochMillis: item.expected.issuedAtEpochMillis,
          expiresAtEpochMillis: item.expected.expiresAtEpochMillis
        });
        expect(agent.activeLeases()).toEqual([lease]);
      } else {
        let failure: unknown;
        try {
          agent.requestCapability(item.request);
        } catch (error) {
          failure = error;
        }
        expect(failure, item.name).toBeInstanceOf(DeviceAgentContractError);
        const typed = failure as DeviceAgentContractError;
        expect(typed.code, item.name).toBe(item.expected.code);
        if (item.expected.permission !== undefined) {
          expect(typed.detail, item.name).toBe(item.expected.permission);
        }
        if (item.expected.operation !== undefined) {
          expect(typed.detail, item.name).toBe(item.expected.operation);
        }
        expect(agent.activeLeases(), item.name).toEqual([]);
      }
    }
  });

  it('releases an active lease once and reports a missing lease', () => {
    const agent = makeAgent();
    agent.start();
    agent.requestCapability(requestCase('camera-authorized'));

    for (const item of fixture.releaseCases) {
      if (item.expected.ok) {
        agent.releaseCapability(item.leaseId);
        expect(agent.activeLeases(), item.name).toEqual([]);
      } else {
        let failure: unknown;
        try {
          agent.releaseCapability(item.leaseId);
        } catch (error) {
          failure = error;
        }
        expect(failure, item.name).toBeInstanceOf(DeviceAgentContractError);
        expect(
          (failure as DeviceAgentContractError).code,
          item.name
        ).toBe(item.expected.code);
      }
    }
  });

  it('delivers subscriptions and enforces typed lifecycle transitions', () => {
    const agent = makeAgent();
    for (const eventType of fixture.subscriptions.eventTypes) {
      const subscription = agent.subscribe(eventType, () => undefined);
      expect(subscription.active).toBe(true);
      subscription.cancel();
      expect(subscription.active).toBe(false);
    }
    expect(() =>
      agent.subscribe(fixture.subscriptions.invalidEventType, () => undefined)
    ).toThrowError(
      expect.objectContaining({ code: 'invalid-event-type' })
    );

    const leaseEvents: DeviceAgentEvent[] = [];
    const lifecycleEvents: DeviceAgentEvent[] = [];
    const leaseSubscription = agent.subscribe('lease', (event) => {
      leaseEvents.push(event);
    });
    const lifecycleSubscription = agent.subscribe('lifecycle', (event) => {
      lifecycleEvents.push(event);
    });

    agent.start();
    const cameraRequest = requestCase('camera-authorized');
    agent.requestCapability(cameraRequest);
    expect(leaseEvents[leaseEvents.length - 1]).toMatchObject({
      type: 'lease',
      action: 'granted',
      leaseId: 'lease-camera-1'
    });

    agent.releaseCapability('lease-camera-1');
    expect(leaseEvents[leaseEvents.length - 1]).toMatchObject({
      type: 'lease',
      action: 'released',
      leaseId: 'lease-camera-1'
    });

    agent.requestCapability(cameraRequest);
    agent.disconnect();
    expect(agent.state).toBe('unavailable');
    expect(agent.activeLeases()).toEqual([]);
    expect(leaseEvents[leaseEvents.length - 1]).toMatchObject({ action: 'revoked' });
    expect(lifecycleEvents[lifecycleEvents.length - 1]).toMatchObject({
      state: 'unavailable'
    });

    expect(() => agent.requestCapability(cameraRequest)).toThrowError(
      expect.objectContaining({ code: 'agent-unavailable' })
    );

    leaseSubscription.cancel();
    lifecycleSubscription.cancel();
  });
});
