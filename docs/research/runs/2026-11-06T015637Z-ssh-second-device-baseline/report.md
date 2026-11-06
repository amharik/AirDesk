# S2 SSH/tmux Second-Device Handoff Baseline

- **Run:** `2026-11-06T015637Z-ssh-second-device-baseline`
- **Commit:** `3fcac85083ff` (dirty: `false`)
- **Date:** 2026-11-06T01:56:48Z
- **Primary controller:** iPhone 16 Pro (3B46FDF8-1482-4517-99F3-D6EF46A85133) / iOS 18.6 simulator (`3B46FDF8-1482-4517-99F3-D6EF46A85133`)
- **Secondary controller:** iPhone 16 Pro Max (DB9D5BBC-3996-440A-8641-4A236F42A0E0) / iOS 18.6 simulator (`DB9D5BBC-3996-440A-8641-4A236F42A0E0`)
- **Host:** macOS 15.5 x86_64
- **Server:** Linux 6.12.101+deb13-amd64 x86_64 (`sillygirl`, tmux 3.5a)
- **Network:** tailnet; underlay `tailscale-derp`

## Result

| Metric | Value |
| --- | --- |
| Primary heartbeat marker | 9 |
| Secondary heartbeat marker | 109 |
| Heartbeat advanced after handoff | yes |
| Secondary cold connect | 40363 ms |
| Secondary test attempts | 1 |
| Remote process survived | yes |
| Transcript truthful | yes |

The primary simulator attached to a unique tmux session, observed the heartbeat and terminated its app. The secondary simulator then attached to the same session, observed a later heartbeat marker and verified a fresh `terminal.ssh.ready`. `secondary_connect_ms` covers the full cold recovery from `app.launch()` through app startup, preview presentation, SSH attach and the ready event.

## Scope

This is a two-simulator handoff on one Mac, not two physical devices and not a simultaneous two-controller session. It does not prove direct-underlay behavior, long-idle survival or key hygiene across a real handoff.

Raw evidence: `run.json`, `test-summary.log`.
