# Raspberry Pi 5 benchmark note

This is optional post-comparison validation. The accepted camera-ready paper is
not blocked by it. Add Pi results to the paper only after all validity gates pass
and the PDF still fits four clean pages.

## Minimum purchase list

- Raspberry Pi 5 with 4 GB RAM.
- Official Raspberry Pi 27 W USB-C power supply.
- Official Raspberry Pi 5 Active Cooler.
- Reputable 32--64 GB A2 microSD card.
- Ethernet cable and microSD reader, if not already available.
- Schuko/Type-L-compatible wall power meter with live watts, cumulative energy
  finer than 0.1 Wh, and preferably a local export/API.

Do not buy NVMe storage, an M.2 HAT, display, keyboard, mouse, 8/16 GB memory, or
an elaborate case for this experiment. Power is measured at the wall so it
includes conversion losses in the official PSU.

## Topology and expected duration

The Pi runs Nephtys or Node-RED plus NATS natively. The Windows machine runs the
controlled simulator, neutral collector, and SSH orchestrator. Connect both by
wired Ethernet and allow Windows TCP ports 9091 (simulator) and SSH outbound.
The Pi exposes 1880, 3002, 4322, and 8322 only on the trusted benchmark LAN.

Each measured run takes about five minutes. Six measured slots, warm-ups,
drains, and restarts require roughly 35--45 minutes after setup and smoke tests.
Latency should remain dominated by the five-second batching policy. Nephtys is
expected to preserve a substantial RSS advantage; wall-power differences may
be small because Pi idle power is part of both complete stacks.

## Device preparation

1. Flash the current Raspberry Pi OS Lite 64-bit image. Record its exact release.
2. Install the Active Cooler, connect the official supply, boot on Ethernet, and
   enable SSH with key authentication.
3. Copy `demo/comparison/pi` to `~/nephtys-pi-bench/pi`, then run:

   ```bash
   chmod +x ~/nephtys-pi-bench/pi/*.sh
   ~/nephtys-pi-bench/pi/setup-pi.sh
   ```

4. Keep default clocks, governor, and official fan policy. Do not overclock.
5. Stop unrelated user workloads. Do not disable networking, SSH, or required
   Raspberry Pi firmware services.
6. Confirm `vcgencmd get_throttled` returns `throttled=0x0` after boot and after
   a short load test.

The setup pins Node.js 24.16.0 and NATS Server 2.14.3. The orchestrator uploads
Nephtys commit `c146ee7`, installs the pinned Node-RED 5.0.1 lockfile on ARM64,
and records model, OS, kernel, firmware, and governor metadata.

## Wall meter adapter

Copy `demo/comparison/pi/power-sample.example.ps1` outside the repository and
replace its body with the selected meter's local API call. Every invocation must
print exactly one JSON object:

```json
{"watts": 5.2, "energy_wh": 123.456}
```

`energy_wh` must be monotonic for the entire benchmark. The adapter must not
reset the meter between samples. Missing samples or a non-positive run energy
delta invalidate the attempt. Record the meter make, model, firmware, energy
resolution, sampling interval, and whether it has a calibration certificate in
the result notes.

## Run

From an elevated PowerShell only if needed for the local firewall rule:

```powershell
pwsh ./demo/comparison/run-pi-comparison.ps1 `
  -PiHost 192.168.1.50 `
  -PiUser pi `
  -WindowsLanIp 192.168.1.20 `
  -PowerSampleScript C:\bench\sample-power.ps1 `
  -PowerMeterModel "meter make/model/firmware" `
  -PowerMeterResolutionWh 0.01 `
  -AmbientTemperatureC 22.5 `
  -OsImageRelease "Raspberry Pi OS Lite image date from Imager"
```

The orchestrator builds ARM64 Nephtys, uploads the pinned projects, starts fresh
native NATS/tool processes per slot, performs the 1,200-event warm-up, and runs
the same interleaved six-slot 12,000-event protocol. It writes metadata, raw
logs, per-second samples, attempts, `runs.csv`, `summary.md`, and `summary.json`
under a timestamped `demo/comparison/results/pi-*` directory.

## Validity and reporting gates

A retained run requires exactly 12,000 simulator events, one WebSocket client,
no malformed output, positive wall-energy delta, and no nonzero throttling
sample. All three Nephtys/Node-RED pairs must have identical timestamp-independent
event-sequence hashes. Failed attempts remain in the result directory and the
slot is retried at most once.

Also reject a run after any undervoltage, process exit, missing power sample,
collector/NATS error, or material background workload. Report tool and NATS CPU
and RSS separately, their combined RSS, temperatures, wall watts, Wh per run,
and joules per input event as mean +/- sample SD. Do not subtract an estimated
idle baseline from primary power results or claim energy superiority within the
meter resolution or trial variability.

If every gate passes, independently check the summary arithmetic. A paper update
is optional and must still produce exactly four pages, zero overfull boxes, zero
undefined citations, and a clean visual inspection of every page.
