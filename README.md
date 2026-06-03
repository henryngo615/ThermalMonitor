# Thermal Monitor

A lightweight macOS menu bar app that shows real-time CPU/GPU temperatures, clock speeds, and power draw for Apple Silicon MacBooks.

![Menu bar showing 48° CPU temp](docs/menubar.png)

## Features

- **Menu bar icon** — live CPU temperature with color coding (green → orange → red)
- **Popover dashboard** — click the icon for full stats:
  - CPU & GPU temperature gauges
  - Per-cluster clock speeds (E-Cluster / P-Cluster / GPU)
  - CPU, GPU, and package power draw
  - Thermal pressure level
- **Auto-refreshes** every 3 seconds
- Works on all Apple Silicon MacBooks (M1 · M2 · M3 · M4)

## Requirements

- macOS 13 Ventura or later
- Apple Silicon Mac (M1 / M2 / M3 / M4 and variants)

## Installation

### Option A — Download binary (recommended)

1. Download the latest `ThermalMonitor.tar.gz` from [Releases](../../releases)
2. Extract and move `ThermalMonitor` to `/Applications` or anywhere you like
3. Double-click to run (you may need to right-click → Open the first time)
4. Follow the one-time sudo setup below

### Option B — Build from source

```bash
git clone https://github.com/yourname/ThermalMonitor
cd ThermalMonitor
swift build -c release
# Binary is at .build/release/ThermalMonitor
```

## One-time sudo setup

Temperature sensors require `powermetrics`, which needs elevated privileges. Run this **once** in Terminal:

```bash
echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/powermetrics" | sudo tee /etc/sudoers.d/powermetrics
```

This grants only `powermetrics` passwordless access — nothing else. The app will work without this (showing SMC temps only, no clock/power data), but this unlocks the full dashboard.

## Auto-launch at login

```bash
# Add to Login Items via System Settings → General → Login Items
# Or use launchd:
cp com.thermalmonitor.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.thermalmonitor.plist
```

## How it works

- **Temperatures** — read directly from the SMC (System Management Controller) via IOKit. Dynamically discovers all `Tp*` (P-cluster), `Te*` (E-cluster), and `Tg*` (GPU) keys, so it works across M1–M4 without hardcoded key lists.
- **Clock speeds & power** — sampled via `sudo powermetrics` in plist mode, parsed in-process every 3 seconds on a background thread.
- No daemons, no kernel extensions, no network access.

## Privacy & Security

- No network connections
- No data collection
- Only accesses local hardware sensors
- Source is fully auditable

## Contributing

PRs welcome. Key files:

| File | Purpose |
|------|---------|
| `Sources/CSMC/CSMC.c` | IOKit SMC reader (C) |
| `Sources/ThermalMonitor/SMCReader.swift` | Key discovery & Swift wrapper |
| `Sources/ThermalMonitor/PowerMetricsParser.swift` | powermetrics poller |
| `Sources/ThermalMonitor/ContentView.swift` | All UI |

## License

MIT
