(function () {
  'use strict';

  var inputNamespace = 'urn:x-cast:com.airdesk.input';
  var controlNamespace = 'urn:x-cast:com.airdesk.control';
  var frame = document.getElementById('desktop-frame');
  var statusText = document.getElementById('receiver-status-text');
  var debug = document.getElementById('receiver-debug');
  var debugSession = document.getElementById('debug-session');
  var debugCount = document.getElementById('debug-count');
  var debugLast = document.getElementById('debug-last');
  var debugState = document.getElementById('debug-state');
  var params = new URLSearchParams(window.location.search);
  var sessionId = params.get('session') || 'cast-preview';
  var shellURL = params.get('shell') || '../AirDesk/Resources/DesktopShell/index.html';
  var showDebug = params.get('debug') === '1';
  var frameReady = false;
  var pending = [];
  var inputCount = 0;
  var receiverContext = null;

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

  frame.src = shellURL + separator(shellURL) + 'session=' + encodeURIComponent(sessionId);

  function shellBridge() {
    try {
      return frame.contentWindow && frame.contentWindow.AirDeskBridge;
    } catch (error) {
      return null;
    }
  }

  function deliverInput(event) {
    var bridge = shellBridge();
    if (!bridge || !frameReady) {
      pending.push(event);
      return;
    }
    bridge.receive(Object.assign({}, event, { sessionId: sessionId }));
    inputCount += 1;
    debugCount.textContent = String(inputCount);
    debugLast.textContent = String(event.type || 'input');
  }

  function deliverControl(message) {
    var bridge = shellBridge();
    if (!bridge || !frameReady) return;
    bridge.receiveControl(message);
  }

  function parsePayload(data) {
    if (!data) return null;
    if (typeof data === 'string') {
      try { return JSON.parse(data); } catch (error) { return null; }
    }
    return typeof data === 'object' ? data : null;
  }

  function handleInput(data) {
    var event = parsePayload(data);
    if (!event || typeof event.type !== 'string') return;
    if (event.sessionId && event.sessionId !== sessionId) return;
    deliverInput(event);
  }

  function handleControl(data) {
    var message = parsePayload(data);
    if (!message || typeof message.type !== 'string') return;
    if (message.type === 'appearance' && message.appearance) {
      deliverControl({ type: 'appearance', appearance: String(message.appearance) });
    }
    if (message.type === 'sessionStart') {
      setStatus('AIRDESK CONNECTED', true);
      setDebugState('session');
    }
    if (message.type === 'sessionEnd' || message.type === 'shutdown') {
      setStatus('AIRDESK RECEIVER', false);
      setDebugState('idle');
    }
    if (message.type === 'workspace' && message.name) {
      setDebugState('workspace ' + String(message.name));
    }
  }

  frame.addEventListener('load', function () {
    frameReady = true;
    setDebugState('shell ready');
    while (pending.length) deliverInput(pending.shift());
  });

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

  window.addEventListener('load', startReceiver);
})();
