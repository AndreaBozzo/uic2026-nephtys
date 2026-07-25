# Raspberry Pi 5 controlled comparison — result notes (2026-07-25)

Definitive device run of the protocol in `RASPBERRY_PI_BENCHMARK.md`. All six measured
slots passed on attempt 1; no attempt was retried and none was discarded. Machine
results are in `runs.csv`, `summary.md`, `summary.json`; per-second samples in
`*.samples.csv`; per-slot Pi logs in `*.remote/`; environment in `metadata.json`.

## Headline

| Metric | Nephtys | Node-RED | Ratio |
|---|---:|---:|---:|
| Tool RSS mean | 19.51 ± 0.07 MB | 128.47 ± 0.44 MB | **6.59×** |
| Tool + NATS RSS mean | 38.85 ± 0.10 MB | 147.07 ± 0.48 MB | 3.79× |
| Tool CPU (100 % = 1 logical CPU) | 0.32 ± 0.00 % | 0.72 ± 0.01 % | 2.23× |
| Latency p50 | 1006.00 ± 0.00 ms | 1009.00 ± 1.00 ms | — |
| Latency p95 | 2009.00 ± 1.00 ms | 2013.00 ± 1.00 ms | — |
| Wall power mean | 3.610 ± 0.005 W | 3.584 ± 0.014 W | 0.99× |
| Wall energy per run | 0.3073 ± 0.0010 Wh | 0.3050 ± 0.0013 Wh | — |
| Energy per input event | 0.0922 ± 0.0003 J | 0.0915 ± 0.0004 J | — |
| SoC temperature mean / peak | 47.26 ± 0.55 / 49.20 ± 1.56 °C | 47.23 ± 0.32 / 49.03 ± 1.27 °C | — |

Mean ± sample SD over three trials per system.

### No energy claim is supported, in either direction

Nephtys measured **0.025 W (0.70 %) higher** than Node-RED — the opposite sign to the
memory result. The difference is smaller than a single quantisation step of the meter's
instantaneous power reading (0.1 W), and is far below the meter's energy quantum
(0.206 Wh, equal to 2.42 W averaged over a 306 s slot). Thermal state, DVFS behaviour,
background daemons, and the measurement harness itself plausibly act at this magnitude
and are not separable with three trials. The correct statement is that **wall power was
indistinguishable between the two systems on this hardware at this load**, and that the
6.59× resident-memory advantage did **not** translate into a measurable wall-power
advantage, because the platform's ~3.0 W idle floor dominates a 40 event/s workload.

## Processing equivalence

Every one of the six measured slots produced the **identical** timestamp-independent
retained-event sequence hash
`d47a65d35398722d073ced6e8412210f2f81fd670dd9d3cc81e78385e5fc1b7a`, and identical output
volumes:
12,000 input events / 2,730,398 input bytes → 155 output messages / 892,955 output
bytes / 7,733 retained events, giving 67.30 % byte and 98.71 % message reduction for
both systems in all trials. These match the x86-64 host comparison
(`results/20260714T133356Z`) exactly, so the pipelines are equivalent across
architectures as well as across systems. An ARM64 golden pre-check (120 events per
system) passed before the measured slots and also produced matching hashes.

Achieved throughput was 40.01–40.04 event/s in every slot, i.e. the intended 40 event/s
paper load, not a saturation test.

## Instrument

- **Meter:** Shelly Plug S MTR Gen3 (S3PL-30110EU), firmware `1.8.99-plugmg3prod0`.
- **Calibration certificate:** none. This is a consumer smart plug.
- **Measurement point:** the wall socket, so the official Raspberry Pi 27 W PSU's
  conversion losses are included. Absolute power covers the complete Pi.
- **Energy resolution:** 0.206 Wh — see below.
- **Sampling:** polled over local HTTP RPC (`Switch.GetStatus`) **from the orchestrator
  host, never from the Pi**, so the measurement does not load the device under test.
  219–220 samples per slot at a 1.37 s mean interval.
- **Mains during the run:** 225.0–231.9 V, mean 229.9 V.

### Why energy is integrated on the host rather than read from the meter's register

This firmware does not accumulate its cumulative `aenergy.total` register continuously.
It flushes in discrete blocks whose size was measured directly during this benchmark:
the register took **11 steps of exactly 0.206–0.207 Wh** across the whole session
(12.099 → 14.372 Wh). At the ~3.6 W load of a slot, one block is ~3.6 minutes of
energy, while a slot accrues only ~0.31 Wh in total. A raw register delta per slot is
therefore quantised at roughly two thirds of the quantity being measured and can
legitimately read 0.000 Wh, which would fail the protocol's positive-energy-delta gate
on a perfectly valid run.

`energy_wh` is consequently a **host-side trapezoidal integral of the meter's own
instantaneous active-power reading** (`apower`, an RMS average over the meter's ~1 s
window), cumulative and monotonic for the entire benchmark; the meter is never reset.
The adapter is `C:\bench\sample-power.ps1` and it logs the raw register alongside every
sample for audit.

**Cross-check.** Over the full session the register advanced 2.273 Wh while the
integration accumulated 2.1165 Wh — agreement within one 0.206 Wh quantum (6.9 %
apparent difference against ±9 % quantisation uncertainty). This reproduces the
agreement seen on the 20-minute windows of the 2026-07-23 exploratory
characterization, and validates the integrated figure against the instrument's own
accumulator. Per-slot, integrated energy and sampled mean power reconcile exactly
(e.g. 0.3068 Wh over a 306.0 s window = 3.610 W), as they must.

