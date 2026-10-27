/* AirDesk live Wanix kernel for the desktop shell. */
(function () {
  'use strict';

  var host = document.getElementById('wanix');
  var resolveReady;
  var rejectReady;
  var ready = new Promise(function (resolve, reject) {
    resolveReady = resolve;
    rejectReady = reject;
  });
  ready.catch(function () { /* surfaced through the shell and native bridge */ });

  var root = null;
  var failed = false;
  var readyTimer = 0;
  var persistent = true;
  var shellStarted = false;
  var terminalPath = '#task/shell/term';

  function bridge() {
    return window.AD || null;
  }

  function fail(message) {
    if (failed) return;
    failed = true;
    clearTimeout(readyTimer);
    var text = String(message || 'The Wanix kernel did not become ready.');
    rejectReady(new Error(text));
    var api = bridge();
    if (api) {
      api.error(text);
      api.state('wanix.failed');
    }
  }

  function useRamWorkspace() {
    persistent = false;
    var opfsBind = document.getElementById('opfs-bind');
    if (opfsBind) {
      opfsBind.setAttribute('src', '#ramfs/new');
      opfsBind.setAttribute('data-fallback', 'true');
      opfsBind.removeAttribute('id');
    }
    var api = bridge();
    if (api) api.state('wanix.ramfs');
  }

  function prepareWorkspace() {
    var opfsBind = document.getElementById('opfs-bind');
    if (!opfsBind) {
      persistent = false;
      return Promise.resolve(false);
    }
    if (location.search.indexOf('noopfs') >= 0 || !(navigator.storage && navigator.storage.getDirectory)) {
      useRamWorkspace();
      return Promise.resolve(false);
    }
    return navigator.storage.getDirectory().then(function () {
      return true;
    }).catch(function () {
      useRamWorkspace();
      return false;
    });
  }

  function loadRuntime() {
    var script = document.createElement('script');
    script.type = 'module';
    script.src = 'https://cdn.jsdelivr.net/npm/wanix@0.4.0-rc2/dist/wanix.min.js';
    script.addEventListener('error', function () {
      fail('The Wanix runtime could not be loaded from the network.');
    });
    document.head.appendChild(script);
  }

  function boot() {
    if (!host) {
      fail('The Wanix namespace element is missing from the desktop shell.');
      return;
    }

    host.addEventListener('ready', function () {
      if (failed) return;
      clearTimeout(readyTimer);
      root = host.root;
      resolveReady(root);
      var api = bridge();
      if (api) api.state('wanix.ready');
    });

    host.addEventListener('error', function (event) {
      var detail = event && event.detail;
      var error = detail && detail.error ? detail.error : detail;
      fail(error && error.message ? error.message : error);
    });

    readyTimer = setTimeout(function () {
      if (!root) fail('The Wanix kernel did not become ready. Check the network connection and retry.');
    }, 45000);

    prepareWorkspace().then(loadRuntime);
  }

  function handle() {
    if (root) return Promise.resolve(root);
    return ready;
  }

  window.AirDeskKernel = {
    ready: ready,
    terminalPath: terminalPath,
    persistent: function () { return persistent; },
    root: function () { return root; },
    startShell: function () {
      if (shellStarted) return Promise.resolve(true);
      return handle().then(function (kernelRoot) {
        return kernelRoot.writeFile('#task/shell/ctl', 'start').then(function () {
          shellStarted = true;
          var api = bridge();
          if (api) api.state('wanix.shell.started');
          return true;
        });
      });
    },
    list: function (path) {
      return handle().then(function (kernelRoot) {
        return kernelRoot.readDir(path || '.');
      });
    },
    stat: function (path) {
      return handle().then(function (kernelRoot) {
        return kernelRoot.stat(path);
      });
    },
    readText: function (path) {
      return handle().then(function (kernelRoot) {
        return kernelRoot.readText(path);
      });
    },
    writeText: function (path, text) {
      return handle().then(function (kernelRoot) {
        return kernelRoot.writeFile(path, text);
      });
    }
  };

  boot();
})();
