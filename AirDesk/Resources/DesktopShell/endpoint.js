"use strict";
(() => {
  // src/endpoint/loopback.ts
  var LOOPBACK_HOST = "127.0.0.1";
  var BROWSER_ENDPOINT_ROLE = "display";
  var BROWSER_ENDPOINT_TRANSPORT = "websocket";
  var BrowserEndpointError = class extends Error {
    constructor(code, message) {
      super(message);
      this.name = "BrowserEndpointError";
      this.code = code;
    }
  };
  function validPort(port) {
    return Number.isSafeInteger(port) && port > 0 && port <= 65535;
  }
  function parseLoopbackEndpoint(input) {
    let raw;
    if (typeof input === "string") {
      raw = input;
    } else {
      if (!validPort(input.port)) {
        throw new BrowserEndpointError("invalid-port", "invalid loopback port");
      }
      raw = `ws://${LOOPBACK_HOST}:${input.port}`;
    }
    const authority = /^ws:\/\/127\.0\.0\.1(?::([0-9]*))?(?=[/?#]|$)/i.exec(raw);
    if (raw.includes("\\") || !authority) {
      throw new BrowserEndpointError(
        "invalid-loopback-url",
        "browser endpoint must use ws://127.0.0.1:<port>"
      );
    }
    if (!authority[1] || !validPort(Number(authority[1]))) {
      throw new BrowserEndpointError("invalid-port", "loopback port is required");
    }
    let url;
    try {
      url = new URL(raw);
    } catch {
      throw new BrowserEndpointError("invalid-loopback-url", "invalid loopback URL");
    }
    if (url.protocol !== "ws:" || url.hostname !== LOOPBACK_HOST || url.username !== "" || url.password !== "" || url.hash !== "") {
      throw new BrowserEndpointError(
        "invalid-loopback-url",
        "browser endpoint must use ws://127.0.0.1:<port>"
      );
    }
    if (!validPort(Number(url.port)) || url.port === "") {
      throw new BrowserEndpointError("invalid-port", "loopback port is required");
    }
    const port = Number(url.port);
    return {
      url: `ws://${LOOPBACK_HOST}:${port}${url.pathname}${url.search}`,
      port,
      origin: `ws://${LOOPBACK_HOST}:${port}`
    };
  }
  function parseLoopbackOrigin(origin, expectedPort) {
    if (origin.includes("\\")) {
      throw new BrowserEndpointError("invalid-origin", "invalid browser origin");
    }
    const prefix = /^(https?):\/\/127\.0\.0\.1:/.exec(origin);
    if (!prefix) {
      throw new BrowserEndpointError(
        "invalid-origin",
        "browser endpoint origin must be loopback"
      );
    }
    let url;
    try {
      url = new URL(origin);
    } catch {
      throw new BrowserEndpointError("invalid-origin", "invalid browser origin");
    }
    if (url.protocol !== "http:" && url.protocol !== "https:" || url.hostname !== LOOPBACK_HOST || url.username !== "" || url.password !== "" || url.port === "") {
      throw new BrowserEndpointError(
        "invalid-origin",
        "browser endpoint origin must be loopback"
      );
    }
    const port = Number(url.port);
    if (!validPort(port)) {
      throw new BrowserEndpointError("invalid-origin", "invalid browser origin port");
    }
    if (expectedPort !== void 0 && port !== expectedPort) {
      throw new BrowserEndpointError(
        "invalid-origin",
        "browser origin does not match loopback endpoint"
      );
    }
    return {
      origin: `${url.protocol}//${LOOPBACK_HOST}:${port}`,
      port,
      protocol: url.protocol
    };
  }
  function validateSessionToken(token) {
    if (!/^[A-Za-z0-9._~-]{16,4096}$/.test(token)) {
      throw new BrowserEndpointError("invalid-token", "invalid session token");
    }
  }
  function assertBrowserTransport(transport) {
    if (transport.toLowerCase() !== BROWSER_ENDPOINT_TRANSPORT) {
      throw new BrowserEndpointError(
        "unsupported-transport",
        "browser endpoint supports loopback WebSocket only"
      );
    }
  }

  // src/endpoint/client.ts
  var ID_PATTERN = /^[A-Za-z0-9._:-]{1,256}$/;
  var ENDPOINT_ERROR_CODES = /* @__PURE__ */ new Set([
    "unsupported-transport",
    "invalid-loopback-url",
    "invalid-port",
    "invalid-origin",
    "invalid-token",
    "invalid-state",
    "transport-failure",
    "handshake-rejected",
    "protocol-error",
    "workspace-mismatch",
    "display-session-mismatch",
    "connection-closed",
    "remote-asset-rejected"
  ]);
  function isRecord(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }
  function validViewport(value) {
    return isRecord(value) && typeof value.width === "number" && Number.isFinite(value.width) && value.width > 0 && typeof value.height === "number" && Number.isFinite(value.height) && value.height > 0;
  }
  function validIdentifier(value) {
    return ID_PATTERN.test(value);
  }
  function toEndpointError(error) {
    if (error instanceof BrowserEndpointError) return error;
    if (error instanceof Error) {
      return new BrowserEndpointError("transport-failure", error.message);
    }
    return new BrowserEndpointError("transport-failure", "browser endpoint transport failed");
  }
  function errorCode(value) {
    return typeof value === "string" && ENDPOINT_ERROR_CODES.has(value) ? value : "protocol-error";
  }
  var BrowserEndpointClient = class {
    constructor(options) {
      this.role = BROWSER_ENDPOINT_ROLE;
      this.status = "idle";
      this.lastError = null;
      this.registered = false;
      this.connection = null;
      this.unsubscribers = [];
      this.statusHandlers = /* @__PURE__ */ new Set();
      this.errorHandlers = /* @__PURE__ */ new Set();
      this.displayHandlers = /* @__PURE__ */ new Set();
      this.options = options;
      this.state = {
        workspaceId: options.workspaceId,
        displaySessionId: options.displaySessionId,
        viewport: {
          width: options.viewport?.width ?? 0,
          height: options.viewport?.height ?? 0
        },
        focusTarget: options.focusTarget ?? null,
        generation: options.generation ?? 0
      };
    }
    snapshot() {
      return {
        status: this.status,
        role: this.role,
        workspaceId: this.state.workspaceId,
        displaySessionId: this.state.displaySessionId,
        viewport: { ...this.state.viewport },
        focusTarget: this.state.focusTarget,
        generation: this.state.generation,
        connected: this.status === "connected",
        registered: this.registered,
        lastError: this.lastError
      };
    }
    onStatus(handler) {
      this.statusHandlers.add(handler);
      return () => this.statusHandlers.delete(handler);
    }
    onError(handler) {
      this.errorHandlers.add(handler);
      return () => this.errorHandlers.delete(handler);
    }
    onDisplayMessage(handler) {
      this.displayHandlers.add(handler);
      return () => this.displayHandlers.delete(handler);
    }
    async start() {
      if (this.status === "connecting" || this.status === "registering" || this.status === "connected") {
        throw new BrowserEndpointError("invalid-state", "browser endpoint is already active");
      }
      await this.connect();
    }
    async reconnect() {
      if (this.status === "connecting" || this.status === "registering") {
        throw new BrowserEndpointError("invalid-state", "browser endpoint is already connecting");
      }
      if (this.connection) {
        const connection = this.connection;
        this.detach();
        this.connection = null;
        try {
          connection.close(1e3, "reconnect");
        } catch {
          this.lastError = null;
        }
      }
      this.state.generation += 1;
      await this.connect();
    }
    async stop() {
      const connection = this.connection;
      this.detach();
      this.connection = null;
      this.registered = false;
      this.lastError = null;
      if (connection) {
        try {
          connection.close(1e3, "client-stop");
        } catch {
          this.lastError = null;
        }
      }
      this.setStatus("idle");
    }
    setViewport(width, height) {
      if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
        throw new BrowserEndpointError("invalid-state", "invalid viewport");
      }
      this.state.viewport = { width: Math.round(width), height: Math.round(height) };
      this.state.generation += 1;
      this.sendDisplayState("display.viewport");
    }
    setFocus(target) {
      if (target !== null && (target.length === 0 || target.length > 512)) {
        throw new BrowserEndpointError("invalid-state", "invalid focus target");
      }
      this.state.focusTarget = target;
      this.state.generation += 1;
      this.sendDisplayState("display.focus");
    }
    async connect() {
      this.lastError = null;
      this.registered = false;
      this.setStatus("connecting");
      try {
        if (!validIdentifier(this.state.workspaceId)) {
          throw new BrowserEndpointError("invalid-state", "invalid workspace id");
        }
        if (!validIdentifier(this.state.displaySessionId)) {
          throw new BrowserEndpointError("invalid-state", "invalid display session id");
        }
        assertBrowserTransport(BROWSER_ENDPOINT_TRANSPORT);
        validateSessionToken(this.options.token);
        const target = parseLoopbackEndpoint({ port: this.options.port });
        const page = parseLoopbackOrigin(this.options.pageOrigin);
        const connection = await this.options.transport.connect({
          url: target.url,
          origin: page.origin,
          token: this.options.token,
          role: BROWSER_ENDPOINT_ROLE
        });
        this.connection = connection;
        this.unsubscribers = [
          connection.onMessage((message) => this.handleMessage(message)),
          connection.onClose((error) => this.handleClose(error)),
          connection.onError((error) => this.fail(error))
        ];
        this.setStatus("registering");
        connection.send(this.registrationMessage());
      } catch (error) {
        const endpointError = toEndpointError(error);
        this.fail(endpointError);
        throw endpointError;
      }
    }
    registrationMessage() {
      return {
        type: "display.register",
        role: BROWSER_ENDPOINT_ROLE,
        authority: "none",
        workspaceId: this.state.workspaceId,
        displaySessionId: this.state.displaySessionId,
        viewport: { ...this.state.viewport },
        focusTarget: this.state.focusTarget,
        generation: this.state.generation,
        canWriteWorkspace: false
      };
    }
    sendDisplayState(type) {
      if (this.status !== "connected" || !this.connection) return;
      this.connection.send({
        type,
        role: BROWSER_ENDPOINT_ROLE,
        authority: "none",
        workspaceId: this.state.workspaceId,
        displaySessionId: this.state.displaySessionId,
        viewport: { ...this.state.viewport },
        focusTarget: this.state.focusTarget,
        generation: this.state.generation,
        canWriteWorkspace: false
      });
    }
    handleMessage(message) {
      if (!isRecord(message) || typeof message.type !== "string") {
        this.fail(new BrowserEndpointError("protocol-error", "invalid control message"));
        return;
      }
      if (message.type === "display.registered") {
        if (message.workspaceId !== this.state.workspaceId) {
          this.fail(new BrowserEndpointError("workspace-mismatch", "workspace mismatch"));
          return;
        }
        if (message.displaySessionId !== this.state.displaySessionId) {
          this.fail(
            new BrowserEndpointError("display-session-mismatch", "display session mismatch")
          );
          return;
        }
        if (message.authority !== void 0 && message.authority !== "none") {
          this.fail(new BrowserEndpointError("protocol-error", "display authority escalated"));
          return;
        }
        this.registered = true;
        this.setStatus("connected");
        return;
      }
      if (message.type === "display.error") {
        this.fail(
          new BrowserEndpointError(
            errorCode(message.code),
            String(message.message ?? "display session rejected").slice(0, 500)
          )
        );
        return;
      }
      if (!message.type.startsWith("display.")) {
        this.fail(new BrowserEndpointError("protocol-error", "unexpected control message"));
        return;
      }
      if (message.type === "display.update") {
        if (message.workspaceId !== void 0 && message.workspaceId !== this.state.workspaceId) {
          this.fail(new BrowserEndpointError("workspace-mismatch", "workspace mismatch"));
          return;
        }
        if (message.displaySessionId !== void 0 && message.displaySessionId !== this.state.displaySessionId) {
          this.fail(
            new BrowserEndpointError("display-session-mismatch", "display session mismatch")
          );
          return;
        }
        if (validViewport(message.viewport)) {
          this.state.viewport = {
            width: Math.round(message.viewport.width),
            height: Math.round(message.viewport.height)
          };
        }
        if (message.focusTarget === null || typeof message.focusTarget === "string") {
          this.state.focusTarget = message.focusTarget;
        }
        if (typeof message.generation === "number" && Number.isSafeInteger(message.generation) && message.generation >= 0) {
          this.state.generation = message.generation;
        }
      }
      for (const handler of this.displayHandlers) {
        try {
          handler(message);
        } catch {
          this.fail(new BrowserEndpointError("protocol-error", "display handler failed"));
        }
      }
    }
    handleClose(error) {
      this.detach();
      this.connection = null;
      this.registered = false;
      if (this.status === "failed") return;
      this.lastError = error ?? null;
      this.setStatus("disconnected");
      if (error) this.emitError(error);
    }
    fail(error) {
      const connection = this.connection;
      this.detach();
      this.connection = null;
      this.registered = false;
      this.lastError = error;
      this.setStatus("failed");
      this.emitError(error);
      if (connection) {
        try {
          connection.close(1008, error.code);
        } catch {
          this.lastError = error;
        }
      }
    }
    detach() {
      for (const unsubscribe of this.unsubscribers) unsubscribe();
      this.unsubscribers = [];
    }
    emitStatus(status) {
      for (const handler of this.statusHandlers) {
        try {
          handler(status);
        } catch {
          this.lastError = new BrowserEndpointError("protocol-error", "status handler failed");
        }
      }
    }
    emitError(error) {
      for (const handler of this.errorHandlers) {
        try {
          handler(error);
        } catch {
          this.lastError = error;
        }
      }
    }
    setStatus(status) {
      if (this.status === status) return;
      this.status = status;
      this.emitStatus(status);
    }
  };

  // src/endpoint/websocket.ts
  var DEFAULT_ENDPOINT_PATH = "/endpoint";
  function socketUrl(request, path) {
    const endpoint = parseLoopbackEndpoint(request.url);
    const url = new URL(endpoint.url);
    url.pathname = path;
    url.search = "";
    url.hash = "";
    url.searchParams.set("token", request.token);
    return url.toString();
  }
  function closeError(event) {
    if (event.code === 1e3) return null;
    const reason = event.reason.trim();
    return new BrowserEndpointError(
      "connection-closed",
      reason.length > 0 ? reason.slice(0, 500) : `browser endpoint closed (${event.code})`
    );
  }
  var WebSocketControlTransport = class {
    constructor(options = {}) {
      const path = options.path ?? DEFAULT_ENDPOINT_PATH;
      if (!path.startsWith("/") || path.includes("?") || path.includes("#")) {
        throw new BrowserEndpointError("invalid-state", "invalid loopback endpoint path");
      }
      this.path = path;
      this.factory = options.factory ?? ((url) => new WebSocket(url));
    }
    connect(request) {
      try {
        assertBrowserTransport(BROWSER_ENDPOINT_TRANSPORT);
        if (request.role !== BROWSER_ENDPOINT_ROLE) {
          throw new BrowserEndpointError("invalid-state", "invalid browser endpoint role");
        }
        validateSessionToken(request.token);
      } catch (error) {
        return Promise.reject(error);
      }
      let socket;
      try {
        socket = this.factory(socketUrl(request, this.path));
      } catch (error) {
        return Promise.reject(
          error instanceof BrowserEndpointError ? error : new BrowserEndpointError("transport-failure", "browser endpoint WebSocket failed")
        );
      }
      return new Promise((resolve, reject) => {
        let opened = false;
        let closed = false;
        let messageHandlers = [];
        let closeHandlers = [];
        let errorHandlers = [];
        const emitError = (error) => {
          for (const handler of [...errorHandlers]) {
            try {
              handler(error);
            } catch {
            }
          }
        };
        const emitClose = (error) => {
          for (const handler of [...closeHandlers]) {
            try {
              handler(error);
            } catch {
            }
          }
        };
        const detach = () => {
          socket.removeEventListener("message", onMessage);
          socket.removeEventListener("close", onClose);
          socket.removeEventListener("error", onError);
        };
        const onOpen = () => {
          if (closed) return;
          opened = true;
          socket.removeEventListener("open", onOpen);
          resolve(connection);
        };
        const onMessage = (event) => {
          if (typeof event.data !== "string") {
            emitError(new BrowserEndpointError("protocol-error", "browser endpoint requires text messages"));
            return;
          }
          let message;
          try {
            message = JSON.parse(event.data);
          } catch {
            emitError(new BrowserEndpointError("protocol-error", "invalid browser endpoint message"));
            return;
          }
          for (const handler of [...messageHandlers]) {
            try {
              handler(message);
            } catch {
              emitError(new BrowserEndpointError("protocol-error", "browser endpoint message handler failed"));
            }
          }
        };
        const onError = () => {
          const error = new BrowserEndpointError("transport-failure", "browser endpoint WebSocket failed");
          if (!opened) {
            closed = true;
            detach();
            reject(error);
            return;
          }
          emitError(error);
        };
        const onClose = (event) => {
          if (closed) return;
          closed = true;
          detach();
          const error = closeError(event);
          if (!opened) {
            reject(error ?? new BrowserEndpointError("handshake-rejected", "browser endpoint handshake failed"));
            return;
          }
          emitClose(error ?? void 0);
        };
        const connection = {
          send(message) {
            if (closed || !opened) {
              throw new BrowserEndpointError("invalid-state", "browser endpoint is not connected");
            }
            socket.send(JSON.stringify(message));
          },
          close(code = 1e3, reason = "client-stop") {
            if (closed) return;
            socket.close(code, reason);
          },
          onMessage(handler) {
            messageHandlers.push(handler);
            return () => {
              messageHandlers = messageHandlers.filter((item) => item !== handler);
            };
          },
          onClose(handler) {
            closeHandlers.push(handler);
            return () => {
              closeHandlers = closeHandlers.filter((item) => item !== handler);
            };
          },
          onError(handler) {
            errorHandlers.push(handler);
            return () => {
              errorHandlers = errorHandlers.filter((item) => item !== handler);
            };
          }
        };
        socket.addEventListener("open", onOpen);
        socket.addEventListener("message", onMessage);
        socket.addEventListener("close", onClose);
        socket.addEventListener("error", onError);
      });
    }
  };

  // src/endpoint/page.ts
  var ID_PATTERN2 = /^[A-Za-z0-9._:-]{1,256}$/;
  var MAX_AUTO_RECONNECTS = 8;
  function identifier(value, name) {
    if (!value || !ID_PATTERN2.test(value)) {
      throw new BrowserEndpointError("invalid-state", `invalid ${name}`);
    }
    return value;
  }
  function readPresentationConfig(location) {
    const params = new URLSearchParams(location.search);
    const endpoint = parseLoopbackEndpoint(params.get("endpoint") ?? "");
    const endpointURL = new URL(endpoint.url);
    const token = params.get("token") ?? "";
    validateSessionToken(token);
    const page = parseLoopbackOrigin(location.origin);
    return {
      endpoint: endpoint.url,
      endpointPath: endpointURL.pathname || "/endpoint",
      port: endpoint.port,
      token,
      workspaceId: identifier(params.get("workspace"), "workspace id"),
      displaySessionId: identifier(params.get("display"), "display session id"),
      pageOrigin: page.origin
    };
  }
  function statusLabel(status) {
    switch (status) {
      case "idle":
        return "Idle";
      case "connecting":
        return "Connecting";
      case "registering":
        return "Registering";
      case "connected":
        return "Connected";
      case "disconnected":
        return "Disconnected";
      case "failed":
        return "Failed";
    }
  }
  function requireElement(document, id) {
    const element = document.getElementById(id);
    if (!element) {
      throw new Error(`missing endpoint page element: ${id}`);
    }
    return element;
  }
  function startEndpointPage(window2, transport) {
    const config = readPresentationConfig(window2.location);
    const document = window2.document;
    const client = new BrowserEndpointClient({
      port: config.port,
      pageOrigin: config.pageOrigin,
      token: config.token,
      workspaceId: config.workspaceId,
      displaySessionId: config.displaySessionId,
      transport: transport ?? new WebSocketControlTransport({ path: config.endpointPath }),
      viewport: {
        width: Math.max(1, Math.round(window2.innerWidth)),
        height: Math.max(1, Math.round(window2.innerHeight))
      }
    });
    const status = requireElement(document, "endpoint-status");
    const detail = requireElement(document, "endpoint-detail");
    const error = requireElement(document, "endpoint-error");
    const reconnect = requireElement(document, "endpoint-reconnect");
    const workspace = requireElement(document, "endpoint-workspace");
    const display = requireElement(document, "endpoint-display");
    const endpoint = requireElement(document, "endpoint-url");
    const indicator = requireElement(document, "endpoint-indicator");
    let disposed = false;
    let reconnectTimer = null;
    let reconnectAttempts = 0;
    const update = () => {
      const snapshot = client.snapshot();
      status.textContent = statusLabel(snapshot.status);
      detail.textContent = snapshot.status === "connected" ? "Display registered. Waiting for workspace surface updates." : snapshot.status === "registering" ? "Waiting for the loopback host to confirm this display session." : snapshot.status === "connecting" ? "Dialing the loopback host." : "The display session is not connected.";
      error.textContent = snapshot.lastError ? `${snapshot.lastError.code}: ${snapshot.lastError.message}` : "";
      reconnect.disabled = snapshot.status === "connecting" || snapshot.status === "registering" || snapshot.status === "connected";
      workspace.textContent = snapshot.workspaceId;
      display.textContent = snapshot.displaySessionId;
      endpoint.textContent = config.endpoint;
      indicator.dataset.status = snapshot.status;
    };
    const scheduleReconnect = () => {
      if (disposed || reconnectTimer !== null || reconnectAttempts >= MAX_AUTO_RECONNECTS) return;
      const delay = Math.min(5e3, 500 * 2 ** reconnectAttempts);
      reconnectAttempts += 1;
      reconnectTimer = window2.setTimeout(() => {
        reconnectTimer = null;
        if (disposed) return;
        void client.reconnect().catch(() => {
          update();
          scheduleReconnect();
        });
      }, delay);
    };
    const reconnectNow = async () => {
      if (disposed) return;
      if (reconnectTimer !== null) {
        window2.clearTimeout(reconnectTimer);
        reconnectTimer = null;
      }
      reconnectAttempts = 0;
      try {
        await client.reconnect();
      } catch {
        update();
        scheduleReconnect();
      }
    };
    const updateViewport = () => {
      try {
        client.setViewport(
          Math.max(1, Math.round(window2.innerWidth)),
          Math.max(1, Math.round(window2.innerHeight))
        );
      } catch {
      }
    };
    const onFocusIn = (event) => {
      const target = event.target;
      const name = target?.getAttribute("data-focus-target") ?? target?.id ?? target?.tagName.toLowerCase() ?? "document";
      try {
        client.setFocus(name.slice(0, 512));
      } catch {
      }
    };
    const onFocusOut = () => {
      try {
        client.setFocus(null);
      } catch {
      }
    };
    const onPageHide = () => {
      dispose();
    };
    const subscriptions = [
      client.onStatus((next) => {
        if (next === "connected") reconnectAttempts = 0;
        update();
        if (next === "disconnected" || next === "failed") scheduleReconnect();
      }),
      client.onError(() => update())
    ];
    const ResizeObserverConstructor = window2.ResizeObserver;
    const resizeObserver = typeof ResizeObserverConstructor === "function" ? new ResizeObserverConstructor(() => updateViewport()) : null;
    resizeObserver?.observe(document.documentElement);
    window2.addEventListener("resize", updateViewport);
    document.addEventListener("focusin", onFocusIn);
    document.addEventListener("focusout", onFocusOut);
    window2.addEventListener("pagehide", onPageHide);
    reconnect.addEventListener("click", () => {
      void reconnectNow();
    });
    function dispose() {
      if (disposed) return;
      disposed = true;
      if (reconnectTimer !== null) {
        window2.clearTimeout(reconnectTimer);
        reconnectTimer = null;
      }
      for (const unsubscribe of subscriptions) unsubscribe();
      resizeObserver?.disconnect();
      window2.removeEventListener("resize", updateViewport);
      document.removeEventListener("focusin", onFocusIn);
      document.removeEventListener("focusout", onFocusOut);
      window2.removeEventListener("pagehide", onPageHide);
      void client.stop();
    }
    update();
    void client.start().catch(() => {
      update();
    });
    return { client, config, dispose };
  }

  // src/endpoint/entry.ts
  function showFatal(error) {
    const document = window.document;
    const status = document.getElementById("endpoint-status");
    const detail = document.getElementById("endpoint-detail");
    const message = document.getElementById("endpoint-error");
    const indicator = document.getElementById("endpoint-indicator");
    if (status) status.textContent = "Unavailable";
    if (detail) detail.textContent = "This display link is incomplete or invalid.";
    if (message) {
      message.textContent = error instanceof Error ? error.message : "The browser endpoint could not be started.";
    }
    if (indicator) indicator.dataset.status = "failed";
  }
  try {
    startEndpointPage(window);
  } catch (error) {
    showFatal(error);
  }
})();
//# sourceMappingURL=endpoint.js.map
