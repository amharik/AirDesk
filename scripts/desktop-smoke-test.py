#!/usr/bin/env python3
import asyncio
import json
import sys
import urllib.request

import websockets


URL = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8123/index.html"


async def main():
    targets = json.loads(await asyncio.to_thread(lambda: urllib.request.urlopen("http://127.0.0.1:9222/json").read()))
    page = next((t for t in targets if t.get("type") == "page"), None)
    async with websockets.connect(page["webSocketDebuggerUrl"], max_size=20_000_000) as ws:
        counter = 0
        pending = {}
        logs = []

        async def call(method, params=None):
            nonlocal counter
            counter += 1
            msg_id = counter
            await ws.send(json.dumps({"id": msg_id, "method": method, "params": params or {}}))
            while msg_id not in pending:
                raw = await asyncio.wait_for(ws.recv(), timeout=90)
                msg = json.loads(raw)
                if "id" in msg:
                    pending[msg["id"]] = msg
                else:
                    method_name = msg.get("method")
                    p = msg.get("params", {})
                    if method_name == "Runtime.consoleAPICalled":
                        args = [str(a.get("value", a.get("description", ""))) for a in p.get("args", [])]
                        line = "console." + p.get("type", "log") + ": " + " ".join(args)
                        logs.append(line)
                        print(line, flush=True)
                    elif method_name == "Log.entryAdded":
                        line = f"log.{p.get('entry', {}).get('level')}: {p.get('entry', {}).get('text')}"
                        logs.append(line)
                        print(line, flush=True)
            result = pending.pop(msg_id)
            if "error" in result:
                raise RuntimeError(result["error"])
            return result.get("result", {})

        async def eval_js(expression):
            result = await call(
                "Runtime.evaluate",
                {"expression": expression, "awaitPromise": True, "returnByValue": True, "userGesture": True},
            )
            if result.get("exceptionDetails"):
                raise RuntimeError(json.dumps(result["exceptionDetails"]))
            return result.get("result", {}).get("value")

        await call("Runtime.enable")
        await call("Log.enable")
        await call("Page.enable")
        await call("Network.enable")
        await call("Network.setCacheDisabled", {"cacheDisabled": True})
        await call("Runtime.discardConsoleEntries")
        await call("Page.navigate", {"url": URL + ("&" if "?" in URL else "?") + "v=" + str(int(__import__("time").time() * 1000))})
        await asyncio.sleep(1)
        ready = await eval_js(
            """
            (async () => {
              const deadline = Date.now() + 60000;
              while (Date.now() < deadline) {
                if (window.AirDeskKernel && window.AirDeskKernel.ready) {
                  try {
                    await Promise.race([window.AirDeskKernel.ready, new Promise((_, r) => setTimeout(() => r(new Error('timeout')), 45000))]);
                    return { ready: true, persistence: window.AirDeskKernel.persistence(), coi: window.crossOriginIsolated };
                  } catch (error) { return { ready: false, error: String(error) }; }
                }
                await new Promise(r => setTimeout(r, 250));
              }
              return { ready: false, error: 'missing' };
            })()
            """
        )
        print("READY", json.dumps(ready), flush=True)
        if not ready or not ready.get("ready"):
            raise SystemExit(1)

        result = await eval_js(
            """
            (async () => {
              const sleep = (ms) => new Promise(r => setTimeout(r, ms));
              document.querySelector('.dock-item[data-app="terminal"]').click();
              const deadline = Date.now() + 30000;
              let term = null;
              while (Date.now() < deadline) {
                term = document.querySelector('wanix-term');
                if (term && term._term) break;
                await sleep(100);
              }
              if (!term || !term._term) return { error: 'terminal missing' };
              const text = () => {
                const buffer = term._term.buffer.active;
                let out = '';
                for (let i = 0; i < buffer.length; i++) {
                  const line = buffer.getLine(i);
                  if (line) out += line.translateToString(true) + '\\n';
                }
                return out;
              };
              const waitFor = async (needle, timeout) => {
                const end = Date.now() + timeout;
                while (Date.now() < end) {
                  if (text().includes(needle)) return true;
                  await sleep(100);
                }
                return false;
              };
              const prompt = await waitFor('rc%', 20000);
              const commands = ['pwd', 'touch created.txt', 'echo hello > redirected.txt', 'echo more >> redirected.txt', 'cat redirected.txt', 'mkdir -p sub', 'cp redirected.txt sub/copied.txt', 'cat sub/copied.txt', 'touch opfs/created.txt', 'echo opfs > opfs/redirected.txt', 'echo more >> opfs/redirected.txt', 'cat opfs/redirected.txt', 'cp opfs/redirected.txt opfs/copied.txt', 'cat opfs/copied.txt', 'ls -l'];
              const steps = [];
              for (const command of commands) {
                const before = text();
                term._term.input(command + '\\n', true);
                await sleep(1000);
                steps.push({ command, output: text().slice(before.length) });
              }
              await sleep(500);
              const root = window.AirDeskKernel.root();
              const files = {};
              for (const path of ['created.txt', 'redirected.txt', 'sub/copied.txt', 'opfs/created.txt', 'opfs/redirected.txt', 'opfs/copied.txt']) {
                try { files[path] = await root.readText(path); }
                catch (error) { files[path] = 'ERROR: ' + error; }
              }
              const expected = {
                'created.txt': '',
                'redirected.txt': 'hello\\nmore\\n',
                'sub/copied.txt': 'hello\\nmore\\n',
                'opfs/created.txt': '',
                'opfs/redirected.txt': 'opfs\\nmore\\n',
                'opfs/copied.txt': 'opfs\\nmore\\n'
              };
              const failures = Object.keys(expected).filter((path) => files[path] !== expected[path]);
              return { prompt, steps, files, expected, failures, text: text() };
            })()
            """
        )
        print("RESULT", json.dumps(result, indent=2), flush=True)
        if not result.get("prompt") or result.get("failures"):
            raise SystemExit(1)
        print("SMOKE PASS", flush=True)


asyncio.run(main())
