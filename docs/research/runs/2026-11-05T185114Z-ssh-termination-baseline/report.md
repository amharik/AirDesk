# S2 SSH/tmux Termination Recovery Baseline

- **Run:** `2026-11-05T185114Z-ssh-termination-baseline`
- **Commit:** `472537a22a19` (dirty: `false`)
- **Date:** 2026-11-05T18:51:24Z
- **Controller:** iPhone 16 Pro (3B46FDF8-1482-4517-99F3-D6EF46A85133) (Booted)  / iOS 18.6 simulator
- **Host:** macOS 15.5 x86_64
- **Server:** Linux 6.12.101+deb13-amd64 x86_64 (`sillygirl`, `tmux 3.5a`)
- **Network:** tailnet; underlay `tailscale-derp`

## Result

| Metric | Value |
| --- | --- |
| Samples | 3 |
| Relaunch recovery p50 | 57555 ms |
| Relaunch recovery p95 | 70799 ms |
| Relaunch recovery p99 | 70799 ms |
| Relaunch recovery min / max | 43513 / 70799 ms |
| Remote process survived | yes, 3/3 |
| Transcript truthful | yes, 3/3 |

The scenario started a remote heartbeat inside the tmux session and terminated the app process, waited, relaunched it, reopened the preview, waited for a fresh `terminal.ssh.ready`, and verified a new heartbeat marker arrived after each relaunch.

## Scope

`relaunch_ms` covers the full cold recovery from `app.launch()` through app startup, preview presentation, SSH reconnect and the first fresh ready event; it is not a transport-only reconnect measurement. This is a simulator-to-tailnet baseline. It does not prove physical-device termination behavior, a second controller device or a direct-underlay path; background behavior is covered separately.

Raw evidence: `run.json`, `test-summary.log`.
