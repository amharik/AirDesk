/* AirDesk bundled desktop applications. */
(function () {
  'use strict';

  var icons = {
    finder: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M8.2 8.6v3.1M15.8 8.6v3.1"/><path d="M7.7 15.4c1.2 1.3 2.7 1.9 4.3 1.9s3.1-.6 4.3-1.9"/><path d="M12 3.2c4.9 0 8.8 3.6 8.8 8.8S16.9 20.8 12 20.8 3.2 17.2 3.2 12 7.1 3.2 12 3.2Z"/><path d="M12 3.2v1.4"/></svg>',
    terminal: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="m6.5 8 3.7 3.6-3.7 3.7"/><path d="M12.5 16.2h5"/></svg>',
    workbench: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><rect x="3.4" y="4.2" width="17.2" height="15.6" rx="2.2"/><path d="M3.4 9h17.2M9 9v10.8M9 14.2h11.6"/></svg>',
    notes: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M6 4.5h12a1.5 1.5 0 0 1 1.5 1.5v12A1.5 1.5 0 0 1 18 19.5H6A1.5 1.5 0 0 1 4.5 18V6A1.5 1.5 0 0 1 6 4.5Z"/><path d="M8 9h8M8 12.5h8M8 16h5"/></svg>',
    settings: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16M4 17h16"/><circle cx="9" cy="7" r="2.2"/><circle cx="15" cy="17" r="2.2"/></svg>',
    welcome: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3.5 14.1 9l5.9.4-4.5 3.8 1.4 5.7-4.9-3.1L7.1 19l1.4-5.7L4 9.4 9.9 9 12 3.5Z"/></svg>',
    trash: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M4.8 7h14.4M9.3 7V4.8h5.4V7M6.7 7l.8 12.2h9l.8-12.2"/><path d="M10 10.5v5.4M14 10.5v5.4"/></svg>',
    folder: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"><path d="M3.2 7.4A1.6 1.6 0 0 1 4.8 5.8h4l1.7 2h8.7a1.6 1.6 0 0 1 1.6 1.6v8.2a1.6 1.6 0 0 1-1.6 1.6H4.8a1.6 1.6 0 0 1-1.6-1.6V7.4Z"/></svg>',
    document: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"><path d="M6 3.8h8l4 4v12.4H6V3.8Z"/><path d="M14 3.8v4h4M9 12h6M9 15.2h6"/></svg>',
    code: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="m9 7-4 5 4 5M15 7l4 5-4 5"/></svg>',
    disk: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"><path d="M4.5 4.8h12l3 3V19h-15V4.8Z"/><path d="M8 4.8v5h7v-5M8 19v-5h8v5"/></svg>',
    search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="6.2"/><path d="m15.6 15.6 4 4"/></svg>',
    wifi: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M4 9.5a12 12 0 0 1 16 0M7 12.8a7.6 7.6 0 0 1 10 0M10 16a3.4 3.4 0 0 1 4 0"/><circle cx="12" cy="19" r=".9" fill="currentColor" stroke="none"/></svg>',
    battery: '<svg viewBox="0 0 28 24" fill="none"><rect x="2" y="8" width="21" height="10" rx="2.4" stroke="currentColor" stroke-width="1.5"/><rect x="4.2" y="10.2" width="15.5" height="5.6" rx="1" fill="currentColor"/><path d="M24.5 11.2v3.6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
    chevron: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 6 6 6-6 6"/></svg>',
    plus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>',
    sidebar: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"><rect x="3.5" y="4.5" width="17" height="15" rx="2"/><path d="M9 4.5v15"/></svg>',
    back: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="m14 6-6 6 6 6"/></svg>',
    forward: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="m10 6 6 6-6 6"/></svg>',
    apple: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M16.4 12.6c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.1-2.7.8-3.4.8-.7 0-1.8-.8-3-.8-1.5 0-3 .9-3.8 2.3-1.6 2.8-.4 7 1.2 9.3.8 1.1 1.7 2.3 2.9 2.2 1.2 0 1.6-.7 3.1-.7 1.4 0 1.8.7 3 .7 1.2 0 2.1-1.1 2.9-2.3.9-1.3 1.3-2.6 1.3-2.7-.1 0-2.8-1.1-2.8-3.5ZM14.2 5.8c.6-.8 1.1-1.9 1-3-.9 0-2 .6-2.7 1.4-.6.7-1.1 1.8-1 2.9 1 .1 2.1-.5 2.7-1.3Z"/></svg>'
  };

  function appIcon(id, extra) {
    return '<span class="app-icon app-icon-' + id + ' ' + (extra || '') + '" aria-hidden="true">' +
      '<span class="app-icon-inner">' + (icons[id] || icons.folder) + '</span></span>';
  }

  function fileTile(kind, name, meta, open) {
    var glyph = kind === 'folder' ? icons.folder : kind === 'app' ? icons.welcome : kind === 'code' ? icons.code : icons.document;
    return '<button class="file-tile" data-file="' + name + '"' + (open ? ' data-open-app="' + open + '"' : '') + '>' +
      '<span class="file-art file-' + kind + '">' + glyph + '</span>' +
      '<span class="file-name">' + name + '</span>' +
      (meta ? '<span class="file-meta">' + meta + '</span>' : '') +
      '</button>';
  }

  function iconTile(id, label) {
    return '<button class="file-tile" data-open-app="' + id + '">' +
      '<span class="file-art file-app">' + appIcon(id) + '</span>' +
      '<span class="file-name">' + label + '</span>' +
      '<span class="file-meta">Application</span></button>';
  }

  window.AirDeskApps = {
    finder: {
      name: 'Finder',
      menu: 'Finder',
      width: 760,
      height: 476,
      minWidth: 520,
      minHeight: 320,
      render: function () {
        var favorites = ['AirDesk', 'Workspace', 'Documents', 'Applications', 'Trash'];
        var side = favorites.map(function (item, index) {
          return '<button class="side-item' + (index === 0 ? ' selected' : '') + '" data-filter="' + item + '">' +
            '<span class="side-glyph">' + (item === 'AirDesk' ? icons.welcome : item === 'Trash' ? icons.trash : icons.folder) + '</span>' +
            '<span>' + item + '</span>' +
            '</button>';
        }).join('');

        return '<div class="finder">' +
          '<aside class="finder-side">' +
            '<div class="side-section-label">Favorites</div>' + side +
            '<div class="side-section-label">Locations</div>' +
            '<button class="side-item" data-filter="iCloud"><span class="side-glyph">' + icons.disk + '</span><span>AirDesk Disk</span></button>' +
            '<button class="side-item" data-filter="Network"><span class="side-glyph">' + icons.wifi + '</span><span>Network</span></button>' +
          '</aside>' +
          '<section class="finder-main">' +
            '<header class="finder-toolbar">' +
              '<div class="finder-nav">' +
                '<button class="icon-button" aria-label="Back">' + icons.back + '</button>' +
                '<button class="icon-button is-disabled" aria-label="Forward">' + icons.forward + '</button>' +
              '</div>' +
              '<div class="finder-location"><span class="loc-icon">' + icons.folder + '</span><span class="loc-title">AirDesk</span></div>' +
              '<div class="finder-tools"><button class="icon-button" aria-label="Toggle sidebar">' + icons.sidebar + '</button><span class="finder-tool-label">' + icons.search + ' Search</span></div>' +
            '</header>' +
            '<div class="finder-grid" data-grid>' +
              '<div class="empty-state"><span class="empty-glyph">' + icons.folder + '</span><strong>Connecting to Wanix</strong><span>Reading the live workspace.</span></div>' +
            '</div>' +
            '<footer class="finder-status"><span data-status>Connecting…</span><span>Live Wanix namespace</span></footer>' +
          '</section>' +
        '</div>';
      },
      mount: function (root, api) {
        var grid = root.querySelector('[data-grid]');
        var status = root.querySelector('[data-status]');
        var title = root.querySelector('.loc-title');
        var currentPath = '.';
        var loadToken = 0;
        var locations = {
          AirDesk: '.',
          Workspace: 'opfs',
          Documents: 'opfs/Documents',
          iCloud: 'opfs'
        };

        function basename(path) {
          var parts = String(path || '').split('/');
          return parts[parts.length - 1] || 'AirDesk';
        }

        function joinPath(path, name) {
          return path === '.' || !path ? name : path + '/' + name;
        }

        function showEmpty(heading, detail) {
          grid.innerHTML = '<div class="empty-state"><span class="empty-glyph">' + icons.folder + '</span><strong>' + escapeHTML(heading) + '</strong><span>' + escapeHTML(detail) + '</span></div>';
        }

        function liveTile(entry, path) {
          var isDir = entry.charAt(entry.length - 1) === '/';
          var name = isDir ? entry.slice(0, -1) : entry;
          var child = joinPath(path, name);
          var kind = isDir ? 'folder' : /\.(js|json|html|css|go|sh|wasm)$/i.test(name) ? 'code' : 'doc';
          var glyph = isDir ? icons.folder : kind === 'code' ? icons.code : icons.document;
          var meta = isDir ? 'Folder' : kind === 'code' ? 'Wanix file' : 'Text file';
          return '<button class="file-tile" data-path="' + escapeHTML(child) + '" data-kind="' + (isDir ? 'folder' : 'file') + '">' +
            '<span class="file-art file-' + kind + '">' + glyph + '</span>' +
            '<span class="file-name">' + escapeHTML(name) + '</span>' +
            '<span class="file-meta">' + meta + '</span></button>';
        }

        function loadPath(path, label) {
          currentPath = path;
          title.textContent = label || basename(path);
          status.textContent = 'Reading ' + (path === '.' ? '/' : path) + '…';
          showEmpty('Reading Wanix workspace', path === '.' ? '/' : path);
          var token = ++loadToken;
          window.AirDeskKernel.list(path).then(function (entries) {
            if (token !== loadToken) return;
            entries = entries || [];
            if (!entries.length) {
              showEmpty('This folder is empty', 'Create files from the live Terminal.');
              status.textContent = '0 items · ' + (path === '.' ? '/' : path);
              return;
            }
            grid.innerHTML = entries.map(function (entry) { return liveTile(entry, path); }).join('');
            status.textContent = entries.length + ' items · ' + (path === '.' ? '/' : path);
          }).catch(function (error) {
            if (token !== loadToken) return;
            showEmpty('Could not read ' + (path === '.' ? '/' : path), String(error && error.message || error));
            status.textContent = 'Unavailable';
          });
        }

        function selectSide(button) {
          root.querySelectorAll('.side-item').forEach(function (item) { item.classList.remove('selected'); });
          button.classList.add('selected');
        }

        function chooseTile(tile, openNow) {
          if (!tile) return;
          grid.querySelectorAll('.file-tile').forEach(function (item) { item.classList.remove('selected'); });
          tile.classList.add('selected');
          if (!openNow) return;
          var path = tile.getAttribute('data-path');
          if (tile.getAttribute('data-kind') === 'folder') {
            loadPath(path, basename(path));
          } else {
            api.openApp('notes', { path: path });
          }
        }

        root.querySelectorAll('.side-item').forEach(function (button) {
          button.addEventListener('click', function () {
            selectSide(button);
            var filter = button.getAttribute('data-filter');
            if (filter === 'Trash') {
              title.textContent = 'Trash';
              grid.innerHTML = '<div class="empty-state"><span class="empty-glyph">' + icons.trash + '</span><strong>Trash is empty</strong><span>Items you delete from the workspace appear here.</span></div>';
              status.textContent = '0 items';
            } else if (filter === 'Applications') {
              title.textContent = 'Applications';
              grid.innerHTML = iconTile('terminal', 'Terminal') + iconTile('workbench', 'Workbench') + iconTile('notes', 'Notes') + iconTile('settings', 'Settings') + iconTile('welcome', 'AirDesk');
              status.textContent = '5 applications';
            } else if (filter === 'Network') {
              title.textContent = 'Network';
              showEmpty('Network is unavailable', 'The live Wanix namespace runs locally.');
              status.textContent = 'Offline';
            } else {
              loadPath(locations[filter] || '.', filter === 'iCloud' ? 'AirDesk Disk' : filter);
            }
            api.notify('Finder · ' + filter);
          });
        });

        grid.addEventListener('click', function (event) {
          var tile = event.target.closest('.file-tile');
          if (!tile) return;
          chooseTile(tile, event.detail >= 2);
        });
        grid.addEventListener('dblclick', function (event) {
          chooseTile(event.target.closest('.file-tile'), true);
        });

        window.AirDeskKernel.ready.then(function () {
          loadPath('.', 'AirDesk');
        }).catch(function (error) {
          showEmpty('Wanix kernel unavailable', String(error && error.message || error));
          status.textContent = 'Offline';
        });
      }
    },

    terminal: {
      name: 'Terminal',
      menu: 'Terminal',
      width: 680,
      height: 420,
      minWidth: 420,
      minHeight: 260,
      render: function () {
        return '<div class="terminal live-terminal">' +
          '<div class="term-status" data-term-status>Connecting to the live Wanix shell…</div>' +
          '<div class="term-host" data-term-host></div>' +
        '</div>';
      },
      mount: function (root, api) {
        var host = root.querySelector('[data-term-host]');
        var status = root.querySelector('[data-term-status]');

        function showStatus(text) {
          status.hidden = false;
          status.textContent = text;
        }

        function waitForTaskTerm() {
          return new Promise(function (resolve, reject) {
            var task = document.querySelector('#wanix wanix-task');
            var attempts = 0;
            var timer = setInterval(function () {
              if (task && task.term) {
                clearInterval(timer);
                setTimeout(resolve, 80);
              } else if (++attempts > 200) {
                clearInterval(timer);
                reject(new Error('The shell task did not allocate a terminal.'));
              }
            }, 50);
          });
        }

        function mountTerminal(attempt) {
          host.innerHTML = '';
          var term = document.createElement('wanix-term');
          term.setAttribute('for', 'wanix');
          term.setAttribute('path', window.AirDeskKernel.terminalPath);
          term.setAttribute('raw', '');
          term.setAttribute('cursor-blink', 'true');
          term.setAttribute('scrollback', '5000');
          term.className = 'wanix-term';
          host.appendChild(term);
          setTimeout(function () {
            try { term.fit(); term.focus(); } catch (error) { /* terminal may still be connecting */ }
          }, 120);

          var settled = false;
          var watchdogTimer = 0;
          var connectTimer = 0;

          function settle(error) {
            if (settled) return;
            settled = true;
            clearTimeout(connectTimer);
            clearTimeout(watchdogTimer);
            if (!error) {
              status.hidden = true;
              api.notify('Terminal attached to live Wanix shell');
              return;
            }
            if (attempt < 3) {
              showStatus('Reconnecting to the live Wanix shell…');
              setTimeout(function () { mountTerminal(attempt + 1); }, 250);
            } else {
              showStatus('Could not start the Wanix shell: ' + String(error && error.message || error));
            }
          }

          connectTimer = setTimeout(function () {
            var connected = term && typeof term.connect === 'function' ? term.connect() : Promise.resolve();
            connected.then(function () {
              return window.AirDeskKernel.startShell();
            }).then(function () {
              settle(null);
            }).catch(function (error) {
              settle(error);
            });
          }, 300);

          watchdogTimer = setTimeout(function () {
            settle(new Error('The Wanix shell did not attach in time.'));
          }, 1800);
        }

        window.AirDeskKernel.ready.then(waitForTaskTerm).then(function () {
          mountTerminal(1);
        }).catch(function (error) {
          showStatus('Wanix shell unavailable: ' + String(error && error.message || error));
        });
      }
    },

    notes: {
      name: 'Notes',
      menu: 'Notes',
      width: 720,
      height: 440,
      minWidth: 460,
      minHeight: 280,
      render: function () {
        return '<div class="notes">' +
          '<aside class="notes-list">' +
            '<div class="notes-head"><span>Notes</span><button class="icon-button" aria-label="New note">' + icons.plus + '</button></div>' +
            '<button class="note-row selected" data-note="welcome"><strong>Welcome to AirDesk</strong><span>Your device is the remote. Your screen is the desk.</span><small>Today</small></button>' +
            '<button class="note-row" data-note="shortcuts"><strong>Remote shortcuts</strong><span>Touchpad, keyboard, and Dock gestures.</span><small>Yesterday</small></button>' +
            '<button class="note-row" data-note="wanix"><strong>About Wanix</strong><span>A WebAssembly workspace in the browser.</span><small>Yesterday</small></button>' +
          '</aside>' +
          '<section class="note-main">' +
            '<div class="note-meta"><span data-note-date>Today at 9:41 PM</span><span class="note-saved" data-saved>Saved</span></div>' +
            '<input class="note-title" data-note-title value="Welcome to AirDesk" aria-label="Note title">' +
            '<textarea class="note-body" data-note-body aria-label="Note body"></textarea>' +
          '</section>' +
        '</div>';
      },
      mount: function (root, api, options) {
        var content = {
          welcome: 'AirDesk turns your ' + ((window.AD && window.AD.device) || 'device') + ' into a precise remote for a Wanix desktop.\n\nThis desktop is the same shell used on the external display and the Cast receiver. Pointer, scroll, keyboard, and text input all arrive through one normalized protocol.\n\nTry it:\n  · Swipe the touchpad to move the Air Cursor.\n  · Tap to click, double-tap to open a window.\n  · Long press and move to drag a title bar.\n  · Two-finger drag to scroll.\n  · Two-finger tap to right-click.\n  · Open the keyboard bar to type here.\n\nNothing on this desktop is a screenshot. Every window is live.',
          shortcuts: 'Air Cursor gestures\n\nOne finger move     Move pointer\nTap                 Click\nDouble tap          Double click\nLong press + move   Drag\nTwo-finger move     Scroll\nTwo-finger tap      Right click\n\nKeyboard bar\n\nEsc, Tab, Return, Backspace, arrows, and modifier keys map to native events. The keyboard field inserts text into the focused field.\n\nHardware keyboard\n\nWhen a hardware keyboard is connected, its text is forwarded over the same input channel.',
          wanix: 'Wanix is a WebAssembly-native workspace. The kernel and userland run inside the browser sandbox, so the desktop state lives with the page.\n\nAirDesk ships a live Wanix kernel inside this desktop shell. Finder and Notes read and write the same namespace. The runtime announces readiness only after its bridge is live; AirDesk never treats a page load as success.\n\nInput is normalized to 0…1 coordinates, so the same events work on a device preview, a TV, or a Cast receiver at any resolution.'
        };
        var title = root.querySelector('[data-note-title]');
        var body = root.querySelector('[data-note-body]');
        var saved = root.querySelector('[data-saved]');
        var date = root.querySelector('[data-note-date]');
        var active = 'welcome';
        var storageKey = 'airdesk.notes.v1';
        var store = {};
        var filePath = null;
        var saveTimer = 0;
        options = options || {};

        try { store = JSON.parse(localStorage.getItem(storageKey) || '{}'); } catch (error) { store = {}; }

        function defaultTitle(key) {
          return key === 'welcome' ? 'Welcome to AirDesk' : key === 'shortcuts' ? 'Remote shortcuts' : key === 'wanix' ? 'About Wanix' : 'Note';
        }

        function basename(path) {
          var parts = String(path || '').split('/');
          return parts[parts.length - 1] || 'Note';
        }

        function persistLocal() {
          try { localStorage.setItem(storageKey, JSON.stringify(store)); } catch (error) { /* local file storage can be unavailable */ }
        }

        function selectRow(key) {
          root.querySelectorAll('.note-row').forEach(function (row) {
            row.classList.toggle('selected', !!key && row.getAttribute('data-note') === key);
          });
        }

        function load(key) {
          filePath = null;
          active = key;
          var stored = store[key];
          title.value = stored ? stored.title : defaultTitle(key);
          body.value = stored ? stored.body : (content[key] || '');
          date.textContent = key === 'welcome' ? 'Today at 9:41 PM' : stored ? 'Saved in Wanix' : 'Yesterday';
          saved.textContent = stored ? 'Saved' : 'Local';
          selectRow(key);
        }

        function loadFile(path) {
          filePath = path;
          active = 'file:' + path;
          title.value = basename(path);
          body.value = 'Loading from Wanix…';
          date.textContent = 'Wanix file';
          saved.textContent = 'Loading…';
          selectRow(null);
          window.AirDeskKernel.readText(path).then(function (text) {
            body.value = text;
            saved.textContent = 'Loaded';
          }).catch(function (error) {
            body.value = '';
            saved.textContent = 'Unavailable';
            api.notify('Could not open ' + basename(path) + ': ' + String(error && error.message || error));
          });
        }

        function persistFile() {
          if (!filePath) return;
          window.AirDeskKernel.writeText(filePath, body.value).then(function () {
            saved.textContent = 'Saved';
          }).catch(function () {
            saved.textContent = 'Not saved';
          });
        }

        function persistStore() {
          persistLocal();
          window.AirDeskKernel.writeText('opfs/notes.json', JSON.stringify(store)).then(function () {
            saved.textContent = 'Saved';
          }).catch(function () {
            saved.textContent = 'Local only';
          });
        }

        function save() {
          saved.textContent = 'Saving…';
          clearTimeout(saveTimer);
          if (filePath) {
            saveTimer = setTimeout(persistFile, 280);
            return;
          }
          store[active] = { title: title.value, body: body.value };
          persistLocal();
          saveTimer = setTimeout(persistStore, 280);
        }

        function hydrate() {
          window.AirDeskKernel.ready.then(function () {
            return window.AirDeskKernel.readText('opfs/notes.json');
          }).then(function (text) {
            if (!text) return;
            try {
              var remote = JSON.parse(text);
              Object.keys(remote).forEach(function (key) {
                if (!store[key]) store[key] = remote[key];
              });
            } catch (error) { /* ignore malformed workspace notes */ }
            if (!filePath) load(active);
          }).catch(function () { /* notes stay local until OPFS is available */ });
        }

        root.querySelectorAll('.note-row').forEach(function (row) {
          row.addEventListener('click', function () { load(row.getAttribute('data-note')); });
        });
        root.querySelector('.notes-head .icon-button').addEventListener('click', function () {
          filePath = null;
          active = 'new-' + Date.now();
          title.value = 'New note';
          body.value = '';
          date.textContent = 'Just now';
          saved.textContent = 'Draft';
          selectRow(null);
          title.focus();
          title.select();
        });
        root.addEventListener('airdesk-open-file', function (event) {
          if (event.detail) loadFile(event.detail);
        });
        title.addEventListener('input', save);
        body.addEventListener('input', save);

        if (options.path) {
          loadFile(options.path);
        } else {
          load('welcome');
          hydrate();
        }
        setTimeout(function () { body.focus(); }, 300);
      }
    },

    workbench: {
      name: 'Workbench',
      menu: 'Workbench',
      width: 780,
      height: 500,
      minWidth: 520,
      minHeight: 340,
      render: function () {
        return '<div class="workbench">' +
          '<header class="workbench-head">' +
            '<div><span class="workbench-kicker">LIVE WORKSPACE</span><h1>Workbench</h1><p>Runtime, files, and session health.</p></div>' +
            '<button class="workbench-refresh" data-workbench-refresh>Refresh</button>' +
          '</header>' +
          '<div class="workbench-grid">' +
            '<section class="workbench-card workbench-runtime">' +
              '<div class="workbench-card-head"><span>Runtime</span><span class="workbench-live"><span></span>LIVE</span></div>' +
              '<div class="workbench-metrics">' +
                '<div><span>Kernel</span><strong data-workbench-kernel>Wanix 0.4</strong></div>' +
                '<div><span>Persistence</span><strong data-workbench-persistence>Checking…</strong></div>' +
                '<div><span>Bridge</span><strong>Input v1</strong></div>' +
                '<div><span>Session</span><strong data-workbench-session>local</strong></div>' +
              '</div>' +
              '<div class="workbench-error" data-workbench-error hidden></div>' +
            '</section>' +
            '<section class="workbench-card workbench-actions-card">' +
              '<div class="workbench-card-head"><span>Quick actions</span></div>' +
              '<div class="workbench-actions">' +
                '<button class="workbench-action" data-workbench-open="terminal"><span class="workbench-action-icon">' + icons.terminal + '</span><strong>Terminal</strong><small>Run a command</small></button>' +
                '<button class="workbench-action" data-workbench-open="finder"><span class="workbench-action-icon">' + icons.folder + '</span><strong>Finder</strong><small>Browse workspace</small></button>' +
                '<button class="workbench-action" data-workbench-open="notes"><span class="workbench-action-icon">' + icons.notes + '</span><strong>Notes</strong><small>Write a note</small></button>' +
                '<button class="workbench-action" data-workbench-spotlight><span class="workbench-action-icon">' + icons.search + '</span><strong>Spotlight</strong><small>Find anything</small></button>' +
              '</div>' +
            '</section>' +
            '<section class="workbench-card workbench-files-card">' +
              '<div class="workbench-card-head"><span>Workspace</span><span data-workbench-count>—</span></div>' +
              '<div class="workbench-files" data-workbench-files><div class="workbench-empty">Reading opfs/…</div></div>' +
            '</section>' +
            '<section class="workbench-card workbench-session-card">' +
              '<div class="workbench-card-head"><span>Session</span></div>' +
              '<p class="workbench-copy">Finder, Notes, Terminal, and the Air Cursor share one live Wanix namespace. Workspace snapshots restore after a reload.</p>' +
              '<div class="workbench-foot"><span data-workbench-footprint>—</span><button data-workbench-open="finder">Open Finder</button></div>' +
            '</section>' +
          '</div>' +
        '</div>';
      },
      mount: function (root, api) {
        var kernel = window.AirDeskKernel;
        var labels = {
          opfs: 'OPFS',
          indexeddb: 'IndexedDB snapshot',
          localstorage: 'localStorage snapshot',
          ram: 'Memory only'
        };
        var error = root.querySelector('[data-workbench-error]');
        var count = root.querySelector('[data-workbench-count]');
        var files = root.querySelector('[data-workbench-files]');
        var footprint = root.querySelector('[data-workbench-footprint]');
        var session = new URLSearchParams(location.search).get('session') || 'local-preview';
        var refreshToken = 0;

        root.querySelector('[data-workbench-session]').textContent = session;
        root.querySelector('[data-workbench-persistence]').textContent =
          labels[kernel.persistence ? kernel.persistence() : 'opfs'] || 'Unknown';

        var persistError = kernel.lastPersistError ? kernel.lastPersistError() : null;
        if (persistError) {
          error.hidden = false;
          error.textContent = persistError;
        }

        function formatBytes(bytes) {
          if (!bytes) return '0 B';
          if (bytes < 1024) return bytes + ' B';
          if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
          return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
        }

        function renderEntries(totalCount, stats) {
          count.textContent = totalCount + (totalCount === 1 ? ' item' : ' items');
          var total = stats.reduce(function (sum, item) { return sum + (item.isDir ? 0 : item.size); }, 0);
          footprint.textContent = formatBytes(total) + ' in opfs';
          if (!stats.length) {
            files.innerHTML = '<div class="workbench-empty">The workspace is empty. Create files in Notes or the Terminal.</div>';
            return;
          }
          files.innerHTML = stats.map(function (item) {
            return '<button class="workbench-file" data-workbench-file="' + escapeHTML(item.path) + '" data-kind="' + (item.isDir ? 'folder' : 'file') + '">' +
              '<span class="workbench-file-icon">' + (item.isDir ? icons.folder : icons.document) + '</span>' +
              '<span class="workbench-file-name">' + escapeHTML(item.name) + '</span>' +
              '<span class="workbench-file-meta">' + (item.isDir ? 'Folder' : formatBytes(item.size)) + '</span>' +
            '</button>';
          }).join('');
        }

        function refresh() {
          var token = ++refreshToken;
          count.textContent = 'Reading…';
          footprint.textContent = '—';
          kernel.list('opfs').then(function (allEntries) {
            if (token !== refreshToken) return;
            var entries = (allEntries || []).slice(0, 8);
            var stats = entries.map(function (entry) {
              var isDir = entry.charAt(entry.length - 1) === '/';
              var name = isDir ? entry.slice(0, -1) : entry;
              var path = 'opfs/' + name;
              return kernel.stat(path).then(function (info) {
                return { name: name, path: path, isDir: isDir, size: info && info.Size || 0 };
              }).catch(function () {
                return { name: name, path: path, isDir: isDir, size: 0 };
              });
            });
            Promise.all(stats).then(function (items) {
              if (token !== refreshToken) return;
              renderEntries((allEntries || []).length, items);
            });
          }).catch(function (cause) {
            if (token !== refreshToken) return;
            count.textContent = 'Unavailable';
            files.innerHTML = '<div class="workbench-empty">' + escapeHTML(String(cause && cause.message || cause)) + '</div>';
          });
        }

        root.querySelector('[data-workbench-refresh]').addEventListener('click', refresh);
        root.querySelectorAll('[data-workbench-open]').forEach(function (button) {
          button.addEventListener('click', function () {
            api.openApp(button.getAttribute('data-workbench-open'));
          });
        });
        root.querySelector('[data-workbench-spotlight]').addEventListener('click', function () {
          if (api.openSpotlight) api.openSpotlight();
          else api.notify('Spotlight is available from the menu bar.');
        });
        files.addEventListener('click', function (event) {
          var file = event.target.closest('[data-workbench-file]');
          if (!file) return;
          if (file.getAttribute('data-kind') === 'folder') {
            api.openApp('finder');
          } else {
            api.openApp('notes', { path: file.getAttribute('data-workbench-file') });
          }
        });

        kernel.ready.then(refresh).catch(function (cause) {
          count.textContent = 'Offline';
          files.innerHTML = '<div class="workbench-empty">Wanix kernel unavailable: ' + escapeHTML(String(cause && cause.message || cause)) + '</div>';
        });
      }
    },

    settings: {
      name: 'Settings',
      menu: 'System Settings',
      width: 620,
      height: 450,
      minWidth: 460,
      minHeight: 320,
      render: function () {
        return '<div class="settings-app">' +
          '<aside class="settings-side">' +
            '<div class="settings-user"><span class="avatar">R</span><span><strong>Remote</strong><small>Wanix workspace</small></span></div>' +
            '<button class="settings-tab selected">Appearance</button>' +
            '<button class="settings-tab">Desktop &amp; Dock</button>' +
            '<button class="settings-tab">Keyboard</button>' +
            '<button class="settings-tab">Privacy</button>' +
          '</aside>' +
          '<section class="settings-main">' +
            '<h2>Appearance</h2>' +
            '<div class="setting-card">' +
              '<div class="setting-row"><div><strong>Theme</strong><span>Applies to the shell and running apps.</span></div>' +
                '<div class="segmented" data-theme-group><button data-theme="dark">Dark</button><button data-theme="light">Light</button></div></div>' +
              '<div class="setting-row"><div><strong>Wallpaper</strong><span>Choose a desktop backdrop.</span></div>' +
                '<div class="wallpaper-options" data-wallpaper-group>' +
                  '<button data-wallpaper="aurora" class="wall-option aurora" aria-label="Aurora"></button>' +
                  '<button data-wallpaper="dune" class="wall-option dune" aria-label="Dune"></button>' +
                  '<button data-wallpaper="graphite" class="wall-option graphite" aria-label="Graphite"></button>' +
                '</div></div>' +
              '<div class="setting-row"><div><strong>Reduce transparency</strong><span>Use solid menu bar and Dock surfaces.</span></div>' +
                '<button class="switch" data-toggle="transparency" aria-pressed="false"><span></span></button></div>' +
              '<div class="setting-row"><div><strong>Window animations</strong><span>Gentle scale and fade when opening apps.</span></div>' +
                '<button class="switch is-on" data-toggle="animation" aria-pressed="true"><span></span></button></div>' +
            '</div>' +
            '<div class="settings-note">' + appIcon('welcome', 'tiny') + '<div><strong>AirDesk 1.0</strong><span>Bundled Wanix desktop shell · bridge v1<br>Changes stay on this runtime.</span></div></div>' +
          '</section>' +
        '</div>';
      },
      mount: function (root, api) {
        var themeButtons = root.querySelectorAll('[data-theme]');
        var wallpaperButtons = root.querySelectorAll('[data-wallpaper]');
        function sync() {
          themeButtons.forEach(function (button) {
            button.classList.toggle('selected', button.getAttribute('data-theme') === api.getAppearance());
          });
          var wallpaper = document.body.getAttribute('data-wallpaper') || 'aurora';
          wallpaperButtons.forEach(function (button) {
            button.classList.toggle('selected', button.getAttribute('data-wallpaper') === wallpaper);
          });
          root.querySelectorAll('.switch').forEach(function (button) {
            var key = button.getAttribute('data-toggle');
            button.classList.toggle('is-on', document.body.classList.contains('reduce-transparency') ? key === 'transparency' : key === 'animation');
          });
        }
        themeButtons.forEach(function (button) {
          button.addEventListener('click', function () {
            api.setAppearance(button.getAttribute('data-theme'));
            sync();
          });
        });
        wallpaperButtons.forEach(function (button) {
          button.addEventListener('click', function () {
            api.setWallpaper(button.getAttribute('data-wallpaper'));
            sync();
          });
        });
        root.querySelectorAll('.switch').forEach(function (button) {
          button.addEventListener('click', function () {
            var key = button.getAttribute('data-toggle');
            if (key === 'transparency') {
              var on = !document.body.classList.contains('reduce-transparency');
              document.body.classList.toggle('reduce-transparency', on);
              api.notify(on ? 'Transparency reduced' : 'Transparency restored');
            } else {
              var animate = !document.body.classList.contains('no-motion');
              document.body.classList.toggle('no-motion', animate);
              api.notify(animate ? 'Window animations off' : 'Window animations on');
            }
            sync();
          });
        });
        root.querySelectorAll('.settings-tab').forEach(function (tab) {
          tab.addEventListener('click', function () {
            root.querySelectorAll('.settings-tab').forEach(function (item) { item.classList.remove('selected'); });
            tab.classList.add('selected');
            if (!tab.textContent.includes('Appearance')) api.notify('This panel is part of the demo shell');
          });
        });
        sync();
      }
    },

    welcome: {
      name: 'AirDesk',
      menu: 'AirDesk',
      width: 620,
      height: 430,
      minWidth: 440,
      minHeight: 330,
      render: function () {
        return '<div class="welcome-app">' +
          '<div class="welcome-glow"></div>' +
          '<div class="welcome-mark">' + appIcon('welcome', 'hero') + '</div>' +
          '<h1>AirDesk</h1>' +
          '<p class="welcome-sub">A Wanix desktop, controlled from the couch.</p>' +
          '<div class="welcome-pills"><span class="pill live"><span class="pulse"></span>Desktop ready</span><span class="pill">Input bridge v1</span><span class="pill">Wanix 0.4</span></div>' +
          '<div class="welcome-cards">' +
            '<button class="welcome-card" data-open-app="terminal"><span class="card-icon">' + appIcon('terminal', 'tiny') + '</span><strong>Terminal</strong><span>Run a command in the live shell.</span><span class="card-link">Open Terminal ' + icons.chevron + '</span></button>' +
            '<button class="welcome-card" data-open-app="notes"><span class="card-icon">' + appIcon('notes', 'tiny') + '</span><strong>Notes</strong><span>Type from your ' + ((window.AD && window.AD.device) || 'device') + ' keyboard.</span><span class="card-link">Open Notes ' + icons.chevron + '</span></button>' +
            '<button class="welcome-card" data-open-app="finder"><span class="card-icon">' + appIcon('finder', 'tiny') + '</span><strong>Finder</strong><span>Browse the bundled workspace.</span><span class="card-link">Open Finder ' + icons.chevron + '</span></button>' +
          '</div>' +
          '<div class="welcome-foot"><span>Swipe to move · Tap to click · Long press to drag</span><button data-open-app="settings">Settings</button></div>' +
        '</div>';
      },
      mount: function (root, api) {
        root.querySelectorAll('[data-open-app]').forEach(function (button) {
          button.addEventListener('click', function () { api.openApp(button.getAttribute('data-open-app')); });
        });
      }
    },

    trash: {
      name: 'Trash',
      menu: 'Finder',
      width: 540,
      height: 360,
      render: function () {
        return '<div class="empty-state large"><span class="empty-glyph">' + icons.trash + '</span><strong>Trash is empty</strong><span>Deleted files from the Wanix workspace would appear here.</span></div>';
      }
    }
  };

  window.AirDeskIcons = icons;
  window.AirDeskAppIcon = appIcon;

  function escapeHTML(value) {
    return String(value).replace(/[&<>"']/g, function (character) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character];
    });
  }
})();
