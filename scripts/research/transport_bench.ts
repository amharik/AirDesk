interface Scenario {
  id: string;
  name: string;
  purpose?: string;
  evidence_scope?: string;
  candidate: string;
  transport?: string;
  network: string;
  samples?: number;
  payload_bytes?: number;
  steps: string[];
  metrics: string[];
  failure_injection: string[];
  pass: Record<string, string>;
}

interface RunState {
  rtts: number[];
  failures: string[];
  delivered: number;
  reconnectMs: number | null;
  serverReceived: number;
  serverErrors: string[];
}

function argument(name: string): string | undefined {
  const index = Deno.args.indexOf(name);
  return index >= 0 ? Deno.args[index + 1] : undefined;
}

function requiredArgument(name: string): string {
  const value = argument(name);
  if (!value) {
    throw new Error(`missing required argument ${name}`);
  }
  return value;
}

function round(value: number): number {
  return Math.round(value * 1000) / 1000;
}

function percentile(values: number[], rank: number): number | null {
  if (values.length === 0) {
    return null;
  }
  const sorted = [...values].sort((left, right) => left - right);
  const index = Math.ceil((rank / 100) * sorted.length) - 1;
  return round(sorted[Math.max(0, Math.min(index, sorted.length - 1))]);
}

function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
  label: string,
): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} timeout`)), timeoutMs);
  });
  return Promise.race([promise, timeout]).finally(() => {
    if (timer !== undefined) {
      clearTimeout(timer);
    }
  });
}

function makePayload(sequence: number, size: number): Uint8Array {
  const payload = new Uint8Array(size);
  payload.set([0x41, 0x44, 0x46, 0x50], 0);
  const view = new DataView(payload.buffer);
  view.setUint32(4, sequence, true);
  view.setFloat64(8, performance.now(), true);
  return payload;
}

function matchesPayload(bytes: Uint8Array, payload: Uint8Array): boolean {
  if (bytes.length !== payload.length) {
    return false;
  }
  for (let index = 0; index < bytes.length; index += 1) {
    if (bytes[index] !== payload[index]) {
      return false;
    }
  }
  return true;
}

function waitForOpen(socket: WebSocket, timeoutMs: number): Promise<void> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error("open timeout"));
    }, timeoutMs);
    const onOpen = () => {
      cleanup();
      resolve();
    };
    const onError = () => {
      cleanup();
      reject(new Error("open failed"));
    };
    function cleanup(): void {
      clearTimeout(timer);
      socket.removeEventListener("open", onOpen);
      socket.removeEventListener("error", onError);
    }
    socket.addEventListener("open", onOpen);
    socket.addEventListener("error", onError);
  });
}

function echoWebSocket(
  socket: WebSocket,
  payload: Uint8Array,
  timeoutMs: number,
): Promise<number> {
  return new Promise((resolve, reject) => {
    const started = performance.now();
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error("echo timeout"));
    }, timeoutMs);
    const onMessage = (event: MessageEvent) => {
      const data = event.data;
      let bytes: Uint8Array;
      if (data instanceof ArrayBuffer) {
        bytes = new Uint8Array(data);
      } else if (ArrayBuffer.isView(data)) {
        bytes = new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
      } else {
        cleanup();
        reject(new Error("unexpected message type"));
        return;
      }
      if (!matchesPayload(bytes, payload)) {
        cleanup();
        reject(new Error("echo mismatch"));
        return;
      }
      cleanup();
      resolve(performance.now() - started);
    };
    const onError = () => {
      cleanup();
      reject(new Error("socket error"));
    };
    function cleanup(): void {
      clearTimeout(timer);
      socket.removeEventListener("message", onMessage);
      socket.removeEventListener("error", onError);
    }
    socket.addEventListener("message", onMessage);
    socket.addEventListener("error", onError);
    socket.send(payload);
  });
}

function waitForClose(socket: WebSocket, timeoutMs: number): Promise<void> {
  if (socket.readyState === WebSocket.CLOSED) {
    return Promise.resolve();
  }
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      cleanup();
      resolve();
    }, timeoutMs);
    const onClose = () => {
      cleanup();
      resolve();
    };
    function cleanup(): void {
      clearTimeout(timer);
      socket.removeEventListener("close", onClose);
    }
    socket.addEventListener("close", onClose);
  });
}

async function runWebSocket(
  state: RunState,
  sampleCount: number,
  payloadBytes: number,
): Promise<void> {
  const server = Deno.serve({
    hostname: "127.0.0.1",
    port: 0,
    onListen: () => {},
  }, (request) => {
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
      return new Response("websocket required", { status: 426 });
    }
    const { socket, response } = Deno.upgradeWebSocket(request);
    socket.binaryType = "arraybuffer";
    socket.onmessage = (event) => {
      state.serverReceived += 1;
      if (socket.readyState === WebSocket.OPEN) {
        socket.send(event.data);
      }
    };
    socket.onerror = () => {
      state.serverErrors.push("server websocket error");
    };
    return response;
  });

  const port = (server.addr as Deno.NetAddr).port;
  try {
    const socket = new WebSocket(`ws://127.0.0.1:${port}`);
    socket.binaryType = "arraybuffer";
    await waitForOpen(socket, 5000);
    for (let index = 0; index < sampleCount; index += 1) {
      try {
        const rtt = await echoWebSocket(
          socket,
          makePayload(index, payloadBytes),
          5000,
        );
        state.rtts.push(rtt);
        state.delivered += 1;
      } catch (error) {
        state.failures.push(`sample ${index}: ${(error as Error).message}`);
        break;
      }
    }

    const reconnectStarted = performance.now();
    socket.close();
    await waitForClose(socket, 2000);
    const replacement = new WebSocket(`ws://127.0.0.1:${port}`);
    replacement.binaryType = "arraybuffer";
    await waitForOpen(replacement, 5000);
    state.reconnectMs = performance.now() - reconnectStarted;
    try {
      await echoWebSocket(
        replacement,
        makePayload(sampleCount, payloadBytes),
        5000,
      );
    } catch (error) {
      state.failures.push(`reconnect echo: ${(error as Error).message}`);
    }
    replacement.close();
    await waitForClose(replacement, 2000);
  } catch (error) {
    state.failures.push(`transport: ${(error as Error).message}`);
  } finally {
    await server.shutdown();
  }
}

