"use strict";
(() => {
  // src/bridge/bridge.ts
  function isRecord(value) {
    return typeof value === "object" && value !== null;
  }
  function installBridge(win) {
    const handler = win.webkit?.messageHandlers?.airdesk ?? null;
    let query = {};
    try {
      const params = new URLSearchParams(win.location.search);
      params.forEach((value, key) => {
        query[key] = value;
      });
    } catch {
      query = {};
    }
    const sessionId = String(win.AIRDESK_SESSION_ID || query.session || "preview");
    const generation = Number(win.AIRDESK_GENERATION || query.generation || 0);
    const host = String(win.AIRDESK_HOST || query.host || "native");
    const parentOrigin = String(win.AIRDESK_PARENT_ORIGIN || query.parentOrigin || "");
    const runtime = String(win.AIRDESK_RUNTIME || query.runtime || "wanixDesktop");
    let appearance = String(win.AIRDESK_APPEARANCE || query.appearance || "dark");
    const deviceName = String(win.AIRDESK_DEVICE_NAME || query.device || "device");
    const inputHandlers = [];
    const controlHandlers = [];
    let readySent = false;
    let lastViewport = { width: 0, height: 0 };
    let reportedError = false;
    function post(message) {
      if (host === "cast") {
        if (!parentOrigin || win.parent === win) return false;
        try {
          win.parent.postMessage(message, parentOrigin);
          return true;
        } catch {
          return false;
        }
      }
      if (!handler || typeof handler.postMessage !== "function") return false;
      try {
        handler.postMessage(message);
        return true;
      } catch {
        return false;
      }
    }
    function ready() {
      if (readySent) return;
      readySent = true;
      post({
        version: 1,
        type: "ready",
        sessionId,
        generation,
        runtime,
        width: win.innerWidth,
        height: win.innerHeight,
        persistence: win.AirDeskKernel?.persistence ? String(win.AirDeskKernel.persistence()) : "unknown",
        timestamp: Date.now()
      });
    }
    function viewport(width, height) {
      const w = Math.round(width || win.innerWidth);
      const h = Math.round(height || win.innerHeight);
      if (w === lastViewport.width && h === lastViewport.height) return;
      lastViewport = { width: w, height: h };
      post({
        version: 1,
        type: "viewport",
        sessionId,
        generation,
        width: w,
        height: h,
        timestamp: Date.now()
      });
    }
    function notice(text) {
      if (!text) return;
      post({
        version: 1,
        type: "notice",
        sessionId,
        generation,
        message: String(text).slice(0, 180),
        timestamp: Date.now()
      });
    }
    function state(name) {
      if (!name) return;
      post({
        version: 1,
        type: "state",
        sessionId,
        generation,
        message: String(name).slice(0, 80),
        timestamp: Date.now()
      });
    }
    function error(message) {
      if (reportedError) return;
      reportedError = true;
      post({
        version: 1,
        type: "error",
        sessionId,
        generation,
        message: String(message || "Desktop shell error").slice(0, 4e3),
        timestamp: Date.now()
      });
    }
    function ack(event) {
      if (typeof event.seq !== "number") return;
      post({
        version: 1,
        type: "ack",
        sessionId,
        generation,
        seq: event.seq,
        timestamp: Date.now()
      });
    }
    function onInput(handlerFn) {
      if (typeof handlerFn === "function") inputHandlers.push(handlerFn);
    }
    function onControl(handlerFn) {
      if (typeof handlerFn === "function") controlHandlers.push(handlerFn);
    }
    function receiveInput(event) {
      if (!isRecord(event)) return;
      const input = event;
      if (input.sessionId && input.sessionId !== sessionId) return;
      if (input.generation != null && Number(input.generation) !== generation) return;
      try {
        inputHandlers.forEach((handlerFn) => {
          try {
            handlerFn(input);
          } catch (handlerError) {
            console.error(handlerError);
          }
        });
      } finally {
        ack(input);
      }
    }
    function receiveControl(message) {
      if (!isRecord(message)) return;
      const control = message;
      if (control.sessionId && control.sessionId !== sessionId) return;
      if (control.generation != null && Number(control.generation) !== generation) return;
      if (control.type === "appearance" && control.appearance) {
        appearance = String(control.appearance);
      }
      controlHandlers.forEach((handlerFn) => {
        try {
          handlerFn(control);
        } catch (handlerError) {
          console.error(handlerError);
        }
      });
    }
    const bridge = {
      receive: receiveInput,
      receiveControl
    };
    const api = {
      sessionId,
      generation,
      host,
      runtime,
      device: deviceName,
      native: host === "cast" ? Boolean(parentOrigin) : Boolean(handler),
      appearance,
      post,
      ready,
      viewport,
      notice,
      state,
      error,
      onInput,
      onControl
    };
    win.AirDeskBridge = bridge;
    win.AD = api;
    win.addEventListener("error", (event) => {
      if (event?.message) error(event.message);
    });
    win.addEventListener("unhandledrejection", (event) => {
      error(event?.reason ? String(event.reason) : "Unhandled promise rejection");
    });
    let resizeTimer = 0;
    win.addEventListener("resize", () => {
      win.clearTimeout(resizeTimer);
      resizeTimer = win.setTimeout(() => {
        viewport();
      }, 120);
    });
    return bridge;
  }

  // src/bridge/entry.ts
  if (typeof window !== "undefined") installBridge(window);
})();
//# sourceMappingURL=bridge.js.map
