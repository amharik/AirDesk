/* AirDesk live Wanix kernel surface. */
(function () {
  'use strict';

  var system = document.getElementById('wanix');
  var term = document.querySelector('wanix-term');
  var boot = document.getElementById('boot');
  var failure = document.getElementById('failure');
  var failureMessage = document.getElementById('failure-message');
  var retry = document.getElementById('retry');
  var statusLabel = document.getElementById('status-label');

  var ready = false;
  var failed = false;
  var lastSeq = -1;
  var pendingData = [];
  var maxPending = 256;
  var readyTimer = 0;

  function bridge() {
    return window.AD || null;
  }

  function setStatus(text) {
    if (statusLabel) statusLabel.textContent = text;
  }

  function showFailure(message) {
    if (failed) return;
    failed = true;
    clearTimeout(readyTimer);
    var text = String(message || 'The live runtime did not become ready.');
    if (failureMessage) failureMessage.textContent = text;
    if (failure) failure.hidden = false;
    if (boot) boot.hidden = true;
    setStatus('WANIX KERNEL · FAILED');
    var api = bridge();
    if (api) {
      api.error(text);
      api.state('failed');
    }
  }

  function setAppearance(value) {
    var appearance = value === 'light' ? 'light' : 'dark';
    document.documentElement.dataset.appearance = appearance;
    document.body.dataset.appearance = appearance;
  }

  function terminal() {
    return term && term._term ? term._term : null;
  }

  function focusTerminal() {
    try {
      if (term && typeof term.focus === 'function') term.focus();
    } catch (error) {
      // Ignore focus failures while the terminal is still connecting.
    }
  }

  function fitTerminal() {
    try {
      if (term && typeof term.fit === 'function') term.fit();
      var api = bridge();
      if (api) api.viewport(window.innerWidth, window.innerHeight);
    } catch (error) {
      // The terminal can be between connection states during a resize.
    }
  }

  function sendData(data) {
    if (!data) return;
    var t = terminal();
    if (!ready || !t) {
      if (pendingData.length < maxPending) pendingData.push(data);
      return;
    }

    try {
      if (typeof t.input === 'function') {
        t.input(data, true);
      } else if (typeof t.paste === 'function') {
        t.paste(data);
      } else if (term && typeof term.write === 'function') {
        term.write(data);
      }
    } catch (error) {
      showFailure('The terminal rejected input: ' + error);
    }
  }

  function flushPending() {
    if (!terminal() || !pendingData.length) return;
    var queued = pendingData;
    pendingData = [];
    queued.forEach(sendData);
  }

  function keyData(event) {
    var key = event.key || '';
    var modifiers = Array.isArray(event.modifiers) ? event.modifiers : [];
    var control = modifiers.indexOf('Control') >= 0;
    var alt = modifiers.indexOf('Alt') >= 0 || modifiers.indexOf('Meta') >= 0;

    var named = {
      Enter: '\r',
      Return: '\r',
      Backspace: '\x7f',
      Delete: '\x1b[3~',
      Tab: '\t',
      Escape: '\x1b',
      ArrowUp: '\x1b[A',
      ArrowDown: '\x1b[B',
      ArrowRight: '\x1b[C',
      ArrowLeft: '\x1b[D',
      Home: '\x1b[H',
      End: '\x1b[F',
      PageUp: '\x1b[5~',
      PageDown: '\x1b[6~',
      Insert: '\x1b[2~',
      Space: ' '
    };

    var data = '';
    if (Object.prototype.hasOwnProperty.call(named, key)) {
      data = named[key];
    } else if (key.length === 1) {
      if (control) {
        var code = key.toUpperCase().charCodeAt(0);
        data = code >= 64 && code <= 95 ? String.fromCharCode(code & 31) : key;
      } else {
        data = key;
      }
    } else {
      return '';
    }

    if (alt && data !== '\x1b') data = '\x1b' + data;
    return data;
  }

  function onInput(event) {
    if (!event || typeof event !== 'object') return;

    if (typeof event.seq === 'number' && event.seq >= 0) {
      if (event.seq <= lastSeq) return;
      lastSeq = event.seq;
    }

    switch (event.type) {
      case 'textInput':
        sendData(String(event.text || ''));
        break;
      case 'keyDown':
        sendData(keyData(event));
        break;
      case 'keyUp':
        break;
      case 'pointerDown':
      case 'pointerUp':
      case 'pointerClick':
        focusTerminal();
        break;
      case 'scroll':
        var t = terminal();
        if (t && typeof t.scrollLines === 'function') {
          var lines = Math.round(Number(event.dy || 0) / 24);
          if (lines) t.scrollLines(-Math.max(-8, Math.min(8, lines)));
        }
        break;
      case 'focusChanged':
      case 'sessionStart':
        focusTerminal();
        break;
      case 'sessionEnd':
      case 'pointerCancel':
        break;
      default:
        break;
    }
  }

  function onControl(message) {
    if (!message || typeof message !== 'object') return;
    switch (message.type) {
      case 'appearance':
        setAppearance(message.appearance);
        break;
      case 'workspace':
        setStatus('WANIX · ' + String(message.name || 'WORKSPACE').toUpperCase());
        break;
      case 'suspend':
        var suspended = bridge();
        if (suspended) suspended.state('suspended');
        break;
      case 'resume':
        focusTerminal();
        fitTerminal();
        var resumed = bridge();
        if (resumed) resumed.state('ready');
        break;
      case 'shutdown':
        var stopped = bridge();
        if (stopped) stopped.state('stopped');
        break;
      case 'action':
        if (message.action === 'dock') focusTerminal();
        break;
      default:
        break;
    }
  }

  function markReady() {
    if (ready || failed) return;
    ready = true;
    clearTimeout(readyTimer);
    document.body.classList.add('ready');
    setStatus('WANIX KERNEL · READY');
    if (boot) boot.hidden = true;

    fitTerminal();
    focusTerminal();
    setTimeout(function () {
      fitTerminal();
      focusTerminal();
      flushPending();
    }, 240);

    var api = bridge();
    if (api) {
      api.ready();
      api.state('ready');
    }
  }

  function start() {
    var api = bridge();
    if (api) {
      api.onInput(onInput);
      api.onControl(onControl);
      setAppearance(api.appearance);
    }

    if (!system) {
      showFailure('The Wanix namespace element is missing.');
      return;
    }

    system.addEventListener('ready', markReady);
    system.addEventListener('error', function (event) {
      var detail = event && event.detail;
      var error = detail && detail.error ? detail.error : detail;
      var message = error && error.message ? error.message : (error || 'The Wanix kernel reported a load error.');
      showFailure(message);
    });

    window.addEventListener('resize', function () {
      fitTerminal();
    });

    readyTimer = setTimeout(function () {
      if (!ready) {
        showFailure('The live Wanix kernel did not become ready. Check the network connection and retry.');
      }
    }, 45000);
  }

  if (retry) {
    retry.addEventListener('click', function () {
      window.location.reload();
    });
  }

  start();
})();
