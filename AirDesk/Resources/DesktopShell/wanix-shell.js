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
  var database = null;
  var persistTimer = 0;
  var persistInFlight = false;
  var restoreInFlight = false;
  var snapshotBackend = 'indexeddb';
  var lastPersistError = null;
  var DB_NAME = 'airdesk.workspace.v1';
  var DB_STORE = 'snapshots';
  var DB_KEY = 'opfs';
  var LOCAL_KEY = 'airdesk.workspace.snapshot.v1';
  var MAX_SNAPSHOT_FILE = 2 * 1024 * 1024;

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
    snapshotBackend = 'indexeddb';
    var opfsBind = document.getElementById('opfs-bind');
    if (opfsBind) {
      opfsBind.setAttribute('src', '#ramfs/new');
      opfsBind.setAttribute('data-fallback', 'true');
      opfsBind.removeAttribute('id');
    }
    var api = bridge();
    if (api) api.state('wanix.ramfs');
  }

  function openDatabase() {
    if (database) return Promise.resolve(database);
    return new Promise(function (resolve, reject) {
      if (!window.indexedDB) {
        reject(new Error('IndexedDB is unavailable.'));
        return;
      }
      var request = indexedDB.open(DB_NAME, 1);
      request.onupgradeneeded = function () {
        var db = request.result;
        if (!db.objectStoreNames.contains(DB_STORE)) db.createObjectStore(DB_STORE);
      };
      request.onsuccess = function () {
        database = request.result;
        resolve(database);
      };
      request.onerror = function () {
        reject(request.error || new Error('IndexedDB could not be opened.'));
      };
      request.onblocked = function () {
        reject(new Error('IndexedDB is blocked by another tab.'));
      };
    });
  }

  function readLocalSnapshot() {
    try {
      var raw = localStorage.getItem(LOCAL_KEY);
      if (!raw) return null;
      snapshotBackend = 'localstorage';
      return JSON.parse(raw);
    } catch (error) {
      return null;
    }
  }

  function writeLocalSnapshot(snapshot) {
    try {
      localStorage.setItem(LOCAL_KEY, JSON.stringify(snapshot));
      snapshotBackend = 'localstorage';
      return true;
    } catch (error) {
      snapshotBackend = 'none';
      return false;
    }
  }

  function readSnapshot() {
    return openDatabase().then(function (db) {
      return new Promise(function (resolve, reject) {
        var transaction = db.transaction(DB_STORE, 'readonly');
        var request = transaction.objectStore(DB_STORE).get(DB_KEY);
        request.onsuccess = function () { resolve(request.result || null); };
        request.onerror = function () { reject(request.error || new Error('Snapshot read failed.')); };
      });
    }).catch(function () {
      return readLocalSnapshot();
    });
  }

  function writeSnapshot(snapshot) {
    return openDatabase().then(function (db) {
      return new Promise(function (resolve, reject) {
        var transaction = db.transaction(DB_STORE, 'readwrite');
        transaction.objectStore(DB_STORE).put(snapshot, DB_KEY);
        transaction.oncomplete = function () { resolve(true); };
        transaction.onerror = function () { reject(transaction.error || new Error('Snapshot write failed.')); };
        transaction.onabort = function () { reject(transaction.error || new Error('Snapshot write aborted.')); };
      });
    }).catch(function () {
      return writeLocalSnapshot(snapshot);
    });
  }

  function bytesToBase64(bytes) {
    var chunk = 0x8000;
    var binary = '';
    for (var index = 0; index < bytes.length; index += chunk) {
      binary += String.fromCharCode.apply(null, bytes.subarray(index, index + chunk));
    }
    return btoa(binary);
  }

  function base64ToBytes(text) {
    var binary = atob(text);
    var bytes = new Uint8Array(binary.length);
    for (var index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
    return bytes;
  }

  function collectWorkspaceFiles(kernelRoot, directory, relative, files) {
    return kernelRoot.readDir(directory).then(function (entries) {
      entries = entries || [];
      return entries.reduce(function (chain, entry) {
        return chain.then(function () {
          var isDirectory = entry.charAt(entry.length - 1) === '/';
          var name = isDirectory ? entry.slice(0, -1) : entry;
          var path = directory === '.' ? name : directory + '/' + name;
          var childRelative = relative ? relative + '/' + name : name;
          if (isDirectory) return collectWorkspaceFiles(kernelRoot, path, childRelative, files);
          return kernelRoot.stat(path).then(function (info) {
            if (info && info.Size > MAX_SNAPSHOT_FILE) return;
            return kernelRoot.readFile(path).then(function (bytes) {
              files[childRelative] = bytesToBase64(bytes);
            });
          }).catch(function () { /* skip unreadable entries */ });
        });
      }, Promise.resolve());
    }).catch(function () { /* an empty fallback workspace has no opfs directory yet */ });
  }

  function snapshotWorkspace() {
    if (persistent || !root || restoreInFlight || persistInFlight) return Promise.resolve(false);
    persistInFlight = true;
    var files = {};
    return collectWorkspaceFiles(root, 'opfs', '', files).then(function () {
      return writeSnapshot({ version: 1, savedAt: Date.now(), files: files });
    }).then(function (written) {
      lastPersistError = written ? null : 'Workspace snapshot could not be stored.';
      return !!written;
    }).catch(function (error) {
      lastPersistError = String(error && error.message || error);
      return false;
    }).then(function (result) {
      persistInFlight = false;
      return result;
    });
  }

  function schedulePersist() {
    if (persistent) return;
    clearTimeout(persistTimer);
    persistTimer = setTimeout(snapshotWorkspace, 600);
  }

  function restoreWorkspace(kernelRoot) {
    if (persistent) return Promise.resolve(false);
    restoreInFlight = true;
    return readSnapshot().then(function (snapshot) {
      var files = snapshot && snapshot.files ? snapshot.files : {};
      return Object.keys(files).reduce(function (chain, relative) {
        return chain.then(function () {
          var path = 'opfs/' + relative;
          var parent = path.split('/').slice(0, -1).join('/');
          var prepare = parent ? kernelRoot.makeDirAll(parent).catch(function () {}) : Promise.resolve();
          return prepare.then(function () {
            return kernelRoot.writeFile(path, base64ToBytes(files[relative]));
          }).catch(function (error) {
            lastPersistError = String(error && error.message || error);
          });
        });
      }, Promise.resolve());
    }).catch(function (error) {
      lastPersistError = String(error && error.message || error);
    }).then(function () {
      restoreInFlight = false;
      return true;
    });
  }

  function startPersistenceLoop() {
    if (persistent) return;
    setInterval(function () {
      if (!document.hidden) snapshotWorkspace();
    }, 4000);
    document.addEventListener('visibilitychange', function () {
      if (document.hidden) snapshotWorkspace();
    });
    window.addEventListener('pagehide', function () { snapshotWorkspace(); });
  }

  function prepareWorkspace() {
    var opfsBind = document.getElementById('opfs-bind');
    if (!opfsBind) {
      persistent = false;
      return Promise.resolve(false);
    }
    var supportsOPFSWrites = typeof FileSystemFileHandle !== 'undefined' &&
      FileSystemFileHandle.prototype &&
      typeof FileSystemFileHandle.prototype.createWritable === 'function';
    if (location.search.indexOf('noopfs') >= 0 || !(navigator.storage && navigator.storage.getDirectory) || !supportsOPFSWrites) {
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
      var finish = function () {
        resolveReady(root);
        var api = bridge();
        if (api) api.state('wanix.ready');
      };
      if (persistent) {
        finish();
      } else {
        startPersistenceLoop();
        restoreWorkspace(root).then(finish, finish);
      }
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
    persistence: function () {
      if (persistent) return 'opfs';
      if (snapshotBackend === 'localstorage') return 'localstorage';
      if (snapshotBackend === 'none') return 'ram';
      return 'indexeddb';
    },
    snapshot: function () { return snapshotWorkspace(); },
    lastPersistError: function () { return lastPersistError; },
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
        return kernelRoot.writeFile(path, text).then(function (result) {
          schedulePersist();
          return result;
        });
      });
    }
  };

  boot();
})();
