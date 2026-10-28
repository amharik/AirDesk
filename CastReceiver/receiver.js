(function () {
  'use strict';

  var inputNamespace = 'urn:x-cast:com.airdesk.input';
  var controlNamespace = 'urn:x-cast:com.airdesk.control';
  var CONTROL_VERSION = 2;
  var INPUT_VERSION = 1;
  var RECEIVER_VERSION = '1';
  var MAX_MESSAGE_BYTES = 64 * 1024;
  var SESSION_GRACE_MS = 30000;
  var BRIDGE_TYPES = ['ready', 'ack', 'log', 'state', 'error', 'viewport', 'action', 'notice'];

  var frame = document.getElementById('desktop-frame');
  var statusText = document.getElementById('receiver-status-text');
  var debug = document.getElementById('receiver-debug');
  var debugSession = document.getElementById('debug-session');
  var debugCount = document.getElementById('debug-count');
  var debugLast = document.getElementById('debug-last');
  var debugState = document.getElementById('debug-state');
  var params = new URLSearchParams(window.location.search);
  var sessionId = params.get('session') || 'cast-preview';
  var generation = Number(params.get('generation') || 0);
  var shellURL = params.get('shell') || '../AirDesk/Resources/DesktopShell/index.html';
  var showDebug = params.get('debug') === '1';
  var shellBase = new URL(shellURL, window.location.href);
  var shellOrigin = params.get('shellOrigin') || shellBase.origin;
  var frameReady = false;
  var shellReady = false;
  var hasSession = false;
  var pending = [];
  var pendingControl = [];
  var inputCount = 0;
  var bridgeRetries = 0;
  var receiverContext = null;
  var graceTimer = 0;
  var lastShellReady = null;
  var lastAcceptedInputSeq = -1;
  var lastInputSeq = -1;
  var acceptedAcks = Object.create(null);
  var processedOperations = Object.create(null);

  if (showDebug) debug.hidden = false;
  debugSession.textContent = sessionId;

  function setStatus(text, connected) {
    statusText.textContent = text;
    document.body.classList.toggle('connected', !!connected);
  }

  function setDebugState(text) {
    debugState.textContent = text;
  }

  function separator(url) {
    return url.indexOf('?') >= 0 ? '&' : '?';
  }

  function payloadSize(value) {
    try { return new TextEncoder().encode(value).length; } catch (error) { return value.length; }
  }

  function shellBridge() {
    try {
      return frame.contentWindow && frame.contentWindow.AirDeskBridge;
    } catch (error) {
      return null;
    }
  }

  function sendControl(message) {
    if (!receiverContext) return;
    var payload = JSON.stringify(message);
    if (payloadSize(payload) > MAX_MESSAGE_BYTES) return;
    try {
      receiverContext.sendCustomMessage(controlNamespace, undefined, payload);
    } catch (error) {
      console.error(error);
    }
  }

  function sendError(code, message) {
    sendControl({
      version: CONTROL_VERSION,
      type: 'error',
      sessionId: sessionId,
      generation: generation,
      code: String(code || 'unknown').slice(0, 64),
      message: String(message || 'Receiver error').slice(0, 4000)
    });
  }

  function shellURLForSession() {
    var url = shellBase.href;
    return url + separator(url) +
      'host=cast' +
      '&session=' + encodeURIComponent(sessionId) +
      '&generation=' + encodeURIComponent(String(generation)) +
      '&parentOrigin=' + encodeURIComponent(window.location.origin);
  }

  function resetSessionState() {
    shellReady = false;
    lastShellReady = null;
    pending = [];
    pendingControl = [];
    lastAcceptedInputSeq = -1;
    lastInputSeq = -1;
    acceptedAcks = Object.create(null);
    inputCount = 0;
    debugCount.textContent = '0';
    debugLast.textContent = '-';
  }

  function beginSession(message) {
    var changed = !hasSession ||
      message.sessionId !== sessionId ||
      message.generation !== generation;

    sessionId = message.sessionId;
    generation = message.generation;
    hasSession = true;
    debugSession.textContent = sessionId;

    if (changed) {
      resetSessionState();
      frameReady = false;
      frame.src = shellURLForSession();
    }

    setStatus('AIRDESK CONNECTED', true);
    setDebugState(changed ? 'shell loading' : 'session resumed');
  }

  function deliverInput(event) {
    var bridge = shellBridge();
    if (!bridge || !shellReady) {
      pending.push(event);
      if (pending.length > 256) pending.shift();
      return;
    }
    try {
      bridge.receive(Object.assign({}, event, {
        sessionId: sessionId,
        generation: generation
      }));
      inputCount += 1;
      debugCount.textContent = String(inputCount);
      debugLast.textContent = String(event.type || 'input');
    } catch (error) {
      console.error(error);
    }
  }

  function deliverControl(message) {
    var bridge = shellBridge();
    if (!bridge || !shellReady) {
      pendingControl.push(message);
      if (pendingControl.length > 32) pendingControl.shift();
      return;
    }
    try {
      bridge.receiveControl(message);
    } catch (error) {
      console.error(error);
    }
  }

  function flushPending() {
    var bridge = shellBridge();
    if (!shellReady || !bridge) return;
    bridgeRetries = 0;
    while (pendingControl.length) {
      try {
        bridge.receiveControl(pendingControl.shift());
      } catch (error) {
        console.error(error);
      }
    }
    while (pending.length) {
      deliverInput(pending.shift());
    }
    debugCount.textContent = String(inputCount);
  }

  function parsePayload(data) {
    if (!data) return null;
    if (typeof data === 'string') {
      if (payloadSize(data) > MAX_MESSAGE_BYTES) return null;
      try { return JSON.parse(data); } catch (error) { return null; }
    }
    return typeof data === 'object' ? data : null;
  }

  function validSession(message) {
    return typeof message.sessionId === 'string' &&
      message.sessionId.length > 0 &&
      message.sessionId.length <= 64 &&
      typeof message.generation === 'number' &&
      message.generation >= 0;
  }

  function validInput(event) {
    if (!event || event.version !== INPUT_VERSION) return false;
    if (!validSession(event)) return false;
    if (typeof event.type !== 'string') return false;
    if (typeof event.seq !== 'number' || event.seq < 0) return false;
    if (typeof event.timestamp !== 'number' || !isFinite(event.timestamp) || event.timestamp <= 0) return false;
    if (event.x != null && (event.x < 0 || event.x > 1)) return false;
    if (event.y != null && (event.y < 0 || event.y > 1)) return false;
    if (event.text != null && (event.text.length === 0 || event.text.length > 4096)) return false;
    if (event.key != null && (event.key.length === 0 || event.key.length > 64)) return false;
    if (event.width != null && (event.width <= 0 || event.width > 20000)) return false;
    if (event.height != null && (event.height <= 0 || event.height > 20000)) return false;
    return true;
  }

  function noteAck(seq) {
    if (typeof seq !== 'number' || seq < 0) return;
    acceptedAcks[seq] = true;
    while (acceptedAcks[lastAcceptedInputSeq + 1]) {
      lastAcceptedInputSeq += 1;
      delete acceptedAcks[lastAcceptedInputSeq];
    }
    sendControl({
      version: CONTROL_VERSION,
      type: 'ack',
      sessionId: sessionId,
      generation: generation,
      lastAcceptedInputSeq: lastAcceptedInputSeq
    });
  }

  function sendReady(width, height, persistence) {
    sendControl({
      version: CONTROL_VERSION,
      type: 'ready',
      sessionId: sessionId,
      generation: generation,
      receiverVersion: RECEIVER_VERSION,
      width: Number(width) || window.innerWidth,
      height: Number(height) || window.innerHeight,
      persistence: String(persistence || 'unknown').slice(0, 64),
      capabilities: {
        pointer: true,
        keyboard: true,
        textInput: true,
        desktopWindows: true
      },
      lastAcceptedInputSeq: Math.max(0, lastAcceptedInputSeq)
    });
  }

  function sendCurrentReady() {
    if (!shellReady) return false;
    var ready = lastShellReady || {};
    sendReady(ready.width, ready.height, ready.persistence);
    return true;
  }

  function handleInput(data) {
    var event = parsePayload(data);
    if (!event) return;
    if (!validInput(event)) {
      sendError('invalidInput', 'Input event validation failed');
      return;
    }
    if (!hasSession || event.sessionId !== sessionId) return;
    if (event.generation !== generation) return;
    if (event.seq <= lastInputSeq) return;
    lastInputSeq = event.seq;
    deliverInput(event);
  }

  function handleControl(data) {
    var message = parsePayload(data);
    if (!message || typeof message.type !== 'string') return;
    if (message.version !== CONTROL_VERSION) {
      sendError('unsupportedVersion', 'Unsupported control protocol version');
      return;
    }
    if (!validSession(message)) {
      sendError('invalidSession', 'Invalid Cast session');
      return;
    }

    if (hasSession) {
      if (message.type === 'sessionStart') {
        if (message.generation < generation) {
          sendError('staleGeneration', 'The receiver has a newer session generation');
          return;
        }
      } else if (message.sessionId !== sessionId || message.generation !== generation) {
        if (message.type !== 'sessionEnd') {
          sendError('sessionMismatch', 'The message belongs to a different session');
        }
        return;
      }
    }

    switch (message.type) {
    case 'sessionStart':
      if (!message.protocol ||
          message.protocol.control !== CONTROL_VERSION ||
          message.protocol.input !== INPUT_VERSION) {
        sendError('unsupportedVersion', 'Unsupported input protocol version');
        return;
      }
      if (typeof message.workspace !== 'string' || message.workspace.length === 0 ||
          message.workspace.length > 128 ||
          typeof message.appearance !== 'string' || message.appearance.length === 0 ||
          message.appearance.length > 32) {
        sendError('invalidField', 'Invalid session fields');
        return;
      }
      if (message.operationId && processedOperations[message.operationId]) {
        sendCurrentReady();
        return;
      }
      beginSession(message);
      if (message.operationId) {
        if (Object.keys(processedOperations).length > 256) {
          processedOperations = Object.create(null);
        }
        processedOperations[message.operationId] = true;
      }
      break;
    case 'sessionResume':
      if (!hasSession || message.sessionId !== sessionId) {
        sendError('sessionNotFound', 'The receiver no longer has this session');
        return;
      }
      if (message.generation !== generation) {
        sendError('staleGeneration', 'The receiver has a newer session generation');
        return;
      }
      if (sendCurrentReady()) {
        flushPending();
      } else {
        setDebugState('resume waiting for shell');
      }
      break;
    case 'sessionEnd':
      if (message.sessionId !== sessionId || message.generation !== generation) return;
      hasSession = false;
      shellReady = false;
      setStatus('AIRDESK RECEIVER', false);
      setDebugState('session ended');
      clearTimeout(graceTimer);
      graceTimer = window.setTimeout(function () {
        resetSessionState();
        frame.src = 'about:blank';
        setDebugState('idle');
      }, SESSION_GRACE_MS);
      break;
    case 'appearance':
    case 'workspace':
      if (message.sessionId !== sessionId || message.generation !== generation) return;
      deliverControl(message);
      break;
    case 'ping':
      sendControl({
        version: CONTROL_VERSION,
        type: 'pong',
        sessionId: sessionId,
        generation: generation
      });
      break;
    default:
      sendError('unsupportedType', 'Unsupported control message type');
      break;
    }
  }

  function handleShellMessage(message) {
    if (!message || typeof message !== 'object') return;
    if (BRIDGE_TYPES.indexOf(message.type) < 0) return;
    if (message.sessionId !== sessionId) return;
    if (Number(message.generation) !== generation) return;

    switch (message.type) {
    case 'ready':
      if (!hasSession) return;
      shellReady = true;
      lastShellReady = message;
      setStatus('AIRDESK CONNECTED', true);
      setDebugState('shell ready');
      sendReady(message.width, message.height, message.persistence);
      flushPending();
      break;
    case 'ack':
      if (hasSession) noteAck(message.seq);
      break;
    case 'state':
      if (hasSession && message.message) {
        sendControl({
          version: CONTROL_VERSION,
          type: 'state',
          sessionId: sessionId,
          generation: generation,
          state: String(message.message).slice(0, 64)
        });
      }
      break;
    case 'viewport':
      if (hasSession) {
        sendControl({
          version: CONTROL_VERSION,
          type: 'viewport',
          sessionId: sessionId,
          generation: generation,
          width: Number(message.width),
          height: Number(message.height)
        });
      }
      break;
    case 'notice':
      if (hasSession && message.message) {
        sendControl({
          version: CONTROL_VERSION,
          type: 'notice',
          sessionId: sessionId,
          generation: generation,
          message: String(message.message).slice(0, 4000)
        });
      }
      break;
    case 'error':
      if (hasSession) {
        sendError('shellError', String(message.message || 'Desktop shell error'));
      }
      break;
    default:
      break;
    }
  }

  frame.addEventListener('load', function () {
    frameReady = true;
    bridgeRetries = 0;
    setDebugState('shell loading');
  });
  frame.addEventListener('error', function () {
    setStatus('AIRDESK SHELL ERROR', false);
    setDebugState('shell error');
  });

  window.addEventListener('message', function (event) {
    if (event.source !== frame.contentWindow) return;
    if (event.origin !== shellOrigin) return;
    handleShellMessage(event.data);
  });

  frame.src = shellURLForSession();

  function startReceiver() {
    var caf = window.cast && window.cast.framework;
    if (!caf || !caf.CastReceiverContext) {
      setStatus('AIRDESK PREVIEW', false);
      setDebugState('cast sdk unavailable');
      return;
    }
    receiverContext = caf.CastReceiverContext.getInstance();
    var options = new caf.CastReceiverOptions();
    options.disableIdleTimeout = true;
    receiverContext.addCustomMessageListener(inputNamespace, function (event) {
      handleInput(event.data);
    });
    receiverContext.addCustomMessageListener(controlNamespace, function (event) {
      handleControl(event.data);
    });
    if (caf.system && caf.system.EventType && caf.system.EventType.READY) {
      receiverContext.addEventListener(caf.system.EventType.READY, function () {
        setStatus('AIRDESK READY', false);
        setDebugState('receiver ready');
      });
    }
    receiverContext.start(options);
    setStatus('AIRDESK READY', false);
    setDebugState('receiver ready');
  }

  window.AirDeskReceiver = {
    handleInput: handleInput,
    handleControl: handleControl,
    handleShellMessage: handleShellMessage,
    pendingCount: function () { return pending.length + pendingControl.length; },
    bridgeReady: function () { return shellReady; }
  };

  window.addEventListener('load', startReceiver);
})();
