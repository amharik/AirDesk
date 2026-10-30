"use strict";
(() => {
  // src/desktop/window-manager.ts
  var DEFAULT_INSETS = { top: 39, right: 0, bottom: 96, left: 0 };
  function createAirDeskWindowTemplate(document2) {
    const template2 = document2.createElement("div");
    template2.innerHTML = '<div class="wb-header airdesk-titlebar titlebar"><div class="traffic airdesk-traffic"><button class="close" type="button" data-window-action="close" aria-label="Close"><span>\xD7</span></button><button class="min" type="button" data-window-action="minimize" aria-label="Minimize"><span>\u2212</span></button><button class="max" type="button" data-window-action="maximize" aria-label="Maximize"><span>+</span></button></div><div class="wb-drag airdesk-drag"><div class="wb-icon airdesk-title-icon"></div><div class="wb-title airdesk-title"></div></div><div class="airdesk-titlebar-actions"></div></div><div class="wb-body airdesk-window-body window-body"></div><div class="wb-n"></div><div class="wb-s"></div><div class="wb-w"></div><div class="wb-e"></div><div class="wb-nw"></div><div class="wb-ne"></div><div class="wb-se"></div><div class="wb-sw"></div>';
    return template2;
  }
  var WindowHandle = class {
    constructor(id, instance, element, body2, insets, onClosed) {
      this.id = id;
      this.instance = instance;
      this.element = element;
      this.body = body2;
      this.insets = insets;
      this.onClosed = onClosed;
      this.closedState = false;
    }
    get closed() {
      return this.closedState;
    }
    focus() {
      if (!this.closedState) this.instance.focus();
    }
    minimize() {
      if (!this.closedState) this.instance.minimize();
    }
    maximize() {
      if (this.closedState) return;
      const view = this.element.ownerDocument.defaultView;
      view?.dispatchEvent(new Event("resize"));
      this.instance.maximize();
    }
    restore() {
      if (!this.closedState) this.instance.restore();
    }
    close() {
      if (!this.closedState) this.instance.close();
    }
    setTitle(title) {
      if (!this.closedState) this.instance.setTitle(title);
    }
    setBounds(bounds) {
      if (this.closedState) return;
      this.instance.resize(bounds.width, bounds.height).move(bounds.x, bounds.y);
    }
    setViewportInsets(insets) {
      if (this.closedState) return;
      const wasMaximized = this.instance.max;
      if (wasMaximized) this.instance.restore();
      this.insets = insets;
      this.applyInsets();
      if (wasMaximized) this.instance.maximize();
    }
    clientToWindowPoint(clientX, clientY) {
      const rect = this.element.getBoundingClientRect();
      return {
        x: clientX - rect.left,
        y: clientY - rect.top
      };
    }
    markClosed() {
      this.closedState = true;
      this.onClosed();
    }
    applyInsets() {
      this.instance.top = this.insets.top;
      this.instance.right = this.insets.right;
      this.instance.bottom = this.insets.bottom;
      this.instance.left = this.insets.left;
      this.clampToViewport();
    }
    clampToViewport() {
      if (this.instance.max || this.instance.min) return;
      const view = this.element.ownerDocument.defaultView;
      if (!view) return;
      const maxX = Math.max(
        this.insets.left,
        view.innerWidth - this.insets.right - Math.min(120, this.instance.width)
      );
      const maxY = Math.max(
        this.insets.top,
        view.innerHeight - this.insets.bottom - Math.min(80, this.instance.height)
      );
      const x = Math.min(Math.max(this.instance.x, this.insets.left), maxX);
      const y = Math.min(Math.max(this.instance.y, this.insets.top), maxY);
      if (x !== this.instance.x || y !== this.instance.y) this.instance.move(x, y);
    }
  };
  var WinBoxWindowManager = class {
    constructor(options) {
      this.options = options;
      this.windows = /* @__PURE__ */ new Map();
      this.focusStack = [];
      this.insets = { ...DEFAULT_INSETS, ...options.insets };
    }
    open(descriptor) {
      const existing = this.windows.get(descriptor.id);
      if (existing && !existing.closed) {
        existing.focus();
        return existing;
      }
      const document2 = this.options.document ?? this.options.root.ownerDocument;
      const template2 = createAirDeskWindowTemplate(document2);
      const instance = this.options.factory({
        id: descriptor.id,
        root: this.options.root,
        title: descriptor.title,
        icon: descriptor.icon,
        template: template2,
        x: descriptor.bounds.x,
        y: descriptor.bounds.y,
        width: descriptor.bounds.width,
        height: descriptor.bounds.height,
        minwidth: descriptor.minWidth ?? 380,
        minheight: descriptor.minHeight ?? 260,
        top: this.insets.top,
        right: this.insets.right,
        bottom: this.insets.bottom,
        left: this.insets.left,
        class: "airdesk-window window",
        onfocus: () => {
          this.bringToFront(descriptor.id);
          descriptor.onFocus?.();
        },
        onblur: descriptor.onBlur,
        onmove: descriptor.onMove,
        onresize: descriptor.onResize,
        onminimize: () => {
          this.removeFromFocusStack(descriptor.id);
          descriptor.onMinimize?.();
        },
        onmaximize: descriptor.onMaximize,
        onrestore: descriptor.onRestore,
        onclose: () => {
          if (descriptor.onBeforeClose?.() === false) return true;
          this.remove(descriptor.id);
          descriptor.onClosed?.();
          return false;
        }
      });
      instance.dom.setAttribute("data-app", descriptor.id);
      instance.dom.setAttribute("role", "dialog");
      instance.dom.setAttribute("aria-label", descriptor.appName ?? descriptor.title);
      if (descriptor.content instanceof Node) {
        instance.body.appendChild(descriptor.content);
      } else if (typeof descriptor.content === "string") {
        instance.body.innerHTML = descriptor.content;
      }
      const handle = new WindowHandle(
        descriptor.id,
        instance,
        instance.dom,
        instance.body,
        this.insets,
        () => {
          this.windows.delete(descriptor.id);
          const index = this.focusStack.indexOf(descriptor.id);
          if (index >= 0) this.focusStack.splice(index, 1);
        }
      );
      this.wireChrome(instance, handle);
      this.windows.set(descriptor.id, handle);
      this.placeInFocusStack(descriptor.id);
      instance.focus();
      return handle;
    }
    get(id) {
      return this.windows.get(id);
    }
    getFocusOrder() {
      return [...this.focusStack];
    }
    topmost() {
      const id = this.focusStack[this.focusStack.length - 1];
      return id ? this.windows.get(id) : void 0;
    }
    setViewportInsets(insets) {
      this.insets = { ...this.insets, ...insets };
      for (const handle of this.windows.values()) {
        handle.setViewportInsets(this.insets);
      }
    }
    clientToWindowPoint(id, clientX, clientY) {
      return this.windows.get(id)?.clientToWindowPoint(clientX, clientY) ?? null;
    }
    wireChrome(instance, handle) {
      for (const button of instance.dom.querySelectorAll("[data-window-action]")) {
        button.addEventListener("click", (event) => {
          event.preventDefault();
          event.stopPropagation();
          switch (button.dataset.windowAction) {
            case "close":
              handle.close();
              break;
            case "minimize":
              handle.minimize();
              break;
            case "maximize":
              if (instance.max) {
                handle.restore();
              } else {
                handle.maximize();
              }
              break;
          }
        });
      }
    }
    bringToFront(id) {
      this.placeInFocusStack(id);
    }
    placeInFocusStack(id) {
      const index = this.focusStack.indexOf(id);
      if (index >= 0) this.focusStack.splice(index, 1);
      this.focusStack.push(id);
    }
    removeFromFocusStack(id) {
      const index = this.focusStack.indexOf(id);
      if (index >= 0) this.focusStack.splice(index, 1);
    }
    remove(id) {
      const handle = this.windows.get(id);
      if (!handle) return;
      this.windows.delete(id);
      handle.markClosed();
    }
  };

  // node_modules/winbox/src/js/template.js
  var template = document.createElement("div");
  template.innerHTML = //'<div class=winbox>' +
  "<div class=wb-header><div class=wb-control><span class=wb-min></span><span class=wb-max></span><span class=wb-full></span><span class=wb-close></span></div><div class=wb-drag><div class=wb-icon></div><div class=wb-title></div></div></div><div class=wb-body></div><div class=wb-n></div><div class=wb-s></div><div class=wb-w></div><div class=wb-e></div><div class=wb-nw></div><div class=wb-ne></div><div class=wb-se></div><div class=wb-sw></div>";
  function template_default(tpl) {
    return (tpl || template).cloneNode(true);
  }

  // node_modules/winbox/src/js/helper.js
  function addListener(node, event, fn, opt) {
    node && node.addEventListener(event, fn, opt || false);
  }
  function removeListener(node, event, fn, opt) {
    node && node.removeEventListener(event, fn, opt || false);
  }
  function preventEvent(event, prevent) {
    event.stopPropagation();
    prevent && /*event.cancelable &&*/
    event.preventDefault();
  }
  function getByClass(root, name) {
    return root.getElementsByClassName(name)[0];
  }
  function addClass(node, classname) {
    node.classList.add(classname);
  }
  function hasClass(node, classname) {
    return node.classList.contains(classname);
  }
  function removeClass(node, classname) {
    node.classList.remove(classname);
  }
  function setStyle(node, style, value) {
    value = "" + value;
    if (node["_s_" + style] !== value) {
      node.style.setProperty(style, value);
      node["_s_" + style] = value;
    }
  }
  function setText(node, value) {
    const textnode = node.firstChild;
    textnode ? textnode.nodeValue = value : node.textContent = value;
  }

  // node_modules/winbox/src/js/winbox.js
  var use_raf = false;
  var stack_min = [];
  var stack_win = [];
  var eventOptions = { "capture": true, "passive": false };
  var eventOptionsPassive = { "capture": true, "passive": true };
  var body;
  var id_counter = 0;
  var index_counter = 10;
  var is_fullscreen;
  var prefix_request;
  var prefix_exit;
  var root_w;
  var root_h;
  var window_clicked;
  function WinBox(params, _title) {
    if (!(this instanceof WinBox)) {
      return new WinBox(params);
    }
    body || setup();
    let id, index, root, tpl, title, icon, mount, html, url, width, height, minwidth, minheight, maxwidth, maxheight, autosize, overflow, x, y, top, left, bottom, right, min, max, hidden, modal, background, border, header, classname, oncreate, onclose, onfocus, onblur, onmove, onresize, onfullscreen, onmaximize, onminimize, onrestore, onhide, onshow, onload;
    if (params) {
      if (_title) {
        title = params;
        params = _title;
      }
      if (typeof params === "string") {
        title = params;
      } else {
        id = params["id"];
        index = params["index"];
        root = params["root"];
        tpl = params["template"];
        title = title || params["title"];
        icon = params["icon"];
        mount = params["mount"];
        html = params["html"];
        url = params["url"];
        width = params["width"];
        height = params["height"];
        minwidth = params["minwidth"];
        minheight = params["minheight"];
        maxwidth = params["maxwidth"];
        maxheight = params["maxheight"];
        autosize = params["autosize"];
        overflow = params["overflow"];
        min = params["min"];
        max = params["max"];
        hidden = params["hidden"];
        modal = params["modal"];
        x = params["x"] || (modal ? "center" : 0);
        y = params["y"] || (modal ? "center" : 0);
        top = params["top"];
        left = params["left"];
        bottom = params["bottom"];
        right = params["right"];
        background = params["background"];
        border = params["border"];
        header = params["header"];
        classname = params["class"];
        oncreate = params["oncreate"];
        onclose = params["onclose"];
        onfocus = params["onfocus"];
        onblur = params["onblur"];
        onmove = params["onmove"];
        onresize = params["onresize"];
        onfullscreen = params["onfullscreen"];
        onmaximize = params["onmaximize"];
        onminimize = params["onminimize"];
        onrestore = params["onrestore"];
        onhide = params["onhide"];
        onshow = params["onshow"];
        onload = params["onload"];
      }
    }
    this.dom = template_default(tpl);
    this.dom.id = this.id = id || "winbox-" + ++id_counter;
    this.dom.className = "winbox" + (classname ? " " + (typeof classname === "string" ? classname : classname.join(" ")) : "") + (modal ? " modal" : "");
    this.dom["winbox"] = this;
    this.window = this.dom;
    this.body = getByClass(this.dom, "wb-body");
    this.header = header || 35;
    stack_win.push(this);
    if (background) {
      this.setBackground(background);
    }
    if (border) {
      setStyle(this.body, "margin", border + (isNaN(border) ? "" : "px"));
    } else {
      border = 0;
    }
    if (header) {
      const node = getByClass(this.dom, "wb-header");
      setStyle(node, "height", header + "px");
      setStyle(node, "line-height", header + "px");
      setStyle(this.body, "top", header + "px");
    }
    if (title) {
      this.setTitle(title);
    }
    if (icon) {
      this.setIcon(icon);
    }
    if (mount) {
      this.mount(mount);
    } else if (html) {
      this.body.innerHTML = html;
    } else if (url) {
      this.setUrl(url, onload);
    }
    top = top ? parse(top, root_h) : 0;
    bottom = bottom ? parse(bottom, root_h) : 0;
    left = left ? parse(left, root_w) : 0;
    right = right ? parse(right, root_w) : 0;
    const viewport_w = root_w - left - right;
    const viewport_h = root_h - top - bottom;
    maxwidth = maxwidth ? parse(maxwidth, viewport_w) : viewport_w;
    maxheight = maxheight ? parse(maxheight, viewport_h) : viewport_h;
    minwidth = minwidth ? parse(minwidth, maxwidth) : 150;
    minheight = minheight ? parse(minheight, maxheight) : this.header;
    if (autosize) {
      (root || body).appendChild(this.body);
      width = Math.max(Math.min(this.body.clientWidth + border * 2 + 1, maxwidth), minwidth);
      height = Math.max(Math.min(this.body.clientHeight + this.header + border + 1, maxheight), minheight);
      this.dom.appendChild(this.body);
    } else {
      width = width ? parse(width, maxwidth) : Math.max(maxwidth / 2, minwidth) | 0;
      height = height ? parse(height, maxheight) : Math.max(maxheight / 2, minheight) | 0;
    }
    x = x ? parse(x, viewport_w, width) : left;
    y = y ? parse(y, viewport_h, height) : top;
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
    this.minwidth = minwidth;
    this.minheight = minheight;
    this.maxwidth = maxwidth;
    this.maxheight = maxheight;
    this.top = top;
    this.right = right;
    this.bottom = bottom;
    this.left = left;
    this.index = index;
    this.overflow = overflow;
    this.min = false;
    this.max = false;
    this.full = false;
    this.hidden = false;
    this.focused = false;
    this.onclose = onclose;
    this.onfocus = onfocus;
    this.onblur = onblur;
    this.onmove = onmove;
    this.onresize = onresize;
    this.onfullscreen = onfullscreen;
    this.onmaximize = onmaximize;
    this.onminimize = onminimize;
    this.onrestore = onrestore;
    this.onhide = onhide;
    this.onshow = onshow;
    if (hidden) {
      this.hide();
    } else {
      this.focus();
    }
    if (index || index === 0) {
      this.index = index;
      setStyle(this.dom, "z-index", index);
      if (index > index_counter) index_counter = index;
    }
    if (max) {
      this.maximize();
    } else if (min) {
      this.minimize();
    } else {
      this.resize().move();
    }
    register(this);
    (root || body).appendChild(this.dom);
    oncreate && oncreate.call(this, params);
  }
  WinBox["new"] = function(params) {
    return new WinBox(params);
  };
  WinBox["stack"] = function() {
    return stack_win;
  };
  var winbox_default = WinBox;
  function parse(num, base, center) {
    if (typeof num === "string") {
      if (num === "center") {
        num = (base - center) / 2 + 0.5 | 0;
      } else if (num === "right" || num === "bottom") {
        num = base - center;
      } else {
        const value = parseFloat(num);
        const unit = "" + value !== num && num.substring(("" + value).length);
        if (unit === "%") {
          num = base / 100 * value + 0.5 | 0;
        } else {
          num = value;
        }
      }
    }
    return num;
  }
  function setup() {
    body = document.body;
    body[prefix_request = "requestFullscreen"] || body[prefix_request = "msRequestFullscreen"] || body[prefix_request = "webkitRequestFullscreen"] || body[prefix_request = "mozRequestFullscreen"] || (prefix_request = "");
    prefix_exit = prefix_request && prefix_request.replace("request", "exit").replace("mozRequest", "mozCancel").replace("Request", "Exit");
    addListener(window, "resize", function() {
      init();
      update_min_stack();
    });
    addListener(body, "mousedown", function(event) {
      window_clicked = false;
    }, true);
    addListener(body, "mousedown", function(event) {
      if (!window_clicked) {
        const stack_length = stack_win.length;
        if (stack_length) {
          for (let i = stack_length - 1; i >= 0; i--) {
            const last_focus = stack_win[i];
            if (last_focus.focused) {
              last_focus.blur();
              break;
            }
          }
        }
      }
    });
    init();
  }
  function register(self) {
    addWindowListener(self, "drag");
    addWindowListener(self, "n");
    addWindowListener(self, "s");
    addWindowListener(self, "w");
    addWindowListener(self, "e");
    addWindowListener(self, "nw");
    addWindowListener(self, "ne");
    addWindowListener(self, "se");
    addWindowListener(self, "sw");
    addListener(getByClass(self.dom, "wb-min"), "click", function(event) {
      preventEvent(event);
      self.min ? self.restore().focus() : self.minimize();
    });
    addListener(getByClass(self.dom, "wb-max"), "click", function(event) {
      preventEvent(event);
      self.max ? self.restore().focus() : self.maximize().focus();
    });
    if (prefix_request) {
      addListener(getByClass(self.dom, "wb-full"), "click", function(event) {
        preventEvent(event);
        self.fullscreen().focus();
      });
    } else {
      self.addClass("no-full");
    }
    addListener(getByClass(self.dom, "wb-close"), "click", function(event) {
      preventEvent(event);
      self.close() || (self = null);
    });
    addListener(self.dom, "mousedown", function(event) {
      window_clicked = true;
    }, true);
    addListener(self.body, "mousedown", function(event) {
      self.focus();
    }, true);
  }
  function remove_min_stack(self) {
    stack_min.splice(stack_min.indexOf(self), 1);
    update_min_stack();
    self.removeClass("min");
    self.min = false;
    self.dom.title = "";
  }
  function update_min_stack() {
    const length = stack_min.length;
    const splitscreen_index = {};
    const splitscreen_length = {};
    for (let i = 0, self, key; i < length; i++) {
      self = stack_min[i];
      key = self.left + ":" + self.top;
      if (splitscreen_length[key]) {
        splitscreen_length[key]++;
      } else {
        splitscreen_index[key] = 0;
        splitscreen_length[key] = 1;
      }
    }
    for (let i = 0, self, key, width; i < length; i++) {
      self = stack_min[i];
      key = self.left + ":" + self.top;
      width = Math.min((root_w - self.left - self.right) / splitscreen_length[key], 250);
      self.resize(width + 1 | 0, self.header, true).move(self.left + splitscreen_index[key] * width | 0, root_h - self.bottom - self.header, true);
      splitscreen_index[key]++;
    }
  }
  function addWindowListener(self, dir) {
    const node = getByClass(self.dom, "wb-" + dir);
    if (!node) return;
    let touch, x, y;
    let raf_timer, raf_move, raf_resize;
    let dblclick_timer = 0;
    addListener(node, "mousedown", mousedown, eventOptions);
    addListener(node, "touchstart", mousedown, eventOptions);
    function loop() {
      raf_timer = requestAnimationFrame(loop);
      if (raf_resize) {
        self.resize();
        raf_resize = false;
      }
      if (raf_move) {
        self.move();
        raf_move = false;
      }
    }
    function mousedown(event) {
      preventEvent(event, true);
      self.focus();
      if (dir === "drag") {
        if (self.min) {
          self.restore();
          return;
        }
        if (!self.hasClass("no-max")) {
          const now = Date.now();
          const diff = now - dblclick_timer;
          dblclick_timer = now;
          if (diff < 300) {
            self.max ? self.restore() : self.maximize();
            return;
          }
        }
      }
      if (
        /*!self.max &&*/
        !self.min
      ) {
        addClass(body, "wb-lock");
        use_raf && loop();
        if ((touch = event.touches) && (touch = touch[0])) {
          event = touch;
          addListener(window, "touchmove", handler_mousemove, eventOptionsPassive);
          addListener(window, "touchend", handler_mouseup, eventOptionsPassive);
        } else {
          addListener(window, "mousemove", handler_mousemove, eventOptionsPassive);
          addListener(window, "mouseup", handler_mouseup, eventOptionsPassive);
        }
        x = event.pageX;
        y = event.pageY;
      }
    }
    function handler_mousemove(event) {
      preventEvent(event);
      if (touch) {
        event = event.touches[0];
      }
      const pageX = event.pageX;
      const pageY = event.pageY;
      const offsetX = pageX - x;
      const offsetY = pageY - y;
      const old_w = self.width;
      const old_h = self.height;
      const old_x = self.x;
      const old_y = self.y;
      let resize_w, resize_h, move_x, move_y;
      if (dir === "drag") {
        if (self.hasClass("no-move")) return;
        self.x += offsetX;
        self.y += offsetY;
        move_x = move_y = 1;
      } else {
        if (dir === "e" || dir === "se" || dir === "ne") {
          self.width += offsetX;
          resize_w = 1;
        } else if (dir === "w" || dir === "sw" || dir === "nw") {
          self.x += offsetX;
          self.width -= offsetX;
          resize_w = 1;
          move_x = 1;
        }
        if (dir === "s" || dir === "se" || dir === "sw") {
          self.height += offsetY;
          resize_h = 1;
        } else if (dir === "n" || dir === "ne" || dir === "nw") {
          self.y += offsetY;
          self.height -= offsetY;
          resize_h = 1;
          move_y = 1;
        }
      }
      if (resize_w) {
        self.width = Math.max(Math.min(self.width, self.maxwidth, root_w - self.x - self.right), self.minwidth);
        resize_w = self.width !== old_w;
      }
      if (resize_h) {
        self.height = Math.max(Math.min(self.height, self.maxheight, root_h - self.y - self.bottom), self.minheight);
        resize_h = self.height !== old_h;
      }
      if (resize_w || resize_h) {
        use_raf ? raf_resize = true : self.resize();
      }
      if (move_x) {
        if (self.max) {
          self.x = (pageX < root_w / 3 ? self.left : pageX > root_w / 3 * 2 ? root_w - self.width - self.right : root_w / 2 - self.width / 2) + offsetX;
        }
        self.x = Math.max(Math.min(self.x, self.overflow ? root_w - 30 : root_w - self.width - self.right), self.overflow ? 30 - self.width : self.left);
        move_x = self.x !== old_x;
      }
      if (move_y) {
        if (self.max) {
          self.y = self.top + offsetY;
        }
        self.y = Math.max(Math.min(self.y, self.overflow ? root_h - self.header : root_h - self.height - self.bottom), self.top);
        move_y = self.y !== old_y;
      }
      if (move_x || move_y) {
        if (self.max) {
          self.restore();
        }
        use_raf ? raf_move = true : self.move();
      }
      if (resize_w || move_x) {
        x = pageX;
      }
      if (resize_h || move_y) {
        y = pageY;
      }
    }
    function handler_mouseup(event) {
      preventEvent(event);
      removeClass(body, "wb-lock");
      use_raf && cancelAnimationFrame(raf_timer);
      if (touch) {
        removeListener(window, "touchmove", handler_mousemove, eventOptionsPassive);
        removeListener(window, "touchend", handler_mouseup, eventOptionsPassive);
      } else {
        removeListener(window, "mousemove", handler_mousemove, eventOptionsPassive);
        removeListener(window, "mouseup", handler_mouseup, eventOptionsPassive);
      }
    }
  }
  function init() {
    const doc = document.documentElement;
    root_w = doc.clientWidth;
    root_h = doc.clientHeight;
  }
  WinBox.prototype.mount = function(src) {
    this.unmount();
    src._backstore || (src._backstore = src.parentNode);
    this.body.textContent = "";
    this.body.appendChild(src);
    return this;
  };
  WinBox.prototype.unmount = function(dest) {
    const node = this.body.firstChild;
    if (node) {
      const root = dest || node._backstore;
      root && root.appendChild(node);
      node._backstore = dest;
    }
    return this;
  };
  WinBox.prototype.setTitle = function(title) {
    const node = getByClass(this.dom, "wb-title");
    setText(node, this.title = title);
    return this;
  };
  WinBox.prototype.setIcon = function(src) {
    const img = getByClass(this.dom, "wb-icon");
    setStyle(img, "background-image", "url(" + src + ")");
    setStyle(img, "display", "inline-block");
    return this;
  };
  WinBox.prototype.setBackground = function(background) {
    setStyle(this.dom, "background", background);
    return this;
  };
  WinBox.prototype.setUrl = function(url, onload) {
    const node = this.body.firstChild;
    if (node && node.tagName.toLowerCase() === "iframe") {
      node.src = url;
    } else {
      this.body.innerHTML = '<iframe src="' + url + '"></iframe>';
      onload && (this.body.firstChild.onload = onload);
    }
    return this;
  };
  WinBox.prototype.focus = function(state) {
    if (state === false) {
      return this.blur();
    }
    if (!this.focused) {
      const stack_length = stack_win.length;
      if (stack_length > 1) {
        for (let i = 1; i <= stack_length; i++) {
          const last_focus = stack_win[stack_length - i];
          if (last_focus.focused) {
            last_focus.blur();
            stack_win.push(stack_win.splice(stack_win.indexOf(this), 1)[0]);
            break;
          }
        }
      }
      setStyle(this.dom, "z-index", ++index_counter);
      this.index = index_counter;
      this.addClass("focus");
      this.focused = true;
      this.onfocus && this.onfocus();
    }
    return this;
  };
  WinBox.prototype.blur = function(state) {
    if (state === false) {
      return this.focus();
    }
    if (this.focused) {
      this.removeClass("focus");
      this.focused = false;
      this.onblur && this.onblur();
    }
    return this;
  };
  WinBox.prototype.hide = function(state) {
    if (state === false) {
      return this.show();
    }
    if (!this.hidden) {
      this.onhide && this.onhide();
      this.hidden = true;
      return this.addClass("hide");
    }
  };
  WinBox.prototype.show = function(state) {
    if (state === false) {
      return this.hide();
    }
    if (this.hidden) {
      this.onshow && this.onshow();
      this.hidden = false;
      return this.removeClass("hide");
    }
  };
  WinBox.prototype.minimize = function(state) {
    if (state === false) {
      return this.restore();
    }
    if (is_fullscreen) {
      cancel_fullscreen();
    }
    if (this.max) {
      this.removeClass("max");
      this.max = false;
    }
    if (!this.min) {
      stack_min.push(this);
      update_min_stack();
      this.dom.title = this.title;
      this.addClass("min");
      this.min = true;
      if (this.focused) {
        this.blur();
        focus_next();
      }
      this.onminimize && this.onminimize();
    }
    return this;
  };
  function focus_next() {
    const stack_length = stack_win.length;
    if (stack_length) {
      for (let i = stack_length - 1; i >= 0; i--) {
        const last_focus = stack_win[i];
        if (!last_focus.min) {
          last_focus.focus();
          break;
        }
      }
    }
  }
  WinBox.prototype.restore = function() {
    if (is_fullscreen) {
      cancel_fullscreen();
    }
    if (this.min) {
      remove_min_stack(this);
      this.resize().move();
      this.onrestore && this.onrestore();
    }
    if (this.max) {
      this.max = false;
      this.removeClass("max").resize().move();
      this.onrestore && this.onrestore();
    }
    return this;
  };
  WinBox.prototype.maximize = function(state) {
    if (state === false) {
      return this.restore();
    }
    if (is_fullscreen) {
      cancel_fullscreen();
    }
    if (this.min) {
      remove_min_stack(this);
    }
    if (!this.max) {
      this.addClass("max").resize(
        root_w - this.left - this.right,
        root_h - this.top - this.bottom,
        true
      ).move(
        this.left,
        this.top,
        true
      );
      this.max = true;
      this.onmaximize && this.onmaximize();
    }
    return this;
  };
  WinBox.prototype.fullscreen = function(state) {
    if (this.min) {
      remove_min_stack(this);
      this.resize().move();
    }
    if (!is_fullscreen || !cancel_fullscreen()) {
      this.body[prefix_request]();
      is_fullscreen = this;
      this.full = true;
      this.onfullscreen && this.onfullscreen();
    } else if (state === false) {
      return this.restore();
    }
    return this;
  };
  function has_fullscreen() {
    return document["fullscreen"] || document["fullscreenElement"] || document["webkitFullscreenElement"] || document["mozFullScreenElement"];
  }
  function cancel_fullscreen() {
    is_fullscreen.full = false;
    if (has_fullscreen()) {
      document[prefix_exit]();
      return true;
    }
  }
  WinBox.prototype.close = function(force) {
    if (this.onclose && this.onclose(force)) {
      return true;
    }
    if (this.min) {
      remove_min_stack(this);
    }
    stack_win.splice(stack_win.indexOf(this), 1);
    this.unmount();
    this.dom.remove();
    this.dom.textContent = "";
    this.dom["winbox"] = null;
    this.body = null;
    this.dom = null;
    this.focused && focus_next();
  };
  WinBox.prototype.move = function(x, y, _skip_update) {
    if (!x && x !== 0) {
      x = this.x;
      y = this.y;
    } else if (!_skip_update) {
      this.x = x ? x = parse(x, root_w - this.left - this.right, this.width) : 0;
      this.y = y ? y = parse(y, root_h - this.top - this.bottom, this.height) : 0;
    }
    setStyle(this.dom, "left", x + "px");
    setStyle(this.dom, "top", y + "px");
    this.onmove && this.onmove(x, y);
    return this;
  };
  WinBox.prototype.resize = function(w, h, _skip_update) {
    if (!w && w !== 0) {
      w = this.width;
      h = this.height;
    } else if (!_skip_update) {
      this.width = w ? w = parse(
        w,
        this.maxwidth
        /*- this.left - this.right*/
      ) : 0;
      this.height = h ? h = parse(
        h,
        this.maxheight
        /*- this.top - this.bottom*/
      ) : 0;
      w = Math.max(w, this.minwidth);
      h = Math.max(h, this.minheight);
    }
    setStyle(this.dom, "width", w + "px");
    setStyle(this.dom, "height", h + "px");
    this.onresize && this.onresize(w, h);
    return this;
  };
  WinBox.prototype.addControl = function(control) {
    const classname = control["class"];
    const image = control.image;
    const click = control.click;
    const index = control.index;
    const node = document.createElement("span");
    const icons = getByClass(this.dom, "wb-control");
    const self = this;
    if (classname) node.className = classname;
    if (image) setStyle(node, "background-image", "url(" + image + ")");
    if (click) node.onclick = function(event) {
      click.call(this, event, self);
    };
    icons.insertBefore(node, icons.childNodes[index || 0]);
    return this;
  };
  WinBox.prototype.removeControl = function(control) {
    control = getByClass(this.dom, control);
    control && control.remove();
    return this;
  };
  WinBox.prototype.addClass = function(classname) {
    addClass(this.dom, classname);
    return this;
  };
  WinBox.prototype.removeClass = function(classname) {
    removeClass(this.dom, classname);
    return this;
  };
  WinBox.prototype.hasClass = function(classname) {
    return hasClass(this.dom, classname);
  };
  WinBox.prototype.toggleClass = function(classname) {
    return this.hasClass(classname) ? this.removeClass(classname) : this.addClass(classname);
  };

  // src/desktop/winbox.ts
  var createWinBox = (options) => new winbox_default(options);

  // src/winbox-preview/entry.ts
  var layer = document.getElementById("window-layer");
  var activeApp = document.getElementById("active-app");
  var clock = document.getElementById("clock");
  if (!layer) throw new Error("WinBox preview layer is missing");
  var api = window.AD;
  function log(message) {
    api?.post({
      version: 1,
      type: "log",
      sessionId: api.sessionId,
      generation: api.generation,
      message: `wm ${message}`
    });
  }
  function setActive(title) {
    if (activeApp) activeApp.textContent = title;
  }
  var manager = new WinBoxWindowManager({
    root: layer,
    factory: createWinBox,
    insets: { top: 31, bottom: 96 }
  });
  manager.open({
    id: "terminal",
    title: "Terminal",
    appName: "Terminal",
    bounds: { x: 72, y: 82, width: 610, height: 380 },
    minWidth: 420,
    minHeight: 240,
    content: `
    <div class="preview-terminal">
      <div class="preview-terminal-head"><span>AirDesk shell</span><span>zsh</span></div>
      <pre>Last login: today on ttys001
airdesk 0.2 \xB7 bundled Wanix workspace

The WinBox parity harness is running inside WKWebView.
Window geometry, focus order, and lifecycle events are live.</pre>
      <div class="preview-prompt"><span>airdesk@studio</span> ~ %</div>
    </div>
  `,
    onFocus: () => {
      setActive("Terminal");
      log("focus terminal");
    },
    onMove: (x, y) => log(`move terminal ${Math.round(x)},${Math.round(y)}`),
    onResize: (width, height) => log(`resize terminal ${Math.round(width)}x${Math.round(height)}`),
    onMinimize: () => log("minimize terminal"),
    onMaximize: () => log("maximize terminal"),
    onRestore: () => log("restore terminal"),
    onBeforeClose: () => {
      log("closing terminal");
      return true;
    },
    onClosed: () => log("closed terminal")
  });
  manager.open({
    id: "notes",
    title: "Notes",
    appName: "Notes",
    bounds: { x: 238, y: 150, width: 560, height: 350 },
    minWidth: 420,
    minHeight: 250,
    content: `
    <div class="preview-notes">
      <aside class="preview-notes-sidebar">
        <strong>Notes</strong>
        <div class="preview-note-item active">WinBox qualification</div>
        <div class="preview-note-item">Input protocol</div>
        <div class="preview-note-item">Display transport</div>
      </aside>
      <div class="preview-note-page">
        <h2>WinBox qualification</h2>
        <p>Upstream WinBox now drives geometry and lifecycle while AirDesk owns the titlebar, glass surfaces, and traffic controls.</p>
        <p>This preview validates the real package in the simulator before the production desktop switches over.</p>
        <div class="preview-pills"><span class="preview-pill">WKWebView</span><span class="preview-pill">AirDesk chrome</span><span class="preview-pill">No fork</span></div>
      </div>
    </div>
  `,
    onFocus: () => {
      setActive("Notes");
      log("focus notes");
    },
    onMove: (x, y) => log(`move notes ${Math.round(x)},${Math.round(y)}`),
    onResize: (width, height) => log(`resize notes ${Math.round(width)}x${Math.round(height)}`),
    onMinimize: () => log("minimize notes"),
    onMaximize: () => log("maximize notes"),
    onRestore: () => log("restore notes"),
    onBeforeClose: () => {
      log("closing notes");
      return true;
    },
    onClosed: () => log("closed notes")
  });
  manager.open({
    id: "welcome",
    title: "Welcome",
    appName: "Welcome",
    bounds: { x: 350, y: 225, width: 470, height: 330 },
    minWidth: 400,
    minHeight: 280,
    content: `
    <div class="preview-welcome">
      <div class="app-icon app-icon-welcome hero"><span class="app-icon-inner"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M12 3.5 14.4 9l5.6.6-4.2 3.8 1.2 5.6L12 16.2 7 19l1.2-5.6L4 9.6 9.6 9 12 3.5Z"/></svg></span></div>
      <h1>AirDesk</h1>
      <p>A macOS-style workspace for iPad, with native input, external displays, and a portable web runtime.</p>
      <div class="preview-pills"><span class="preview-pill">Window manager harness</span><span class="preview-pill">Simulator ready</span></div>
    </div>
  `,
    onFocus: () => {
      setActive("Welcome");
      log("focus welcome");
    },
    onMove: (x, y) => log(`move welcome ${Math.round(x)},${Math.round(y)}`),
    onResize: (width, height) => log(`resize welcome ${Math.round(width)}x${Math.round(height)}`),
    onMinimize: () => log("minimize welcome"),
    onMaximize: () => log("maximize welcome"),
    onRestore: () => log("restore welcome"),
    onBeforeClose: () => {
      log("closing welcome");
      return true;
    },
    onClosed: () => log("closed welcome")
  });
  function updateClock() {
    if (!clock) return;
    clock.textContent = new Intl.DateTimeFormat(void 0, {
      weekday: "short",
      month: "short",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit"
    }).format(/* @__PURE__ */ new Date());
  }
  function updateInsets() {
    const menubar = document.getElementById("menubar");
    const dock = document.getElementById("dock-shell");
    manager.setViewportInsets({
      top: (menubar?.getBoundingClientRect().height ?? 27) + 4,
      bottom: Math.max(0, window.innerHeight - (dock?.getBoundingClientRect().top ?? window.innerHeight - 96) + 10)
    });
  }
  document.body.dataset.wallpaper = "aurora";
  document.body.dataset.appearance = api?.appearance === "light" ? "light" : "dark";
  updateClock();
  updateInsets();
  setInterval(updateClock, 3e4);
  window.addEventListener("resize", updateInsets);
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      api?.viewport();
      api?.ready();
      log("ready");
      api?.state("winbox-preview-ready");
    });
  });
})();
//# sourceMappingURL=winbox-preview.js.map