## Deviations from `RASPBERRY_PI_BENCHMARK.md`

These are recorded rather than hidden; none affects the comparison, because every one
is common-mode across the two systems, which were interleaved within the same session.

1. **OS image is the desktop build, not Lite.** Raspberry Pi OS reference 2026-06-18
   (Debian 13 trixie, pi-gen `ca8aeed0`, stage4). Mitigated: `lightdm` was stopped for
   the run, Docker and a stale container were stopped, and the Wi-Fi radio was brought
   down so only wired `eth0` carried traffic. Load average was 0.01 and 342 MB of RAM
   was in use before each slot started.
2. **Storage is a USB SSD, not an A2 microSD.** Samsung Portable SSD T7 931.5 GB over
   USB 3.x; no microSD is present in the device. A USB SSD draws more power than a
   microSD, so absolute wall power is higher than a microSD build would show.
3. **Host-side link is Wi-Fi.** The Pi — the device whose power is measured — is wired
   to the router on `eth0`. The orchestrator host has no working wired interface, so it
   reaches the Pi in one hop over Wi-Fi through the same router. This affects only
   latency jitter, which the batching policy dominates by three orders of magnitude:
   batches close on `max_batch_size` = 50 rather than on the 5 s flush interval
   (mean 49.9 events per batch), which at the 25.80 event/s retained rate takes 1.94 s,
   so p95 ≈ 2009 ms is essentially one batch period. It cannot affect the Pi's wall
   power, which is measured at the Pi's own socket.
4. **Consumer meter without a calibration certificate**, and energy obtained by
   integration rather than from the register, as detailed above.
5. **The measurement harness itself runs on the Pi.** Sampling issues one SSH command
   per interval (~1.37 s), so `sshd` fork and crypto cost is included in the reported
   wall power for both systems equally. Absolute power is therefore a slight
   over-estimate of an unmonitored deployment; the comparison is unaffected.

Ambient temperature 26.0 °C, reported by the operator. Governor left at the default
`ondemand`; no overclock. Firmware `ab8a9dde` (2026/01/21).

## Validity gates

| Gate | Result |
|---|---|
| Exactly 12,000 simulator events per retained run | pass, all six slots |
| Exactly one WebSocket client | pass |
| No malformed collector output, no negative latency | pass |
| Positive wall-energy delta | pass (0.3036–0.3085 Wh) |
| No non-zero throttling sample | pass — `throttled` was `0x0` in all 1,316 samples |
| Paired sequence hashes identical in all three trials | pass, and identical across all six slots |
| Undervoltage / process exit / missing power sample | none |
| Summary arithmetic independently recomputed | pass, 24/24 metrics matched `summary.json` exactly |

SoC temperature stayed within 45.0–51.0 °C (mean 47.25 °C) across all samples, so the
active cooler held the part far from its throttle point throughout.

## Harness corrections made to run this

`run-pi-comparison.ps1` had never been executed before today; five defects were fixed,
all in the orchestration rather than the measurement path, plus one genuine measurement
bug in the power adapter:

1. Built `.` instead of `./cmd/nephtys`, so the ARM64 cross-build produced nothing.
2. Polled Nephtys at `/healthz`, which does not exist at commit `c146ee7` and returns
   401 behind the admin token; the endpoint is `/health`.
3. Started the collector with `-create-stream=true` for **both** systems. Nephtys
   creates the `NEPHTYS` JetStream stream with file storage and the collector creates it
   with memory storage, so whichever ran second failed with "stream name already in
   use" — fatal for Nephtys. Now mirrors `run-comparison.ps1`: the tool owns the stream
   for Nephtys slots, the collector owns it for Node-RED slots.
4. Read `run_started_at` / `run_finished_at` from the simulator, which emits
   `started_at` / `completed_at`; run duration therefore threw on an empty string.
5. Called `ssh` without `-n`, so `ssh.exe` forwarded the detached orchestrator's
   never-closing stdin and hung indefinitely *after* the remote command had completed.
   This stalled the first golden slot for eleven minutes and would have been far worse
   inside the measured sampling loop.

Two robustness improvements were also made: the simulator-connection check now waits
for the tool's asynchronous WebSocket attach instead of asserting immediately (the Pi is
slower to attach than the x86-64 host), and non-positive run durations are rejected.

The power-adapter bug is worth recording because it produced plausible-looking but wrong
numbers. Interval state was carried between invocations as an ISO-8601 string;
`ConvertFrom-Json` rehydrates such a string into a `[datetime]`, and coercing that back
to a string for parsing renders it in the host's `it-IT` short format, which silently
drops the sub-second component. Every interval therefore gained the discarded fraction —
about +0.5 s on 1.37 s intervals — and integrated energy was inflated by roughly 30 %
(logged intervals summed to 931 s against 716 s of real time). Time is now carried as
integer UTC ticks, which round-trip through JSON exactly. After the fix, integrated
energy and sampled mean power reconcile to 0.07 %. The affected partial run was
discarded and the whole benchmark was re-run from scratch; no data from it is retained.
