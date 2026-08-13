# Thermal Monitor

A lightweight macOS menu bar app that shows real-time CPU/GPU temperatures, activity,
and power draw for Apple Silicon Macs. No root, no sudo, no helper daemon.

## Features

- **Menu bar icon** — live CPU temperature with color coding (green → orange → red)
- **Popover dashboard** — click the icon for full stats:
  - CPU & GPU die temperature gauges
  - Activity per CPU performance tier, plus the GPU
  - CPU, GPU, DRAM and total package power
  - Battery charge/discharge wattage, charge level, time remaining and adapter rating
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
| Battery power | Pack voltage × current from the `AppleSmartBattery` IO registry entry. Signed: into the battery while charging, out of it while discharging — so on battery it is the whole machine's draw, not just the SoC's. Hidden on machines without a battery. |
| CPU activity | `host_processor_info` tick counters, aggregated per performance tier. Tier names and core counts come from `hw.perflevel*`. |
| GPU activity | `IOReport` GPU performance-state residency. Time outside the `OFF` bucket is the active fraction. |
| Thermal pressure | `ProcessInfo.thermalState`. |

`IOReport` is the same private framework `powermetrics` reads, but unlike `powermetrics`
it does not need elevated privileges — which is why this app needs no sudoers entry and
spawns no subprocesses.

CPU activity deliberately does *not* come from IOReport, even though it sits right next
to the power counters. On some SoCs the per-core `CPU Core Performance States` channels
report the cluster's shared DVFS state replicated across every core, with no idle
accounting: on an M5 Max all six `PCPU*` channels return byte-identical residency with
`IDLE=0` whether the machine is idle or saturated. That reads as a permanent 100%. The
Mach tick counters are public API and correct everywhere, so they are used instead.

There is no clock-speed readout. It would come from weighting those same residencies by
the `voltage-states*` DVFS tables in the IO registry, and those tables are published
with the frequencies zeroed on M5 and later — so the feature could not be verified on
the hardware at hand and was left out rather than shipped as a guess.

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
| `Sources/ThermalMonitor/IOReportSampler.swift` | Energy and GPU residency sampling |
| `Sources/ThermalMonitor/ProcessorLoad.swift` | Per-tier CPU utilization |
| `Sources/ThermalMonitor/BatteryReader.swift` | Battery charge/discharge power |
| `Sources/ThermalMonitor/SensorPoller.swift` | Polling loop |
| `Sources/ThermalMonitor/ContentView.swift` | All UI |

## License

MIT
