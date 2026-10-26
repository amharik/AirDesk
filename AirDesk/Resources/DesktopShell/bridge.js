/* AirDesk native bridge v1. */
(function () {
  'use strict';

  var handler = null;
  try {
    handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.airdesk;
  } catch (error) {
    handler = null;
  }

  var query = {};
  try {
    var params = new URLSearchParams(window.location.search);
    params.forEach(function (value, key) { query[key] = value; });
  } catch (error) { query = {}; }
  var sessionId = String(window.AIRDESK_SESSION_ID || query.session || 'preview');
  var runtime = String(window.AIRDESK_RUNTIME || query.runtime || 'wanixDesktop');
  var appearance = String(window.AIRDESK_APPEARANCE || query.appearance || 'dark');
  var inputHandlers = [];
  var controlHandlers = [];
  var readySent = false;
  var lastViewport = { width: 0, height: 0 };
  var reportedError = false;

  function post(message) {
    if (!handler || typeof handler.postMessage !== 'function') return false;
    try {
      handler.postMessage(message);
      return true;
    } catch (error) {
      return false;
    }
  }

  function ready() {
    if (readySent) return;
    readySent = true;
    post({
      version: 1,
      type: 'ready',
      sessionId: sessionId,
      runtime: runtime,
      width: window.innerWidth,
      height: window.innerHeight,
      timestamp: Date.now()
    });
  }

  function viewport(width, height) {
    var w = Math.round(width || window.innerWidth);
    var h = Math.round(height || window.innerHeight);
    if (w === lastViewport.width && h === lastViewport.height) return;
    lastViewport = { width: w, height: h };
    post({
      version: 1,
      type: 'viewport',
      sessionId: sessionId,
      width: w,
      height: h,
      timestamp: Date.now()
    });
  }

  function notice(text) {
    if (!text) return;
    post({
      version: 1,
      type: 'notice',
      sessionId: sessionId,
      message: String(text).slice(0, 180),
      timestamp: Date.now()
    });
  }

  function state(name) {
    if (!name) return;
    post({
      version: 1,
      type: 'state',
      sessionId: sessionId,
      message: String(name).slice(0, 80),
      timestamp: Date.now()
    });
  }

  function error(message) {
    if (reportedError) return;
    reportedError = true;
    post({
      version: 1,
      type: 'error',
      sessionId: sessionId,
      message: String(message || 'Desktop shell error').slice(0, 4000),
      timestamp: Date.now()
    });
  }

  function ack(event) {
    if (!event || typeof event.seq !== 'number') return;
    post({
      version: 1,
      type: 'ack',
      sessionId: sessionId,
      seq: event.seq,
      timestamp: Date.now()
    });
  }

  function onInput(fn) {
    if (typeof fn === 'function') inputHandlers.push(fn);
  }

  function onControl(fn) {
    if (typeof fn === 'function') controlHandlers.push(fn);
  }

  function receiveInput(event) {
    if (!event || typeof event !== 'object') return;
    if (event.sessionId && event.sessionId !== sessionId) return;
    try {
      inputHandlers.forEach(function (fn) {
        try { fn(event); } catch (handlerError) { console.error(handlerError); }
      });
    } finally {
      ack(event);
    }
  }

  function receiveControl(message) {
    if (!message || typeof message !== 'object') return;
    if (message.type === 'appearance' && message.appearance) {
      appearance = String(message.appearance);
    }
    controlHandlers.forEach(function (fn) {
      try { fn(message); } catch (handlerError) { console.error(handlerError); }
    });
  }

  window.AirDeskBridge = {
    receive: receiveInput,
    receiveControl: receiveControl
  };

  window.AD = {
    sessionId: sessionId,
    runtime: runtime,
    native: !!handler,
    appearance: appearance,
    post: post,
    ready: ready,
    viewport: viewport,
    notice: notice,
    state: state,
    error: error,
    onInput: onInput,
    onControl: onControl
  };

  window.addEventListener('error', function (event) {
    if (event && event.message) error(event.message);
  });
  window.addEventListener('unhandledrejection', function (event) {
    error(event && event.reason ? String(event.reason) : 'Unhandled promise rejection');
  });

  var resizeTimer = 0;
  window.addEventListener('resize', function () {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function () { viewport(); }, 120);
  });
})();
