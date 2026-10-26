/* AirDesk bundled desktop applications. */
(function () {
  'use strict';

  var icons = {
    finder: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M8.2 8.6v3.1M15.8 8.6v3.1"/><path d="M7.7 15.4c1.2 1.3 2.7 1.9 4.3 1.9s3.1-.6 4.3-1.9"/><path d="M12 3.2c4.9 0 8.8 3.6 8.8 8.8S16.9 20.8 12 20.8 3.2 17.2 3.2 12 7.1 3.2 12 3.2Z"/><path d="M12 3.2v1.4"/></svg>',
    terminal: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="m6.5 8 3.7 3.6-3.7 3.7"/><path d="M12.5 16.2h5"/></svg>',
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

  var commands = {
    help: [
      'AirDesk shell commands',
      '  help          show this list',
      '  ls            list the workspace',
      '  pwd           print working directory',
      '  whoami        current Wanix user',
      '  uname -a      runtime information',
      '  date          current date and time',
      '  open <app>    open finder, notes, settings, welcome',
      '  neofetch      system summary',
      '  clear         clear the terminal'
    ],
    ls: ['Applications   Documents   Projects   README.md   welcome.txt   wanix.sock'],
    pwd: ['/Users/remote/Workspace'],
    whoami: ['remote'],
    uname: ['Wanix 0.4 (wasm) arm64 virtual · AirDesk bridge v1'],
    date: [new Date().toString()],
    neofetch: [
      '        .:\'         remote@wanix',
      '     .:ooo:\'       ------------------',
      '   .:ooooooo:\'     OS: Wanix 0.4 (wasm)',
      '  :ooooooooooo:    Host: AirDesk on iPhone',
      '  :ooooooooooo:    Kernel: coreutils-wasm',
      '   \':ooooooo:\'     Shell: ash 1.36',
      '     \':ooo:\'       Runtime: local bundle',
      '        \':\'        Bridge: AirDesk input v1'
    ]
  };

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
          return '<button class="side-item' + (index === 1 ? ' selected' : '') + '" data-filter="' + item + '">' +
            '<span class="side-glyph">' + (item === 'AirDesk' ? icons.welcome : item === 'Trash' ? icons.trash : icons.folder) + '</span>' +
            '<span>' + item + '</span>' +
            (item === 'Trash' ? '<span class="side-count">2</span>' : '') +
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
              '<div class="finder-location"><span class="loc-icon">' + icons.folder + '</span><span class="loc-title">Workspace</span></div>' +
              '<div class="finder-tools"><button class="icon-button" aria-label="Toggle sidebar">' + icons.sidebar + '</button><span class="finder-tool-label">' + icons.search + ' Search</span></div>' +
            '</header>' +
            '<div class="finder-grid" data-grid>' +
              fileTile('folder', 'Projects', 'Folder', null) +
              fileTile('folder', 'Documents', 'Folder', null) +
              fileTile('code', 'wanix-bridge.js', 'JavaScript · 14 KB', 'notes') +
              fileTile('doc', 'README.md', 'Markdown · 3 KB', 'notes') +
              fileTile('doc', 'welcome.txt', 'Text · 1 KB', 'notes') +
              fileTile('app', 'Wanix Terminal', 'Application', 'terminal') +
            '</div>' +
            '<footer class="finder-status"><span data-status>6 items</span><span>Wanix virtual volume · 48.2 GB available</span></footer>' +
          '</section>' +
        '</div>';
      },
      mount: function (root, api) {
        var grid = root.querySelector('[data-grid]');
        var status = root.querySelector('[data-status]');
        var title = root.querySelector('.loc-title');
        root.querySelectorAll('.side-item').forEach(function (button) {
          button.addEventListener('click', function () {
            root.querySelectorAll('.side-item').forEach(function (item) { item.classList.remove('selected'); });
            button.classList.add('selected');
            var filter = button.getAttribute('data-filter');
            title.textContent = filter;
            if (filter === 'Trash') {
              grid.innerHTML = '<div class="empty-state"><span class="empty-glyph">' + icons.trash + '</span><strong>Trash is empty</strong><span>Items you delete from the workspace appear here.</span></div>';
              status.textContent = '0 items';
            } else if (filter === 'Applications') {
              grid.innerHTML = iconTile('terminal', 'Terminal') + iconTile('notes', 'Notes') + iconTile('settings', 'Settings') + iconTile('welcome', 'AirDesk');
              status.textContent = '4 applications';
            } else {
              grid.innerHTML = '<button class="file-tile" data-file="Projects"><span class="file-art file-folder">' + icons.folder + '</span><span class="file-name">Projects</span><span class="file-meta">Folder</span></button>' +
                '<button class="file-tile" data-file="Documents"><span class="file-art file-folder">' + icons.folder + '</span><span class="file-name">Documents</span><span class="file-meta">Folder</span></button>' +
                '<button class="file-tile" data-open-app="notes"><span class="file-art file-doc">' + icons.document + '</span><span class="file-name">README.md</span><span class="file-meta">Markdown · 3 KB</span></button>' +
                '<button class="file-tile" data-open-app="notes"><span class="file-art file-doc">' + icons.document + '</span><span class="file-name">welcome.txt</span><span class="file-meta">Text · 1 KB</span></button>';
              status.textContent = '4 items';
            }
            api.notify('Finder · ' + filter);
          });
        });
        function chooseTile(tile, openNow) {
          if (!tile) return;
          grid.querySelectorAll('.file-tile').forEach(function (item) { item.classList.remove('selected'); });
          tile.classList.add('selected');
          if (openNow) {
            var open = tile.getAttribute('data-open-app');
            if (open) api.openApp(open);
            else api.notify(tile.getAttribute('data-file') + ' · virtual folder');
          }
        }
        grid.addEventListener('click', function (event) {
          var tile = event.target.closest('.file-tile');
          if (!tile) return;
          chooseTile(tile, event.detail >= 2);
        });
        grid.addEventListener('dblclick', function (event) {
          chooseTile(event.target.closest('.file-tile'), true);
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
        return '<div class="terminal">' +
          '<div class="term-scroll" data-term-scroll>' +
            '<pre class="term-output" data-term-output>' +
'AirDesk shell · Wanix 0.4\n' +
'Type "help" for available commands.\n\n' +
'<span class="term-dim">remote@wanix</span> <span class="term-path">~</span> <span class="term-accent">%</span> ' +
            '</pre>' +
            '<div class="term-line"><span class="term-prompt"><span class="term-dim">remote@wanix</span> <span class="term-path">~</span> <span class="term-accent">%</span></span>' +
            '<input class="term-input" data-term-input spellcheck="false" autocomplete="off" autocapitalize="off" aria-label="Terminal input"></div>' +
          '</div>' +
        '</div>';
      },
      mount: function (root, api) {
        var input = root.querySelector('[data-term-input]');
        var output = root.querySelector('[data-term-output]');
        var scroll = root.querySelector('[data-term-scroll]');
        var history = [];
        var index = 0;

        function scrollDown() { scroll.scrollTop = scroll.scrollHeight; }
        function write(html) {
          output.insertAdjacentHTML('beforeend', html + '\n');
          scrollDown();
        }
        function submit() {
          var raw = input.value;
          var line = raw.trim();
          input.value = '';
          if (!line) { write('<span class="term-dim">remote@wanix</span> <span class="term-path">~</span> <span class="term-accent">%</span> '); return; }
          history.push(line);
          index = history.length;
          write('<span class="term-echo">&gt; ' + escapeHTML(raw) + '</span>');
          var parts = line.split(/\s+/);
          var command = parts[0].toLowerCase();
          var response = commands[command];
          if (command === 'open' && parts[1]) {
            api.openApp(parts[1].toLowerCase());
            write('<span class="term-dim">Opening ' + escapeHTML(parts[1]) + '…</span>');
          } else if (command === 'clear') {
            output.innerHTML = '';
          } else if (response) {
            if (command === 'uname' && parts[1] !== '-a') {
              write('Wanix');
            } else {
              write('<pre class="term-block">' + response.map(escapeHTML).join('\n') + '</pre>');
            }
          } else if (command === 'echo') {
            write(escapeHTML(parts.slice(1).join(' ')));
          } else if (command === 'cd') {
            write('<span class="term-dim">Directories are virtual in this demo workspace.</span>');
          } else {
            write('<span class="term-error">ash: ' + escapeHTML(command) + ': command not found</span>');
          }
          write('<span class="term-dim">remote@wanix</span> <span class="term-path">~</span> <span class="term-accent">%</span> ');
          scrollDown();
        }

        input.addEventListener('keydown', function (event) {
          if (event.key === 'Enter') {
            event.preventDefault();
            submit();
          } else if (event.key === 'ArrowUp') {
            event.preventDefault();
            if (history.length) { index = Math.max(0, index - 1); input.value = history[index]; }
          } else if (event.key === 'ArrowDown') {
            event.preventDefault();
            if (history.length) { index = Math.min(history.length, index + 1); input.value = history[index] || ''; }
          }
        });
        root.addEventListener('click', function (event) {
          if (!event.target.closest('input,textarea,button')) input.focus();
        });
        setTimeout(function () { input.focus(); }, 260);
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
            '<button class="note-row selected" data-note="welcome"><strong>Welcome to AirDesk</strong><span>Your phone is the remote. Your screen is the desk.</span><small>Today</small></button>' +
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
      mount: function (root, api) {
        var content = {
          welcome: 'AirDesk turns your iPhone into a precise remote for a Wanix desktop.\n\nThis desktop is the same shell used on the external display and the Cast receiver. Pointer, scroll, keyboard, and text input all arrive through one normalized protocol.\n\nTry it:\n  · Swipe the touchpad to move the Air Cursor.\n  · Tap to click, double-tap to open a window.\n  · Long press and move to drag a title bar.\n  · Two-finger drag to scroll.\n  · Two-finger tap to right-click.\n  · Open the keyboard bar to type here.\n\nNothing on this desktop is a screenshot. Every window is live.',
          shortcuts: 'Air Cursor gestures\n\nOne finger move     Move pointer\nTap                 Click\nDouble tap          Double click\nLong press + move   Drag\nTwo-finger move     Scroll\nTwo-finger tap      Right click\n\nKeyboard bar\n\nEsc, Tab, Return, Backspace, arrows, and modifier keys map to native events. The keyboard field inserts text into the focused field.\n\nHardware keyboard\n\nWhen a hardware keyboard is connected, its text is forwarded over the same input channel.',
          wanix: 'Wanix is a WebAssembly-native workspace. The kernel and userland run inside the browser sandbox, so the desktop state lives with the page.\n\nAirDesk ships a bundled shell for offline use and a live Wanix Kernel runtime for experiments. The runtime announces readiness only after its bridge is live; AirDesk never treats a page load as success.\n\nInput is normalized to 0…1 coordinates, so the same events work on a phone preview, a TV, or a Cast receiver at any resolution.'
        };
        var title = root.querySelector('[data-note-title]');
        var body = root.querySelector('[data-note-body]');
        var saved = root.querySelector('[data-saved]');
        var date = root.querySelector('[data-note-date]');
        var active = 'welcome';
        var storageKey = 'airdesk.notes.v1';

        function load(key) {
          active = key;
          try {
            var stored = JSON.parse(localStorage.getItem(storageKey) || '{}');
            if (stored[key]) {
              title.value = stored[key].title;
              body.value = stored[key].body;
            } else {
              title.value = key === 'welcome' ? 'Welcome to AirDesk' : key === 'shortcuts' ? 'Remote shortcuts' : 'About Wanix';
              body.value = content[key] || '';
            }
          } catch (error) {
            title.value = key === 'welcome' ? 'Welcome to AirDesk' : 'Note';
            body.value = content[key] || '';
          }
          date.textContent = key === 'welcome' ? 'Today at 9:41 PM' : 'Yesterday';
          root.querySelectorAll('.note-row').forEach(function (row) {
            row.classList.toggle('selected', row.getAttribute('data-note') === key);
          });
        }

        function save() {
          saved.textContent = 'Saving…';
          try {
            var stored = JSON.parse(localStorage.getItem(storageKey) || '{}');
            stored[active] = { title: title.value, body: body.value };
            localStorage.setItem(storageKey, JSON.stringify(stored));
            setTimeout(function () { saved.textContent = 'Saved'; }, 320);
          } catch (error) {
            saved.textContent = 'Local only';
          }
        }

        root.querySelectorAll('.note-row').forEach(function (row) {
          row.addEventListener('click', function () { load(row.getAttribute('data-note')); });
        });
        root.querySelector('.notes-head .icon-button').addEventListener('click', function () {
          active = 'new-' + Date.now();
          title.value = 'New note';
          body.value = '';
          date.textContent = 'Just now';
          saved.textContent = 'Draft';
          root.querySelectorAll('.note-row').forEach(function (row) { row.classList.remove('selected'); });
          title.focus();
          title.select();
        });
        title.addEventListener('input', save);
        body.addEventListener('input', save);
        load('welcome');
        setTimeout(function () { body.focus(); }, 300);
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
            '<button class="welcome-card" data-open-app="notes"><span class="card-icon">' + appIcon('notes', 'tiny') + '</span><strong>Notes</strong><span>Type from your iPhone keyboard.</span><span class="card-link">Open Notes ' + icons.chevron + '</span></button>' +
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
