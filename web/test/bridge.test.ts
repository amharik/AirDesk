import { JSDOM } from 'jsdom';
import { describe, expect, it } from 'vitest';
import { installBridge } from '../src/bridge/bridge';
import type { BridgeMessage } from '../src/bridge/types';

type TestWindow = Window & {
  webkit?: {
    messageHandlers?: {
      airdesk?: {
        postMessage(message: unknown): void;
      };
    };
  };
};

function makeBridge(search = ''): {
  window: TestWindow;
  posted: BridgeMessage[];
  bridge: ReturnType<typeof installBridge>;
} {
  const dom = new JSDOM('<!doctype html>', {
    url: `https://airdesk.test/index.html${search}`,
    pretendToBeVisual: true
  });
  const posted: BridgeMessage[] = [];
  const window = dom.window as unknown as TestWindow;
  window.webkit = {
    messageHandlers: {
      airdesk: {
        postMessage(message: unknown) {
          posted.push(message as BridgeMessage);
        }
      }
    }
  };
  return { window, posted, bridge: installBridge(window) };
}

describe('bridge', () => {
  it('posts ready once and deduplicates viewport updates', () => {
    const { window, posted } = makeBridge('?session=live&generation=7&runtime=test-runtime');
    window.AirDeskKernel = { persistence: () => 'opfs' };

    window.AD!.ready();
    window.AD!.ready();
    window.AD!.viewport(1000, 700);
    window.AD!.viewport(1000, 700);

    expect(posted).toHaveLength(2);
    expect(posted[0]).toMatchObject({
      type: 'ready',
      sessionId: 'live',
      generation: 7,
      runtime: 'test-runtime',
      persistence: 'opfs'
    });
    expect(posted[1]).toMatchObject({
      type: 'viewport',
      sessionId: 'live',
      generation: 7,
      width: 1000,
      height: 700
    });
  });

  it('routes matching input and acknowledges it', () => {
    const { window, posted, bridge } = makeBridge('?session=live&generation=7');
    const seen: BridgeMessage[] = [];
    window.AD!.onInput((event) => seen.push(event));

    bridge.receive({ sessionId: 'other', seq: 8 });
    bridge.receive({ sessionId: 'live', generation: 6, seq: 9 });
    bridge.receive({ sessionId: 'live', generation: 7, type: 'pointerMove', seq: 10 });

    expect(seen).toEqual([{ sessionId: 'live', generation: 7, type: 'pointerMove', seq: 10 }]);
    expect(posted).toEqual([
      { version: 1, type: 'ack', sessionId: 'live', generation: 7, seq: 10, timestamp: expect.any(Number) }
    ]);
  });

  it('routes matching control messages only once', () => {
    const { window, bridge } = makeBridge('?session=live&generation=7');
    const seen: BridgeMessage[] = [];
    window.AD!.onControl((message) => seen.push(message));

    bridge.receiveControl({ sessionId: 'live', generation: 7, type: 'appearance', appearance: 'light' });
    bridge.receiveControl({ sessionId: 'other', generation: 7, type: 'appearance', appearance: 'dark' });
    bridge.receiveControl({ sessionId: 'live', generation: 8, type: 'appearance', appearance: 'dark' });

    expect(seen).toEqual([
      { sessionId: 'live', generation: 7, type: 'appearance', appearance: 'light' }
    ]);
  });

  it('bounds notices, state names, and errors', () => {
    const { window, posted } = makeBridge();
    window.AD!.notice('n'.repeat(200));
    window.AD!.state('');
    window.AD!.error('e'.repeat(5000));
    window.AD!.error('second error');

    const notices = posted.filter((message) => message.type === 'notice');
    const states = posted.filter((message) => message.type === 'state');
    const errors = posted.filter((message) => message.type === 'error');

    expect(notices).toHaveLength(1);
    expect(String(notices[0]?.message)).toHaveLength(180);
    expect(states).toHaveLength(0);
    expect(errors).toHaveLength(1);
    expect(String(errors[0]?.message)).toHaveLength(4000);
  });

  it('ignores malformed messages', () => {
    const { bridge } = makeBridge();

    expect(() => bridge.receive(null)).not.toThrow();
    expect(() => bridge.receive('input')).not.toThrow();
    expect(() => bridge.receiveControl(undefined)).not.toThrow();
  });
});
