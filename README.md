# Thermal Monitor

A lightweight macOS menu bar app that shows real-time CPU/GPU temperatures, activity,
and power draw for Apple Silicon Macs. No root, no sudo, no helper daemon.

## Features

- **Menu bar icon** — live CPU temperature with color coding (green → orange → red)
- **Popover dashboard** — click the icon for full stats:
  - CPU & GPU die temperature gauges
  - Per-cluster activity (efficiency / performance / GPU), with average clock speed on
    the SoCs that publish a DVFS table
  - CPU, GPU, DRAM and total package power
  - System thermal pressure
- **Open at Login** toggle
- Auto-refreshes every 2 seconds

## Requirements

- macOS 13 Ventura or later
- Apple Silicon Mac

## Install

```bash
./build_app.sh
```

That builds `ThermalMonitor.app`, installs it to `/Applications`, and launches it. Pass
`--no-install` to just produce the bundle in the working directory.

The app is ad-hoc signed, so it runs without an Apple Developer account and without the
right-click → Open dance. To uninstall, quit it from the popover and delete
`/Applications/ThermalMonitor.app`.

## How it works

| Reading | Source |
|---|---|
| Temperatures | SMC over IOKit. Every `T*` key is enumerated once at startup and the ones that read back as a plausible temperature are kept, so `Tp*` (performance cluster), `Te*` (efficiency cluster) and `Tg*` (GPU) are found without a hardcoded per-SoC key list. |
| Power | `IOReport` "Energy Model" energy counters, differenced between samples. |
| Activity | `IOReport` CPU/GPU performance-state residencies. Time outside the `DOWN`/`IDLE`/`OFF` buckets is the active fraction. |
| Clock speed | Residencies weighted by the `voltage-states*` DVFS tables in the IO registry. |
| Thermal pressure | `ProcessInfo.thermalState`. |

`IOReport` is the same private framework `powermetrics` reads, but unlike `powermetrics`
it does not need elevated privileges — which is why this app needs no sudoers entry and
spawns no subprocesses.

The `voltage-states*` frequency tables are zeroed out on some newer machines (M5 and
later). There the clock readout is simply omitted; activity and power are unaffected.

## Privacy & Security

- No network connections
- No data collection
- No privileged helper, no kernel extension
- Only reads local hardware sensors

## Contributing

PRs welcome. Key files:

| File | Purpose |
|------|---------|
| `Sources/CSensors/SMC.c` | IOKit SMC reader |
| `Sources/CSensors/IOReport.c` | `libIOReport` symbol resolution and wrappers |
| `Sources/ThermalMonitor/SMCReader.swift` | Sensor key discovery |
| `Sources/ThermalMonitor/IOReportSampler.swift` | Energy and residency sampling |
| `Sources/ThermalMonitor/ClockTables.swift` | DVFS table lookup |
| `Sources/ThermalMonitor/SensorPoller.swift` | Polling loop |
| `Sources/ThermalMonitor/ContentView.swift` | All UI |

## License

MIT
