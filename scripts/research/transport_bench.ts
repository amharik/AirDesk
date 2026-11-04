interface Scenario {
  id: string;
  name: string;
  purpose?: string;
  evidence_scope?: string;
  candidate: string;
  network: string;
  samples?: number;
  payload_bytes?: number;
  steps: string[];
  metrics: string[];
  failure_injection: string[];
  pass: Record<string, string>;
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

function makePayload(sequence: number, size: number): Uint8Array {
  const payload = new Uint8Array(size);
  payload.set([0x41, 0x44, 0x46, 0x50], 0);
  const view = new DataView(payload.buffer);
  view.setUint32(4, sequence, true);
  view.setFloat64(8, performance.now(), true);
  return payload;
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

function echoRoundTrip(
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
      if (bytes.length !== payload.length) {
        cleanup();
        reject(new Error("unexpected message size"));
        return;
      }
      for (let index = 0; index < bytes.length; index += 1) {
        if (bytes[index] !== payload[index]) {
          cleanup();
          reject(new Error("echo mismatch"));
          return;
        }
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

const failures: string[] = [];
const rtts: number[] = [];
const serverErrors: string[] = [];
let delivered = 0;
let reconnectMs: number | null = null;
let serverReceived = 0;

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
    serverReceived += 1;
    if (socket.readyState === WebSocket.OPEN) {
      socket.send(event.data);
    }
  };
  socket.onerror = () => {
    serverErrors.push("server websocket error");
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
      const rtt = await echoRoundTrip(socket, makePayload(index, payloadBytes), 5000);
      rtts.push(rtt);
      delivered += 1;
    } catch (error) {
      failures.push(`sample ${index}: ${(error as Error).message}`);
      break;
    }
  }

  const reconnectStarted = performance.now();
  socket.close();
  await waitForClose(socket, 2000);
  const replacement = new WebSocket(`ws://127.0.0.1:${port}`);
  replacement.binaryType = "arraybuffer";
  await waitForOpen(replacement, 5000);
  reconnectMs = performance.now() - reconnectStarted;
  try {
    await echoRoundTrip(replacement, makePayload(sampleCount, payloadBytes), 5000);
  } catch (error) {
    failures.push(`reconnect echo: ${(error as Error).message}`);
  }
  replacement.close();
  await waitForClose(replacement, 2000);
} catch (error) {
  failures.push(`transport: ${(error as Error).message}`);
} finally {
  await server.shutdown();
}

for (const error of serverErrors) {
  failures.push(error);
}

const pass = failures.length === 0 &&
  delivered === sampleCount &&
  reconnectMs !== null;

const observations = [
  "R0 harness smoke; not candidate evidence.",
  dirty
    ? "Working tree was dirty; preserve the diff with this run."
    : "Working tree was clean.",
  `Server received ${serverReceived} messages.`,
].join(" ");

const result = {
  schema_version: 1,
  run_id: runId,
  scenario: scenario.id,
  scenario_name: scenario.name,
  evidence_scope: scenario.evidence_scope ?? "harness-smoke",
  candidate: scenario.candidate,
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
      p50: percentile(rtts, 50),
      p95: percentile(rtts, 95),
      p99: percentile(rtts, 99),
      min: rtts.length === 0 ? null : round(Math.min(...rtts)),
      max: rtts.length === 0 ? null : round(Math.max(...rtts)),
    },
    messages_delivered: delivered,
    reconnect_ms: reconnectMs === null ? null : round(reconnectMs),
  },
  diagnostics: {
    server_messages_received: serverReceived,
    payload_bytes: payloadBytes,
    timeout_ms: 5000,
  },
  failures,
  observations,
  license_notes: "Deno runtime and WebSocket standard only; no added dependency.",
  decision: pass ? "trial" : "hold",
  pass,
};

const report = [
  `# ${scenario.id} — ${scenario.name}`,
  "",
  `- Date: ${result.date}`,
  `- Scenario: \`${scenario.id}\` ${scenario.name}`,
  `- Candidate: \`${scenario.candidate}\``,
  `- Commit: \`${commit}\`${dirty ? " (dirty)" : ""}`,
  "- Owner: R0 harness",
  `- Environment: ${result.environment.host}; ${result.environment.controller}`,
  `- Network: ${scenario.network}`,
  "- Build configuration: research",
  `- Samples: ${sampleCount}`,
  `- Result: ${pass ? "pass" : "fail"}`,
  "",
  "## Hypothesis",
  "",
  "The R0 transport runner can produce a reproducible raw result and report without credentials, external services or workspace contents.",
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
  failures.length === 0 ? "None." : failures.map((failure) => `- ${failure}`).join("\n"),
  "",
  "## Recovery behavior",
  "",
  reconnectMs === null
    ? "Reconnect was not demonstrated."
    : `Client reconnected in ${round(reconnectMs)} ms and completed an echo exchange.`,
  "",
  "## Security notes",
  "",
  "Loopback only. No credentials, terminal output, prompts or workspace contents were captured.",
  "",
  "## License/SBOM notes",
  "",
  "Deno runtime and the WebSocket standard only; no runtime dependency was added.",
  "",
  "## Comparison to baseline",
  "",
  "Baseline self-test only; this run is not a candidate comparison.",
  "",
  "## Decision",
  "",
  result.decision,
  "",
  "## What would change the decision",
  "",
  "A failed smoke keeps R1 blocked. Candidate evidence requires the S1-S8 scenarios on recorded hardware and networks.",
  "",
].join("\n");

await Deno.writeTextFile(`${runDir}/run.json`, `${JSON.stringify(result, null, 2)}\n`);
await Deno.writeTextFile(`${runDir}/report.md`, report);
console.log(`${runDir}/run.json`);
console.log(`${runDir}/report.md`);

if (!pass) {
  Deno.exitCode = 1;
}
