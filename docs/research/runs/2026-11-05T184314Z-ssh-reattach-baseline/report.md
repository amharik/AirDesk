# S2 SSH/tmux Reattach Baseline

- **Run:** `2026-11-05T184314Z-ssh-reattach-baseline`
- **Commit:** `472537a22a19` (dirty: `false`)
- **Date:** 2026-11-05T18:43:24Z
- **Controller:** iPhone 16 Pro (3B46FDF8-1482-4517-99F3-D6EF46A85133) (Booted)  / iOS 18.6 simulator
- **Host:** macOS 15.5 x86_64
- **Server:** Linux 6.12.101+deb13-amd64 x86_64 (`sillygirl`, `tmux 3.5a`)
- **Network:** tailnet; underlay `tailscale-derp`

## Result

| Metric | Value |
| --- | --- |
| Samples | 3 |
| Reattach p50 | 6891 ms |
| Reattach p95 | 8208 ms |
| Reattach p99 | 8208 ms |
| Reattach min / max | 5345 / 8208 ms |
| Remote process survived | yes, 3/3 |
| Transcript truthful | yes, 3/3 |

The scenario started a remote heartbeat inside the tmux session and backgrounded the app to drop the SSH session, returned to the foreground, waited for a fresh `terminal.ssh.ready`, and verified a new heartbeat marker arrived after each reattach.

## Scope

This is a simulator-to-tailnet baseline. It does not prove physical-device background behavior, a second controller device, a direct-underlay path, or app termination recovery. The Tailscale underlay is recorded separately from the SSH/tmux session.

Raw evidence: `run.json`, `test-summary.log`.
