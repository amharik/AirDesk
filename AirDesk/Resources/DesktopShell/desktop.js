/* AirDesk window manager and input surface. */
(function () {
  'use strict';

  var apps = window.AirDeskApps || {};
  var icons = window.AirDeskIcons || {};
  var appIcon = window.AirDeskAppIcon || function () { return ''; };
  var AD = window.AD;
  if (!AD) return;

  var $ = function (selector, root) { return (root || document).querySelector(selector); };
  var $$ = function (selector, root) { return Array.prototype.slice.call((root || document).querySelectorAll(selector)); };
  var clamp = function (value, min, max) { return Math.min(Math.max(value, min), max); };

  var state = {
    windows: [],
    focused: null,
    z: 100,
    pointer: { x: window.innerWidth / 2, y: window.innerHeight / 2 },
    pointerVisible: false,
    drag: null,
    downTarget: null,
    hoverElement: null,
    typingHintShown: false
  };

  var appearance = 'dark';
  var wallpaper = 'aurora';
  var toastTimer = 0;
  var clockTimer = 0;
  var menuButton = null;
  var bootHidden = false;

  var desktop = $('#desktop');
  var windowLayer = $('#window-layer');
  var cursor = $('#cursor');
  var clock = $('#clock');
  var activeAppLabel = $('#active-app');
  var dock = $('#dock');
  var spotlight = $('#spotlight');
  var spotlightInput = $('#spotlight-input');
  var spotlightResults = $('#spotlight-results');
  var contextMenu = $('#context-menu');
  var toast = $('#toast');
  var boot = $('#boot');

  function loadPreference(key, fallback) {
    try {
      var value = localStorage.getItem('airdesk.' + key);
      return value === null ? fallback : value;
    } catch (error) {
      return fallback;
    }
  }

  function savePreference(key, value) {
    try { localStorage.setItem('airdesk.' + key, value); } catch (error) { /* local file storage can be unavailable */ }
  }

  function setAppearance(value, announce) {
    appearance = value === 'light' ? 'light' : 'dark';
    document.body.setAttribute('data-appearance', appearance);
    document.documentElement.setAttribute('data-appearance', appearance);
    savePreference('appearance', appearance);
    if (announce) notify(appearance === 'light' ? 'Light appearance' : 'Dark appearance');
  }

  function setWallpaper(value) {
    var allowed = ['aurora', 'dune', 'graphite'];
    wallpaper = allowed.indexOf(value) >= 0 ? value : 'aurora';
    document.body.setAttribute('data-wallpaper', wallpaper);
    savePreference('wallpaper', wallpaper);
    notify('Wallpaper · ' + wallpaper.charAt(0).toUpperCase() + wallpaper.slice(1));
  }

  function notify(text) {
    if (!toast || !text) return;
    toast.textContent = text;
    toast.classList.add('visible');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toast.classList.remove('visible'); }, 2200);
  }

  function updateClock() {
    var now = new Date();
    var days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    var months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    var hours = now.getHours();
    var minutes = String(now.getMinutes()).padStart(2, '0');
    var suffix = hours >= 12 ? 'PM' : 'AM';
    hours = hours % 12 || 12;
    clock.textContent = days[now.getDay()] + ' ' + now.getDate() + ' ' + months[now.getMonth()] + '  ' + hours + ':' + minutes + ' ' + suffix;
  }

  function focusWindow(win) {
    if (!win) return;
    state.windows.forEach(function (entry) {
      entry.el.classList.remove('focused', 'inactive');
      entry.el.style.zIndex = entry.el.style.zIndex || '';
    });
    state.windows.forEach(function (entry) {
      if (entry !== win) entry.el.classList.add('inactive');
    });
    win.el.classList.add('focused');
    win.el.classList.remove('inactive');
    win.el.style.zIndex = String(++state.z);
    state.focused = win;
    setActiveApp(win.app.menu || win.app.name || 'Finder');

    var active = document.activeElement;
    if (active && active !== document.body && active.closest && active.closest('.window') !== win.el) {
      if (typeof active.blur === 'function') active.blur();
    }
    if (win.id === 'terminal' || win.id === 'notes') {
      var field = win.id === 'terminal' ? $('.term-input', win.body) : $('.note-body', win.body);
      if (field && document.activeElement !== field && (!active || !active.closest || active.closest('.window') !== win.el)) {
        field.focus();
      }
    }
  }

  function setActiveApp(name) {
    if (activeAppLabel) activeAppLabel.textContent = name || 'Finder';
  }

  function topWindow(excluding) {
    var candidates = state.windows.filter(function (entry) { return entry !== excluding && !entry.minimized; });
    candidates.sort(function (a, b) { return (parseInt(a.el.style.zIndex, 10) || 0) - (parseInt(b.el.style.zIndex, 10) || 0); });
    return candidates[candidates.length - 1] || null;
  }

  function updateDock() {
    $$('.dock-item[data-app]', dock).forEach(function (item) {
      var id = item.getAttribute('data-app');
      var running = state.windows.some(function (entry) { return entry.id === id && !entry.minimized; });
      item.classList.toggle('running', running);
    });
  }

  function climbDock() {
    /* Keeps the dock above windows; nothing else to do yet. */
  }

  function dockMarkup() {
    var order = ['finder', 'terminal', 'notes', 'settings', 'welcome'];
    var html = order.map(function (id) {
      var app = apps[id];
      return '<button class="dock-item" data-app="' + id + '" aria-label="' + app.name + '">' +
        appIcon(id) + '<span class="dock-tooltip">' + app.name + '</span></button>';
    }).join('');
    html += '<span class="dock-divider"></span>';
    html += '<button class="dock-item" data-app="trash" aria-label="Trash">' + appIcon('trash') + '<span class="dock-tooltip">Trash</span></button>';
    return html;
  }

  function desktopIconMarkup() {
    return '<button class="desktop-icon" data-desktop-app="finder" aria-label="Workspace">' +
        '<span class="desk-art folder"></span><span class="desktop-label">Workspace</span></button>' +
      '<button class="desktop-icon" data-desktop-app="notes" aria-label="README">' +
        '<span class="desk-art document">' + icons.document + '</span><span class="desktop-label">README</span></button>' +
      '<button class="desktop-icon" data-desktop-app="trash" aria-label="Trash">' +
        '<span class="desk-art trash">' + icons.trash + '</span><span class="desktop-label">Trash</span></button>';
  }

  function rectFor(id) {
    var app = apps[id] || apps.welcome;
    var vw = window.innerWidth;
    var vh = window.innerHeight;
    var top = 39;
    var bottom = 96;
    var availableH = vh - top - bottom;
    var width = Math.min(app.width || 640, Math.max(360, vw - 32));
    var height = Math.min(app.height || 420, Math.max(260, availableH - 8));
    if (vw < 760) {
      width = Math.min(width, vw - 20);
      height = Math.min(height, availableH - 4);
    }
    var x = (vw - width) / 2;
    var y = top + Math.max(12, (availableH - height) / 2 - 10);

    if (id === 'finder') {
      x = Math.max(20, vw * 0.045);
      y = top + 22;
      width = Math.min(app.width, vw * 0.64);
      height = Math.min(app.height, availableH - 30);
    } else if (id === 'terminal') {
      width = Math.min(app.width, vw * 0.56);
      height = Math.min(app.height, Math.max(320, availableH * 0.50));
      x = vw - width - Math.max(25, vw * 0.035);
      y = vh - bottom - height - 8;
    } else if (id === 'notes') {
      x = (vw - width) / 2 + vw * 0.035;
      y = top + 28;
    } else if (id === 'welcome') {
      y = top + Math.max(10, (availableH - height) / 2 - 14);
    } else if (id === 'settings') {
      y = top + Math.max(14, (availableH - height) / 2 - 12);
    }
    return {
      x: Math.round(clamp(x, 12, Math.max(12, vw - width - 12))),
      y: Math.round(clamp(y, top, Math.max(top, vh - bottom - height))),
      width: Math.round(width),
      height: Math.round(height)
    };
  }

  function openApp(id) {
    var app = apps[id];
    if (!app) return null;
    var existing = state.windows.find(function (entry) { return entry.id === id; });
    if (existing) {
      if (existing.minimized) {
        existing.minimized = false;
        existing.el.classList.remove('minimized');
      }
      focusWindow(existing);
      updateDock();
      return existing;
    }

    var rect = rectFor(id);
    var win = {
      id: id,
      app: app,
      el: document.createElement('section'),
      minimized: false,
      maximized: false,
      previous: null
    };
    win.el.className = 'window';
    win.el.setAttribute('data-app', id);
    win.el.setAttribute('role', 'dialog');
    win.el.setAttribute('aria-label', app.name);
    win.el.style.left = rect.x + 'px';
    win.el.style.top = rect.y + 'px';
    win.el.style.width = rect.width + 'px';
    win.el.style.height = rect.height + 'px';
    win.el.innerHTML =
      '<header class="titlebar">' +
        '<div class="traffic">' +
          '<button class="close" data-window-action="close" aria-label="Close"><span>×</span></button>' +
          '<button class="min" data-window-action="minimize" aria-label="Minimize"><span>−</span></button>' +
          '<button class="max" data-window-action="zoom" aria-label="Zoom"><span>+</span></button>' +
        '</div>' +
        '<div class="titlebar-title">' + appIcon(id, 'tiny') + '<span>' + app.name + '</span></div>' +
        '<div class="titlebar-actions"></div>' +
      '</header>' +
      '<div class="window-body"></div>' +
      '<div class="resize-grip" data-resize="true" aria-hidden="true"></div>';
    windowLayer.appendChild(win.el);
    state.windows.push(win);

    var body = $('.window-body', win.el);
    body.innerHTML = app.render ? app.render() : '';
    win.body = body;

    var api = {
      openApp: openApp,
      notify: notify,
      close: function () { closeWindow(win); },
      getAppearance: function () { return appearance; },
      setAppearance: function (value) { setAppearance(value, true); },
      setWallpaper: setWallpaper,
      minimize: function () { minimizeWindow(win); }
    };
    if (typeof app.mount === 'function') {
      try { app.mount(body, api); } catch (error) { console.error(error); notify('Could not mount ' + app.name); }
    }

    focusWindow(win);
    updateDock();
    AD.state('window.open.' + id);
    return win;
  }

  function closeWindow(win) {
    if (!win) return;
    var wasFocused = state.focused === win;
    win.el.classList.add('closing');
    win.el.style.transition = 'opacity .14s ease, transform .14s ease';
    win.el.style.opacity = '0';
    win.el.style.transform = 'scale(.97)';
    setTimeout(function () {
      win.el.remove();
      state.windows = state.windows.filter(function (entry) { return entry !== win; });
      if (wasFocused) {
        var next = topWindow();
        state.focused = null;
        if (next) focusWindow(next);
        else { setActiveApp('Finder'); }
      }
      updateDock();
    }, 140);
    AD.state('window.close.' + win.id);
  }

  function minimizeWindow(win) {
    if (!win) return;
    win.minimized = true;
    win.el.classList.add('minimized');
    if (state.focused === win) {
      var next = topWindow(win);
      state.focused = null;
      if (next) focusWindow(next);
    }
    updateDock();
    notify(win.app.name + ' minimized');
    AD.state('window.minimize.' + win.id);
  }

  function toggleMaximize(win) {
    if (!win) return;
    if (win.maximized) {
      win.maximized = false;
      win.el.classList.remove('maximized');
      if (win.previous) {
        win.el.style.left = win.previous.left;
        win.el.style.top = win.previous.top;
        win.el.style.width = win.previous.width;
        win.el.style.height = win.previous.height;
      }
    } else {
      win.previous = {
        left: win.el.style.left, top: win.el.style.top,
        width: win.el.style.width, height: win.el.style.height
      };
      win.maximized = true;
      win.el.classList.add('maximized');
      win.el.style.left = '12px';
      win.el.style.top = '39px';
      win.el.style.width = (window.innerWidth - 24) + 'px';
      win.el.style.height = (window.innerHeight - 39 - 94) + 'px';
    }
    focusWindow(win);
    AD.state('window.zoom.' + win.id);
  }

  function closeMenus() {
    $$('.dropdown-menu').forEach(function (menu) { menu.remove(); });
    $$('.menubar-item.open, .menubar-status.open, .menubar-clock.open').forEach(function (button) { button.classList.remove('open'); });
    if (menuButton) menuButton.classList.remove('open');
    menuButton = null;
    if (contextMenu) contextMenu.hidden = true;
  }

  function performAction(action) {
    switch (action) {
      case 'about': openApp('welcome'); break;
      case 'settings': openApp('settings'); break;
      case 'terminal': openApp('terminal'); break;
      case 'notes': openApp('notes'); break;
      case 'finder': openApp('finder'); break;
      case 'trash': openApp('trash'); break;
      case 'spotlight': openSpotlight(); break;
      case 'close-window': closeWindow(state.focused); break;
      case 'minimize-window': minimizeWindow(state.focused); break;
      case 'zoom-window': toggleMaximize(state.focused); break;
      case 'toggle-dock': toggleDock(); break;
      case 'toggle-appearance': setAppearance(appearance === 'dark' ? 'light' : 'dark', true); break;
      case 'restart': location.reload(); break;
      case 'shut-down': notify('The demo desktop remains online'); break;
      case 'help': openApp('welcome'); break;
      case 'shortcuts': openApp('notes'); setTimeout(function () { notify('Open Notes → Remote shortcuts'); }, 350); break;
      case 'diagnostics':
        AD.post({ version: 1, type: 'action', sessionId: AD.sessionId, action: 'diagnostics', timestamp: Date.now() });
        notify('Opened session diagnostics on iPhone');
        break;
      case 'preview':
        AD.post({ version: 1, type: 'action', sessionId: AD.sessionId, action: 'preview', timestamp: Date.now() });
        break;
      case 'copy':
        try { document.execCommand('copy'); notify('Copied selection'); } catch (error) { notify('Nothing selected'); }
        break;
      case 'cut':
        try { document.execCommand('cut'); } catch (error) { notify('Nothing selected'); }
        break;
      case 'paste': notify('Paste uses the iPhone keyboard field'); break;
      case 'select-all':
        if (document.activeElement && document.activeElement.select) document.activeElement.select();
        else { var selection = window.getSelection(); if (selection) { selection.removeAllRanges(); var range = document.createRange(); range.selectNodeContents(state.focused ? state.focused.body : document.body); selection.addRange(range); } }
        break;
      case 'undo': try { document.execCommand('undo'); } catch (error) { /* no-op */ } break;
      case 'redo': try { document.execCommand('redo'); } catch (error) { /* no-op */ } break;
      case 'cycle-wallpaper': {
        var order = ['aurora', 'dune', 'graphite'];
        setWallpaper(order[(order.indexOf(wallpaper) + 1) % order.length]);
        break;
      }
      case 'wifi': notify('Wanix local bridge · connected'); break;
      case 'battery': notify('Simulator battery · 82%'); break;
      case 'calendar': notify(clock.textContent); break;
      case 'control': openApp('settings'); break;
      case 'bring-front': if (state.focused) focusWindow(state.focused); break;
      case 'hide-window': minimizeWindow(state.focused); break;
      case 'quit':
        if (state.focused) { var id = state.focused.id; state.windows.filter(function (e) { return e.id === id; }).forEach(closeWindow); }
        break;
      default: break;
    }
  }

  function menuItems(name) {
    switch (name) {
      case 'apple':
        return [
          { label: 'About AirDesk', action: 'about' },
          { label: 'System Settings…', action: 'settings' },
          { separator: true },
          { label: 'Spotlight…', action: 'spotlight', shortcut: '⌘Space' },
          { label: 'Show / Hide Dock', action: 'toggle-dock' },
          { separator: true },
          { label: 'Restart Desktop', action: 'restart' },
          { label: 'Shut Down…', action: 'shut-down' }
        ];
      case 'app': {
        var nameValue = activeAppLabel.textContent || 'Finder';
        return [
          { label: 'About ' + nameValue, action: 'about' },
          { separator: true },
          { label: 'Settings…', action: 'settings', shortcut: '⌘,' },
          { separator: true },
          { label: 'Hide ' + nameValue, action: 'hide-window', shortcut: '⌘H' },
          { label: 'Quit ' + nameValue, action: 'quit', shortcut: '⌘Q' }
        ];
      }
      case 'file':
        return [
          { label: 'New Terminal Window', action: 'terminal', shortcut: '⌘T' },
          { label: 'New Note', action: 'notes', shortcut: '⌘N' },
          { label: 'Open Finder', action: 'finder' },
          { separator: true },
          { label: 'Close Window', action: 'close-window', shortcut: '⌘W' }
        ];
      case 'edit':
        return [
          { label: 'Undo', action: 'undo', shortcut: '⌘Z' },
          { label: 'Redo', action: 'redo', shortcut: '⇧⌘Z' },
          { separator: true },
          { label: 'Cut', action: 'cut', shortcut: '⌘X' },
          { label: 'Copy', action: 'copy', shortcut: '⌘C' },
          { label: 'Paste', action: 'paste', shortcut: '⌘V' },
          { label: 'Select All', action: 'select-all', shortcut: '⌘A' }
        ];
      case 'view':
        return [
          { label: 'Show / Hide Dock', action: 'toggle-dock' },
          { label: appearance === 'dark' ? 'Use Light Appearance' : 'Use Dark Appearance', action: 'toggle-appearance' },
          { label: 'Next Wallpaper', action: 'cycle-wallpaper' },
          { separator: true },
          { label: 'Enter Full Screen', action: 'zoom-window', shortcut: '⌃⌘F' }
        ];
      case 'window':
        return [
          { label: 'Minimize', action: 'minimize-window', shortcut: '⌘M' },
          { label: 'Zoom', action: 'zoom-window' },
          { separator: true },
          { label: 'Bring All to Front', action: 'bring-front' }
        ];
      case 'help':
        return [
          { label: 'AirDesk Help', action: 'help' },
          { label: 'Keyboard Shortcuts', action: 'shortcuts' },
          { separator: true },
          { label: 'Session Diagnostics', action: 'diagnostics' }
        ];
      case 'wanix':
        return [
          { label: 'Runtime · bundled shell', action: 'terminal', disabled: true },
          { label: 'Bridge · protocol v1', action: 'terminal', disabled: true },
          { separator: true },
          { label: 'Open Terminal', action: 'terminal' },
          { label: 'Session Diagnostics', action: 'diagnostics' }
        ];
      case 'control':
        return [
          { label: 'Wanix bridge · connected', action: 'wifi' },
          { label: 'Appearance · ' + (appearance === 'dark' ? 'Dark' : 'Light'), action: 'toggle-appearance' },
          { label: 'Wi-Fi · AirDesk direct', action: 'wifi' },
          { separator: true },
          { label: 'Open System Settings', action: 'settings' }
        ];
      case 'battery':
        return [{ label: 'Battery · 82%', action: 'battery', disabled: true }, { label: 'This is a simulated display', action: 'battery', disabled: true }];
      case 'clock':
        return [{ label: clock.textContent, action: 'calendar' }, { separator: true }, { label: 'Open Calendar', action: 'calendar' }, { label: 'Show Welcome', action: 'about' }];
      default:
        return [];
    }
  }

  function openMenu(button) {
    var name = button.getAttribute('data-menu');
    var wasOpen = button.classList.contains('open');
    closeMenus();
    if (wasOpen) return;
    var items = menuItems(name);
    if (!items.length) return;

    var menu = document.createElement('div');
    menu.className = 'dropdown-menu';
    menu.innerHTML = items.map(function (item) {
      if (item.separator) return '<div class="menu-separator"></div>';
      return '<button class="menu-entry' + (item.disabled ? ' disabled' : '') + '" data-action="' + (item.disabled ? '' : item.action) + '">' +
        '<span>' + item.label + '</span>' +
        (item.shortcut ? '<span class="shortcut">' + item.shortcut + '</span>' : '') +
      '</button>';
    }).join('');
    desktop.appendChild(menu);

    var rect = button.getBoundingClientRect();
    var left = name === 'apple' ? rect.left : rect.left;
    var top = rect.bottom + 4;
    var width = menu.offsetWidth;
    var height = menu.offsetHeight;
    if (left + width > window.innerWidth - 8) left = window.innerWidth - width - 8;
    if (top + height > window.innerHeight - 8) top = Math.max(32, rect.top - height - 4);
    menu.style.left = Math.max(8, left) + 'px';
    menu.style.top = top + 'px';
    button.classList.add('open');
    menuButton = button;
  }

  function toggleDock() {
    var hidden = document.body.classList.toggle('dock-hidden');
    notify(hidden ? 'Dock hidden · restore from View menu' : 'Dock shown');
  }

  function showContextMenu(x, y, target) {
    var items;
    if (target.closest('.desktop-icon')) {
      items = [
        { label: 'Open', action: 'open-icon' },
        { label: 'Get Info', action: 'info' },
        { separator: true },
        { label: 'Move to Trash', action: 'trash-icon' }
      ];
      contextMenu.setAttribute('data-target-app', target.closest('.desktop-icon').getAttribute('data-desktop-app'));
    } else if (target.closest('.file-tile')) {
      items = [
        { label: 'Open', action: 'open-file' },
        { label: 'Get Info', action: 'info' },
        { separator: true },
        { label: 'Move to Trash', action: 'trash-icon' }
      ];
      var tile = target.closest('.file-tile');
      contextMenu.setAttribute('data-target-app', tile.getAttribute('data-open-app') || 'finder');
    } else if (target.closest('.window')) {
      items = [
        { label: 'Close Window', action: 'close-window' },
        { label: 'Minimize', action: 'minimize-window' },
        { label: 'Zoom', action: 'zoom-window' },
        { separator: true },
        { label: 'Bring All to Front', action: 'bring-front' }
      ];
    } else {
      items = [
        { label: 'New Terminal Window', action: 'terminal' },
        { label: 'New Note', action: 'notes' },
        { separator: true },
        { label: 'Show / Hide Dock', action: 'toggle-dock' },
        { label: 'Change Wallpaper', action: 'cycle-wallpaper' },
        { separator: true },
        { label: 'About AirDesk', action: 'about' }
      ];
    }
    contextMenu.innerHTML = items.map(function (item) {
      if (item.separator) return '<div class="menu-separator"></div>';
      return '<button class="menu-entry" data-action="' + item.action + '"><span>' + item.label + '</span></button>';
    }).join('');
    contextMenu.hidden = false;
    var width = contextMenu.offsetWidth;
    var height = contextMenu.offsetHeight;
    contextMenu.style.left = clamp(x, 8, window.innerWidth - width - 8) + 'px';
    contextMenu.style.top = clamp(y, 34, window.innerHeight - height - 8) + 'px';
  }

  function handleContextTarget(action) {
    var id = contextMenu.getAttribute('data-target-app');
    if (action === 'open-icon' && id) openApp(id);
    else if (action === 'open-file') { if (id) openApp(id); }
    else if (action === 'info') notify('Wanix virtual item · 48.2 GB available');
    else if (action === 'trash-icon') notify('Moved to Trash');
    else performAction(action);
  }

  /* Pointer */
  function point(event) {
    return {
      x: clamp(Number(event.x) || 0, 0, 1) * window.innerWidth,
      y: clamp(Number(event.y) || 0, 0, 1) * window.innerHeight
    };
  }

  function moveCursor(x, y) {
    state.pointer.x = x;
    state.pointer.y = y;
    if (cursor) {
      cursor.style.left = '0px';
      cursor.style.top = '0px';
      cursor.style.margin = '0';
      cursor.style.transform = 'translate3d(' + (x - 3) + 'px,' + (y - 2) + 'px,0)';
      if (!state.pointerVisible || !cursor.classList.contains('visible')) {
        state.pointerVisible = true;
        cursor.classList.add('visible');
      }
    }
    updateHover(x, y);
  }

  function updateHover(x, y) {
    var target = document.elementFromPoint(x, y);
    var hovered = target && target.closest ? (target.closest('.dock-item') || target.closest('.desktop-icon') || null) : null;
    if (state.hoverElement && state.hoverElement !== hovered) state.hoverElement.classList.remove('hovered');
    if (hovered) hovered.classList.add('hovered');
    state.hoverElement = hovered;
  }

  function dispatchMouse(type, target, x, y, button, count) {
    if (!target) return;
    var event = new MouseEvent(type, {
      bubbles: true,
      cancelable: true,
      view: window,
      clientX: x,
      clientY: y,
      screenX: x,
      screenY: y,
      button: button || 0,
      buttons: type === 'mousedown' ? 1 : 0,
      detail: count || 1
    });
    target.dispatchEvent(event);
  }

  function clickAt(x, y, count, button) {
    moveCursor(x, y);
    var target = document.elementFromPoint(x, y);
    if (!target) return;

    if (cursor) {
      cursor.classList.add('clicking');
      setTimeout(function () { cursor.classList.remove('clicking'); }, 160);
    }

    if (button === 1) {
      closeMenus();
      showContextMenu(x, y, target);
      return;
    }

    var menuEntry = target.closest('.menu-entry');
    if (menuEntry) {
      menuEntry.click();
      return;
    }

    var spotlightResult = target.closest('.spotlight-result');
    if (spotlightResult) {
      spotlightResult.click();
      return;
    }

    closeMenus();

    var dockItem = target.closest('.dock-item');
    if (dockItem) {
      var dockApp = dockItem.getAttribute('data-app');
      if (dockApp) openApp(dockApp);
      return;
    }

    var desktopIcon = target.closest('.desktop-icon');
    if (desktopIcon) {
      $$('.desktop-icon').forEach(function (item) { item.classList.remove('selected'); });
      desktopIcon.classList.add('selected');
      if (count >= 2) {
        var desktopApp = desktopIcon.getAttribute('data-desktop-app');
        if (desktopApp) openApp(desktopApp);
      }
      return;
    }

    if (target.closest('.file-tile')) {
      dispatchMouse('click', target, x, y, 0, count);
      if (count >= 2) dispatchMouse('dblclick', target, x, y, 0, 2);
      return;
    }

    var winEl = target.closest('.window');
    if (winEl) {
      var win = state.windows.find(function (entry) { return entry.el === winEl; });
      if (win) focusWindow(win);
    }

    var editable = target.closest('input, textarea, [contenteditable="true"]');
    if (editable) {
      if (typeof editable.focus === 'function') editable.focus();
      if (typeof editable.setSelectionRange === 'function') {
        try {
          var position = editable.value ? editable.value.length : 0;
          editable.setSelectionRange(position, position);
        } catch (error) { /* some input types do not support selection */ }
      }
      return;
    }

    var traffic = target.closest('[data-window-action]');
    if (traffic) {
      traffic.click();
      return;
    }

    dispatchMouse('mousedown', target, x, y, 0, count);
    dispatchMouse('mouseup', target, x, y, 0, count);
    dispatchMouse('click', target, x, y, 0, count);
    if (count >= 2) dispatchMouse('dblclick', target, x, y, 0, 2);
  }

  function pointerDown(event) {
    var p = point(event);
    moveCursor(p.x, p.y);
    var target = document.elementFromPoint(p.x, p.y);
    state.downTarget = target;
    if (!target) return;

    var traffic = target.closest('.traffic, .titlebar-actions');
    if (traffic) return;

    var winEl = target.closest('.window');
    if (!winEl) return;
    var win = state.windows.find(function (entry) { return entry.el === winEl; });
    if (!win) return;
    focusWindow(win);

    if (target.closest('.resize-grip')) {
      state.drag = {
        type: 'resize',
        win: win,
        startX: p.x,
        startY: p.y,
        startW: winEl.offsetWidth,
        startH: winEl.offsetHeight
      };
      return;
    }

    if (target.closest('.titlebar')) {
      state.drag = {
        type: 'move',
        win: win,
        offX: p.x - winEl.offsetLeft,
        offY: p.y - winEl.offsetTop
      };
      winEl.classList.add('dragging');
      return;
    }

    dispatchMouse('mousedown', target, p.x, p.y, 0, 1);
    if (target.closest('input, textarea, [contenteditable="true"]')) {
      target.focus();
    }
  }

  function pointerMove(event) {
    var p = point(event);
    moveCursor(p.x, p.y);
    if (!state.drag) return;
    var drag = state.drag;
    var winEl = drag.win.el;

    if (drag.type === 'move') {
      var left = clamp(p.x - drag.offX, 6, window.innerWidth - winEl.offsetWidth - 6);
      var top = clamp(p.y - drag.offY, 32, window.innerHeight - 40);
      winEl.style.left = left + 'px';
      winEl.style.top = top + 'px';
    } else if (drag.type === 'resize') {
      var minWidth = Math.max(320, drag.win.app.minWidth || 340);
      var minHeight = Math.max(220, drag.win.app.minHeight || 240);
      var width = clamp(drag.startW + (p.x - drag.startX), minWidth, window.innerWidth - winEl.offsetLeft - 8);
      var height = clamp(drag.startH + (p.y - drag.startY), minHeight, window.innerHeight - winEl.offsetTop - 76);
      winEl.style.width = width + 'px';
      winEl.style.height = height + 'px';
    }
  }

  function pointerUp(event) {
    var p = point(event);
    moveCursor(p.x, p.y);
    if (state.drag) {
      state.drag.win.el.classList.remove('dragging');
      state.drag = null;
      return;
    }
    if (state.downTarget) {
      var target = document.elementFromPoint(p.x, p.y) || state.downTarget;
      dispatchMouse('mouseup', target, p.x, p.y, 0, 1);
      state.downTarget = null;
    }
  }

  function scrollAt(event) {
    var x = state.pointer.x;
    var y = state.pointer.y;
    var target = document.elementFromPoint(x, y);
    var scroller = target;
    while (scroller && scroller !== document.body && scroller !== document.documentElement) {
      var style = window.getComputedStyle(scroller);
      var scrollableY = /(auto|scroll)/.test(style.overflowY) && scroller.scrollHeight > scroller.clientHeight + 2;
      var scrollableX = /(auto|scroll)/.test(style.overflowX) && scroller.scrollWidth > scroller.clientWidth + 2;
      if (scrollableY || scrollableX) break;
      scroller = scroller.parentElement;
    }
    if (!scroller || scroller === document.body) {
      scroller = state.focused ? state.focused.body : null;
    }
    if (scroller) {
      var dx = Number(event.dx) || 0;
      var dy = Number(event.dy) || 0;
      if (scroller.scrollHeight > scroller.clientHeight + 2) scroller.scrollTop += dy * 0.72;
      if (scroller.scrollWidth > scroller.clientWidth + 2) scroller.scrollLeft += dx * 0.72;
    }
  }

  /* Text and keyboard */
  function activeEditable() {
    var element = document.activeElement;
    if (element && (element.tagName === 'INPUT' || element.tagName === 'TEXTAREA' || element.isContentEditable)) {
      return element;
    }
    if (spotlight && !spotlight.hidden) return spotlightInput;
    if (state.focused) {
      var selector = state.focused.id === 'terminal' ? '.term-input' : state.focused.id === 'notes' ? '.note-body' : 'input, textarea';
      var candidate = $(selector, state.focused.body);
      if (candidate) return candidate;
    }
    return null;
  }

  function insertText(text) {
    if (!text) return false;
    var element = activeEditable();
    if (!element) {
      if (!state.typingHintShown) {
        state.typingHintShown = true;
        notify('Open Notes or Terminal to type');
      }
      return false;
    }
    element.focus();
    if (element.isContentEditable) {
      try { document.execCommand('insertText', false, text); } catch (error) { element.textContent += text; }
    } else {
      var start = typeof element.selectionStart === 'number' ? element.selectionStart : element.value.length;
      var end = typeof element.selectionEnd === 'number' ? element.selectionEnd : start;
      element.value = element.value.slice(0, start) + text + element.value.slice(end);
      var position = start + text.length;
      try { element.setSelectionRange(position, position); } catch (error) { /* no-op */ }
    }
    element.dispatchEvent(new Event('input', { bubbles: true }));
    return true;
  }

  function deleteBackward() {
    var element = activeEditable();
    if (!element) return;
    element.focus();
    if (element.isContentEditable) {
      try { document.execCommand('delete'); } catch (error) { /* no-op */ }
      element.dispatchEvent(new Event('input', { bubbles: true }));
      return;
    }
    var start = typeof element.selectionStart === 'number' ? element.selectionStart : element.value.length;
    var end = typeof element.selectionEnd === 'number' ? element.selectionEnd : start;
    if (start !== end) {
      element.value = element.value.slice(0, start) + element.value.slice(end);
    } else if (start > 0) {
      element.value = element.value.slice(0, start - 1) + element.value.slice(start);
      start -= 1;
    }
    try { element.setSelectionRange(start, start); } catch (error) { /* no-op */ }
    element.dispatchEvent(new Event('input', { bubbles: true }));
  }

  function submitFocused() {
    var element = activeEditable();
    if (!element) return;
    if (element.classList && element.classList.contains('term-input')) {
      element.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', bubbles: true }));
    } else if (element.tagName === 'TEXTAREA') {
      insertText('\n');
    } else if (element.tagName === 'INPUT') {
      element.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', bubbles: true }));
    }
  }

  function moveCaret(direction) {
    var element = activeEditable();
    if (!element || element.isContentEditable) return false;
    var position = typeof element.selectionStart === 'number' ? element.selectionStart : 0;
    var length = element.value ? element.value.length : 0;
    var next = direction === 'left' ? Math.max(0, position - 1) : Math.min(length, position + 1);
    try { element.setSelectionRange(next, next); } catch (error) { return false; }
    return true;
  }

  function handleKey(event, isDown) {
    if (!event || !event.key) return;
    var modifiers = Array.isArray(event.modifiers) ? event.modifiers : [];
    var meta = modifiers.indexOf('Meta') >= 0;
    var control = modifiers.indexOf('Control') >= 0;
    var shift = modifiers.indexOf('Shift') >= 0;
    var key = event.key;
    var lower = key.length === 1 ? key.toLowerCase() : key;
    if (!isDown) return;

    if (lower === 'Escape' || key === 'Escape') {
      if (spotlight && !spotlight.hidden) { closeSpotlight(); return; }
      closeMenus();
      return;
    }

    if (meta || control) {
      if (key === ' ' || lower === ' ') { openSpotlight(); return; }
      switch (lower) {
        case 'w': closeWindow(state.focused); return;
        case 'm': minimizeWindow(state.focused); return;
        case 'q': performAction('quit'); return;
        case 't': openApp('terminal'); return;
        case 'n': openApp('notes'); return;
        case 'f': openApp('finder'); return;
        case ',': openApp('settings'); return;
        case 'k': openSpotlight(); return;
        case 'a': performAction('select-all'); return;
        case 'c': performAction('copy'); return;
        case 'x': performAction('cut'); return;
        case 'v': performAction('paste'); return;
        case 'z': performAction(shift ? 'redo' : 'undo'); return;
        case 'h': minimizeWindow(state.focused); return;
        default: break;
      }
    }

    if (key === 'Backspace' || key === 'Delete') { deleteBackward(); return; }
    if (key === 'Return' || key === 'Enter') {
      if (spotlight && !spotlight.hidden) { activateFirstSpotlightResult(); return; }
      submitFocused();
      return;
    }
    if (key === 'Tab') { insertText('\t'); return; }
    if (key === 'ArrowLeft') { moveCaret('left'); return; }
    if (key === 'ArrowRight') { moveCaret('right'); return; }
    if (key === 'ArrowUp' || key === 'ArrowDown') {
      var element = activeEditable();
      if (element && element.classList && element.classList.contains('term-input')) {
        element.dispatchEvent(new KeyboardEvent('keydown', { key: key, code: key, bubbles: true }));
      } else if (state.focused && state.focused.id === 'notes') {
        moveCaret(key === 'ArrowUp' ? 'left' : 'right');
      }
      return;
    }

    if (key.length === 1 && !meta && !control) {
      insertText(shift ? key.toUpperCase() : key);
    }
  }

  /* Spotlight */
  function openSpotlight() {
    closeMenus();
    spotlight.hidden = false;
    spotlightInput.value = '';
    renderSpotlight('');
    setTimeout(function () { spotlightInput.focus(); }, 30);
    AD.state('spotlight.open');
  }

  function closeSpotlight() {
    spotlight.hidden = true;
    spotlightInput.value = '';
    if (state.focused) focusWindow(state.focused);
  }

  function spotlightApps() {
    return ['finder', 'terminal', 'notes', 'settings', 'welcome', 'trash'].map(function (id) {
      return { id: id, name: apps[id].name, kind: id === 'trash' ? 'Utility' : 'Application' };
    });
  }

  function renderSpotlight(query) {
    var term = String(query || '').trim().toLowerCase();
    var results = spotlightApps().filter(function (entry) {
      return !term || entry.name.toLowerCase().indexOf(term) >= 0 || entry.kind.toLowerCase().indexOf(term) >= 0;
    });
    if (!results.length) {
      spotlightResults.innerHTML = '<div class="spotlight-empty">No applications match “' + escapeHTML(term) + '”</div>';
      return;
    }
    spotlightResults.innerHTML = results.map(function (entry, index) {
      return '<button class="spotlight-result' + (index === 0 ? ' selected' : '') + '" data-spotlight-app="' + entry.id + '">' +
        appIcon(entry.id) +
        '<span><strong>' + entry.name + '</strong><small>' + entry.kind + ' · Wanix workspace</small></span>' +
      '</button>';
    }).join('');
    $$('.spotlight-result', spotlightResults).forEach(function (button) {
      button.addEventListener('click', function () {
        closeSpotlight();
        openApp(button.getAttribute('data-spotlight-app'));
      });
    });
  }

  function activateFirstSpotlightResult() {
    var first = $('.spotlight-result', spotlightResults);
    if (first) first.click();
  }

  function escapeHTML(value) {
    return String(value).replace(/[&<>"']/g, function (character) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character];
    });
  }

  function activateSession() {
    moveCursor(window.innerWidth / 2, window.innerHeight / 2);
    cursor.classList.add('visible');
  }

  function endSession() {
    state.drag = null;
    state.downTarget = null;
    closeMenus();
    closeSpotlight();
    cursor.classList.remove('visible');
  }

  function cancelPointer() {
    state.drag = null;
    state.downTarget = null;
    if (cursor) cursor.classList.remove('visible');
  }

  function handleInput(event) {
    switch (event.type) {
      case 'pointerMove': {
        var p = point(event);
        moveCursor(p.x, p.y);
        break;
      }
      case 'pointerClick': {
        var pc = point(event);
        clickAt(pc.x, pc.y, Number(event.clickCount) || 1, Number(event.button) || 0);
        break;
      }
      case 'pointerDown': {
        var pd = point(event);
        pointerDown(event);
        break;
      }
      case 'pointerUp': pointerUp(event); break;
      case 'pointerCancel': cancelPointer(); break;
      case 'scroll': scrollAt(event); break;
      case 'keyDown': handleKey(event, true); break;
      case 'keyUp': handleKey(event, false); break;
      case 'textInput': insertText(event.text); break;
      case 'focusChanged': break;
      case 'sessionStart': activateSession(); break;
      case 'sessionEnd': endSession(); break;
      default: break;
    }
  }

  function handleControl(message) {
    if (!message) return;
    if (message.type === 'appearance' && message.appearance) {
      setAppearance(message.appearance, false);
      notify('Appearance synced from iPhone');
      return;
    }
    if (message.type === 'action') {
      if (message.action === 'dock') toggleDock();
      else if (message.action === 'spotlight') openSpotlight();
      else if (message.action === 'appearance') setAppearance(appearance === 'dark' ? 'light' : 'dark', true);
      else if (message.action === 'cycle-wallpaper') performAction('cycle-wallpaper');
    }
  }

  /* Global events */
  function bindEvents() {
    $$('#menubar [data-menu]').forEach(function (button) {
      button.addEventListener('click', function (event) {
        event.stopPropagation();
        openMenu(button);
      });
    });

    document.addEventListener('click', function (event) {
      var entry = event.target.closest('.menu-entry');
      if (entry) {
        var action = entry.getAttribute('data-action');
        var inContext = !!entry.closest('.context-menu');
        closeMenus();
        if (inContext && (action === 'open-icon' || action === 'open-file' || action === 'info' || action === 'trash-icon')) {
          handleContextTarget(action);
        } else if (action) {
          showContextMenuTarget = null;
          performAction(action);
        }
        return;
      }

      var windowAction = event.target.closest('[data-window-action]');
      if (windowAction) {
        var container = windowAction.closest('.window');
        var targetWin = state.windows.find(function (entryWin) { return entryWin.el === container; });
        if (targetWin) {
          var actionName = windowAction.getAttribute('data-window-action');
          if (actionName === 'close') closeWindow(targetWin);
          else if (actionName === 'minimize') minimizeWindow(targetWin);
          else if (actionName === 'zoom') toggleMaximize(targetWin);
        }
        return;
      }

      if (!event.target.closest('.dropdown-menu') && !event.target.closest('.context-menu') && !event.target.closest('[data-menu]')) {
        closeMenus();
      }

      var clickedWindow = event.target.closest('.window');
      if (clickedWindow) {
        var clicked = state.windows.find(function (entryWin) { return entryWin.el === clickedWindow; });
        if (clicked) focusWindow(clicked);
      }

      if (event.target.closest('.dock-item')) {
        var dockApp = event.target.closest('.dock-item').getAttribute('data-app');
        if (dockApp) openApp(dockApp);
      }
    });

    $$('.titlebar').forEach(function (bar) {
      bar.addEventListener('dblclick', function () { /* delegated below */ });
    });

    windowLayer.addEventListener('dblclick', function (event) {
      if (event.target.closest('.titlebar') && !event.target.closest('.traffic')) {
        var winEl = event.target.closest('.window');
        var win = state.windows.find(function (entry) { return entry.el === winEl; });
        if (win) toggleMaximize(win);
      }
    });

    spotlight.addEventListener('click', function (event) {
      if (event.target === spotlight) closeSpotlight();
    });
    spotlightInput.addEventListener('input', function () { renderSpotlight(spotlightInput.value); });
    spotlightInput.addEventListener('keydown', function (event) {
      if (event.key === 'Escape') { event.preventDefault(); closeSpotlight(); }
      else if (event.key === 'Enter') { event.preventDefault(); activateFirstSpotlightResult(); }
      else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        event.preventDefault();
        var results = $$('.spotlight-result', spotlightResults);
        if (!results.length) return;
        var index = results.findIndex(function (item) { return item.classList.contains('selected'); });
        if (index < 0) index = 0;
        index = event.key === 'ArrowDown' ? (index + 1) % results.length : (index - 1 + results.length) % results.length;
        results.forEach(function (item) { item.classList.remove('selected'); });
        results[index].classList.add('selected');
      }
    });

    window.addEventListener('resize', function () {
      clearTimeout(window.__airdeskResize);
      window.__airdeskResize = setTimeout(function () {
        state.windows.forEach(function (entry) {
          if (entry.maximized) {
            entry.el.style.width = (window.innerWidth - 24) + 'px';
            entry.el.style.height = (window.innerHeight - 39 - 94) + 'px';
          } else {
            var maxLeft = Math.max(6, window.innerWidth - 140);
            var maxTop = Math.max(32, window.innerHeight - 90);
            entry.el.style.left = Math.min(parseInt(entry.el.style.left, 10) || 20, maxLeft) + 'px';
            entry.el.style.top = Math.min(parseInt(entry.el.style.top, 10) || 40, maxTop) + 'px';
          }
        });
        AD.viewport();
      }, 140);
    });
  }

  var showContextMenuTarget = null;

  function init() {
    document.body.classList.add('native');
    setAppearance(window.AIRDESK_APPEARANCE || loadPreference('appearance', 'dark'), false);
    setWallpaper(loadPreference('wallpaper', 'aurora'));
    if (loadPreference('reduce-transparency', 'false') === 'true') document.body.classList.add('reduce-transparency');

    $('.apple').innerHTML = icons.apple || '';
    $('[data-menu="control"]').innerHTML = icons.settings || '';
    $('[data-menu="battery"]').innerHTML = (icons.battery || '') + '<span>82%</span>';

    clock.textContent = '';
    updateClock();
    clearInterval(clockTimer);
    clockTimer = setInterval(updateClock, 15000);

    dock.innerHTML = dockMarkup();
    $('#desktop-icons').innerHTML = desktopIconMarkup();

    bindEvents();
    AD.onInput(handleInput);
    AD.onControl(handleControl);

    $$('.desktop-icon').forEach(function (icon) {
      icon.addEventListener('click', function () {
        $$('.desktop-icon').forEach(function (item) { item.classList.remove('selected'); });
        icon.classList.add('selected');
      });
      icon.addEventListener('dblclick', function () {
        var id = icon.getAttribute('data-desktop-app');
        if (id) openApp(id);
      });
    });

    setTimeout(function () {
      openApp('finder');
      openApp('terminal');
      openApp('welcome');
      if (state.focused) focusWindow(state.focused);
    }, 90);

    setTimeout(function () {
      if (!bootHidden) {
        bootHidden = true;
        if (boot) boot.classList.add('hidden');
        AD.ready();
        AD.viewport(window.innerWidth, window.innerHeight);
        AD.state('shell.ready');
      }
    }, 480);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