const FRAME_HEADER_BYTES = 4;

function framePayload(payload: Uint8Array): Uint8Array {
  const frame = new Uint8Array(FRAME_HEADER_BYTES + payload.length);
  new DataView(frame.buffer).setUint32(0, payload.length, true);
  frame.set(payload, FRAME_HEADER_BYTES);
  return frame;
}

class StreamFrameReader {
  readonly #reader: ReadableStreamDefaultReader<Uint8Array>;
  #buffer = new Uint8Array(0);

  constructor(reader: ReadableStreamDefaultReader<Uint8Array>) {
    this.#reader = reader;
  }

  async readExactly(length: number): Promise<Uint8Array> {
    while (this.#buffer.length < length) {
      const { value, done } = await this.#reader.read();
      if (done) {
        throw new Error(
          `stream ended after ${this.#buffer.length} of ${length} bytes`,
        );
      }
      if (!value) {
        continue;
      }
      const next = new Uint8Array(this.#buffer.length + value.byteLength);
      next.set(this.#buffer);
      next.set(value, this.#buffer.length);
      this.#buffer = next;
    }
    const result = this.#buffer.slice(0, length);
    this.#buffer = this.#buffer.slice(length);
    return result;
  }
}

async function echoWebTransportStream(
  stream: WebTransportBidirectionalStream,
): Promise<void> {
  const reader = stream.readable.getReader();
  const framed = new StreamFrameReader(reader);
  try {
    const header = await framed.readExactly(FRAME_HEADER_BYTES);
    const length = new DataView(header.buffer).getUint32(0, true);
    if (length > 1048576) {
      throw new Error(`stream frame too large: ${length}`);
    }
    const payload = await framed.readExactly(length);
    const writer = stream.writable.getWriter();
    try {
      await writer.write(framePayload(payload));
      await writer.close();
    } finally {
      writer.releaseLock();
    }
  } finally {
    reader.releaseLock();
  }
}

async function webTransportRoundTrip(
  transport: WebTransport,
  payload: Uint8Array,
  timeoutMs: number,
): Promise<number> {
  const started = performance.now();
  const stream = await withTimeout(
    transport.createBidirectionalStream(),
    timeoutMs,
    "stream open",
  );
  const writer = stream.writable.getWriter();
  try {
    await withTimeout(
      writer.write(framePayload(payload)),
      timeoutMs,
      "stream write",
    );
    await withTimeout(writer.close(), timeoutMs, "stream close");
  } finally {
    writer.releaseLock();
  }
  const reader = stream.readable.getReader();
  const framed = new StreamFrameReader(reader);
  try {
    const header = await withTimeout(
      framed.readExactly(FRAME_HEADER_BYTES),
      timeoutMs,
      "stream read header",
    );
    const length = new DataView(header.buffer).getUint32(0, true);
    if (length !== payload.length) {
      throw new Error(`echo length mismatch: ${length} != ${payload.length}`);
    }
    const bytes = await withTimeout(
      framed.readExactly(length),
      timeoutMs,
      "stream read body",
    );
    if (!matchesPayload(bytes, payload)) {
      throw new Error("echo mismatch");
    }
  } finally {
    reader.releaseLock();
  }
  return performance.now() - started;
}

async function runWebTransport(
  state: RunState,
  sampleCount: number,
  payloadBytes: number,
  certPath: string,
  keyPath: string,
  derPath: string,
): Promise<void> {
  const cert = await Deno.readTextFile(certPath);
  const key = await Deno.readTextFile(keyPath);
  const der = await Deno.readFile(derPath);
  const certHash = await crypto.subtle.digest("SHA-256", der);
  const endpoint = new Deno.QuicEndpoint({ hostname: "127.0.0.1", port: 0 });
  const listener = endpoint.listen({ cert, key, alpnProtocols: ["h3"] });
  const serverTask = (async () => {
    for await (const incoming of listener) {
      (async () => {
        const connection = await incoming.accept();
        const transport = await Deno.upgradeWebTransport(connection);
        await transport.ready;
        const reader = transport.incomingBidirectionalStreams.getReader();
        while (true) {
          const { value: stream, done } = await reader.read();
          if (done) {
            break;
          }
          if (!stream) {
            continue;
          }
          state.serverReceived += 1;
          echoWebTransportStream(stream).catch((error) => {
            state.serverErrors.push(`server stream: ${(error as Error).message}`);
          });
        }
      })().catch((error) => {
        state.serverErrors.push(`server transport: ${(error as Error).message}`);
      });
    }
  })().catch((error) => {
    state.serverErrors.push(`server listener: ${(error as Error).message}`);
  });

  const port = (endpoint.addr as Deno.NetAddr).port;
  const url = `https://127.0.0.1:${port}`;
  const options = {
    serverCertificateHashes: [{ algorithm: "sha-256", value: certHash }],
  };

  try {
    const transport = new WebTransport(url, options);
    await withTimeout(transport.ready, 5000, "webtransport ready");
    for (let index = 0; index < sampleCount; index += 1) {
      try {
        const rtt = await webTransportRoundTrip(
          transport,
          makePayload(index, payloadBytes),
          5000,
        );
        state.rtts.push(rtt);
        state.delivered += 1;
      } catch (error) {
        state.failures.push(`sample ${index}: ${(error as Error).message}`);
        break;
      }
    }

    const reconnectStarted = performance.now();
    transport.close();
    await withTimeout(transport.closed, 5000, "webtransport close").catch(() => {});
    const replacement = new WebTransport(url, options);
    await withTimeout(replacement.ready, 5000, "webtransport reconnect");
    state.reconnectMs = performance.now() - reconnectStarted;
    try {
      await webTransportRoundTrip(
        replacement,
        makePayload(sampleCount, payloadBytes),
        5000,
      );
    } catch (error) {
      state.failures.push(`reconnect echo: ${(error as Error).message}`);
    }
    replacement.close();
    await withTimeout(replacement.closed, 5000, "webtransport close").catch(() => {});
  } catch (error) {
    state.failures.push(`transport: ${(error as Error).message}`);
  } finally {
    endpoint.close();
    await serverTask;
  }
}

const scenarioPath = requiredArgument("--scenario");
const runDir = requiredArgument("--run-dir");
const runId = requiredArgument("--run-id");
const commit = requiredArgument("--commit");
const dirty = requiredArgument("--dirty") === "true";
const hostOs = requiredArgument("--host-os");
const hostArch = requiredArgument("--host-arch");
const denoVersion = requiredArgument("--deno-version");
const requestedSamples = Number(argument("--samples") ?? "0");
const requestedPayloadBytes = Number(argument("--payload-bytes") ?? "0");
const scenario = JSON.parse(await Deno.readTextFile(scenarioPath)) as Scenario;

if (!scenario.id || !scenario.name || !scenario.candidate || !scenario.network) {
  throw new Error("scenario is missing required identity fields");
}

const transport = argument("--transport") ?? scenario.transport ?? "websocket";
const sampleCount = Number.isInteger(requestedSamples) && requestedSamples > 0
  ? requestedSamples
  : scenario.samples ?? 30;

if (!Number.isInteger(sampleCount) || sampleCount < 1 || sampleCount > 10000) {
  throw new Error("samples must be an integer between 1 and 10000");
}

const payloadBytes = Number.isInteger(requestedPayloadBytes) && requestedPayloadBytes > 0
  ? requestedPayloadBytes
  : scenario.payload_bytes ?? 64;

if (!Number.isInteger(payloadBytes) || payloadBytes < 8 || payloadBytes > 1048576) {
  throw new Error("payload bytes must be an integer between 8 and 1048576");
}

const state: RunState = {
  rtts: [],
  failures: [],
  delivered: 0,
  reconnectMs: null,
  serverReceived: 0,
  serverErrors: [],
};

if (transport === "websocket") {
  await runWebSocket(state, sampleCount, payloadBytes);
} else if (transport === "webtransport") {
  await runWebTransport(
    state,
    sampleCount,
    payloadBytes,
    requiredArgument("--cert"),
    requiredArgument("--key"),
    requiredArgument("--der"),
  );
} else {
  throw new Error(`unsupported transport ${transport}`);
}

for (const error of state.serverErrors) {
  state.failures.push(error);
}

const pass = state.failures.length === 0 &&
  state.delivered === sampleCount &&
  state.reconnectMs !== null;

const observations = [
  "Research measurement; not a product commitment.",
  dirty
    ? "Working tree was dirty; preserve the diff with this run."
    : "Working tree was clean.",
  `Transport ${transport}.`,
  `Server received ${state.serverReceived} messages.`,
].join(" ");

const result = {
  schema_version: 1,
  run_id: runId,
  scenario: scenario.id,
  scenario_name: scenario.name,
  evidence_scope: scenario.evidence_scope ?? "harness-smoke",
  candidate: scenario.candidate,
  transport,
  commit,
  dirty,
  build: "research",
  date: new Date().toISOString(),
  environment: {
    controller: `deno ${denoVersion}`,
    host: `macOS ${hostOs} ${hostArch}`,
    browser: "n/a",
    network: scenario.network,
  },
  samples: sampleCount,
  metrics: {
    control_rtt_ms: {
      p50: percentile(state.rtts, 50),
      p95: percentile(state.rtts, 95),
      p99: percentile(state.rtts, 99),
      min: state.rtts.length === 0 ? null : round(Math.min(...state.rtts)),
      max: state.rtts.length === 0 ? null : round(Math.max(...state.rtts)),
    },
    messages_delivered: state.delivered,
    reconnect_ms: state.reconnectMs === null ? null : round(state.reconnectMs),
  },
  diagnostics: {
    server_messages_received: state.serverReceived,
    payload_bytes: payloadBytes,
    timeout_ms: 5000,
  },
  failures: state.failures,
  observations,
  license_notes: transport === "webtransport"
    ? "Deno unstable WebTransport/QUIC runtime only; no added dependency."
    : "Deno runtime and WebSocket standard only; no added dependency.",
  decision: pass ? "trial" : "hold",
  pass,
};

const report = [
  `# ${scenario.id} — ${scenario.name}`,
  "",
  `- Date: ${result.date}`,
  `- Scenario: \`${scenario.id}\` ${scenario.name}`,
  `- Candidate: \`${scenario.candidate}\``,
  `- Transport: \`${transport}\``,
  `- Commit: \`${commit}\`${dirty ? " (dirty)" : ""}`,
  "- Owner: R0 harness",
  `- Environment: ${result.environment.host}; ${result.environment.controller}`,
  `- Network: ${scenario.network}`,
  "- Build configuration: research",
  `- Samples: ${sampleCount}`,
  `- Payload: ${payloadBytes} bytes`,
  `- Result: ${pass ? "pass" : "fail"}`,
  "",
  "## Hypothesis",
  "",
  scenario.purpose ?? "The transport runner can produce a reproducible raw result and report.",
  "",
  "## Method",
  "",
  ...scenario.steps.map((step, index) => `${index + 1}. ${step}`),
  "",
  "## Raw measurements",
  "",
  "```json",
  JSON.stringify(result, null, 2),
  "```",
  "",
  "## Observed failures",
  "",
  state.failures.length === 0
    ? "None."
    : state.failures.map((failure) => `- ${failure}`).join("\n"),
  "",
  "## Recovery behavior",
  "",
  state.reconnectMs === null
    ? "Reconnect was not demonstrated."
    : `Client reconnected in ${round(state.reconnectMs)} ms and completed an echo exchange.`,
  "",
  "## Security notes",
  "",
  "Loopback only. No credentials, terminal output, prompts or workspace contents were captured. The generated TLS certificate is ephemeral and scoped to this run.",
  "",
  "## License/SBOM notes",
  "",
  result.license_notes,
  "",
  "## Comparison to baseline",
  "",
  transport === "websocket"
    ? "Reference baseline only; this run is not a candidate comparison."
    : "Compare with T1 only when host, network and payload are matched.",
  "",
  "## Decision",
  "",
  result.decision,
  "",
  "## What would change the decision",
  "",
  "A failed run keeps the candidate on hold. Candidate evidence requires the scenario corpus on recorded hardware and networks.",
  "",
].join("\n");

await Deno.writeTextFile(`${runDir}/run.json`, `${JSON.stringify(result, null, 2)}\n`);
await Deno.writeTextFile(`${runDir}/report.md`, report);
console.log(`${runDir}/run.json`);
console.log(`${runDir}/report.md`);

if (!pass) {
  Deno.exitCode = 1;
}
