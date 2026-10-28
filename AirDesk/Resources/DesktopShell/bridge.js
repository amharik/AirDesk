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
  var generation = Number(window.AIRDESK_GENERATION || query.generation || 0);
  var host = String(window.AIRDESK_HOST || query.host || 'native');
  var parentOrigin = String(window.AIRDESK_PARENT_ORIGIN || query.parentOrigin || '');
  var runtime = String(window.AIRDESK_RUNTIME || query.runtime || 'wanixDesktop');
  var appearance = String(window.AIRDESK_APPEARANCE || query.appearance || 'dark');
  var inputHandlers = [];
  var controlHandlers = [];
  var readySent = false;
  var lastViewport = { width: 0, height: 0 };
  var reportedError = false;

  function post(message) {
    if (host === 'cast') {
      if (!parentOrigin || window.parent === window) return false;
      try {
        window.parent.postMessage(message, parentOrigin);
        return true;
      } catch (error) {
        return false;
      }
    }
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
      generation: generation,
      runtime: runtime,
      width: window.innerWidth,
      height: window.innerHeight,
      persistence: window.AirDeskKernel && window.AirDeskKernel.persistence
        ? String(window.AirDeskKernel.persistence())
        : 'unknown',
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
      generation: generation,
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
      generation: generation,
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
      generation: generation,
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
      generation: generation,
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
      generation: generation,
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
    if (event.generation != null && Number(event.generation) !== generation) return;
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
    if (message.sessionId && message.sessionId !== sessionId) return;
    if (message.generation != null && Number(message.generation) !== generation) return;
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
    generation: generation,
    host: host,
    runtime: runtime,
    native: host === 'cast' ? !!parentOrigin : !!handler,
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
