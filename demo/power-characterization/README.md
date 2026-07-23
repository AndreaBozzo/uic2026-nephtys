# Nephtys power characterization — preliminary (2026-07-23)

> **Status: exploratory, NOT camera-ready evidence.**
>
> This is a **single-system** power-vs-throughput characterization of Nephtys on a
> Raspberry Pi 5. It is **not** the definitive experiment and **does not satisfy the
> validity gates** in [`../../RASPBERRY_PI_BENCHMARK.md`](../../RASPBERRY_PI_BENCHMARK.md).
> The definitive result is the controlled **Nephtys-vs-Node-RED** wall-power comparison
> run through [`../comparison/`](../comparison/) (wired Ethernet, interleaved
> multi-slot protocol, mean ± sample SD, event-hash and throttling gates).
>
> Do not cite these numbers in the paper as headline results. They are useful for
> intuition about how Nephtys' own power scales with load, and as a dry run of the
> wall-meter method — nothing more.

## How this deviates from the formal protocol

| Formal protocol (`RASPBERRY_PI_BENCHMARK.md`) | This run |
|---|---|
| Wired Ethernet | **Wi-Fi** (more power, more variance) |
| Nephtys **vs** Node-RED, interleaved 6-slot | Nephtys **alone**, one stream per point |
| Mean ± sample SD over repeated slots | **Single trial** per point (within-window dispersion only) |
| Meter with certified resolution, per-slot energy delta | Shelly Plug S MTR Gen3 (consumer meter; `aenergy` counter quantizes on short windows) |
| Event-sequence hash equality gate | not applicable (single tool) |
| `throttled=0x0` gate | **passed** (`0x0`, active cooler present) |

## Method

- **Instrument:** Shelly Plug S MTR Gen3, measured at the wall socket (includes PSU
  conversion losses). Polled over HTTP RPC (`Switch.GetStatus`) **from the sampling
  host, never from the Pi**, to avoid perturbing the device under test.
- **Windows:** 20 minutes per level, ~470 samples each.
- **Dual method:** average power from the integrated energy counter (`aenergy` delta,
  primary) and from instantaneous `apower` samples (dispersion control). The two
  agreed within 0.5–4.6 % on every 20-minute window; on short (< few minute) windows
  the energy counter is unusable (blocky accumulation) and was rejected.
- **Load:** exact-rate SSE generator on the host; Nephtys pipeline empty, so one
  event = one NATS publish. Harness lives in the main repo:
  [`Nephtys/docs/benchmarks/power/`](https://github.com/AndreaBozzo/Nephtys/tree/main/docs/benchmarks/power).
- **Hardware:** Raspberry Pi 5 (4 GB), USB SSD, active cooler, Wi-Fi; NATS 2.14.3;
  Nephtys built from `main`. CPU 46–55 °C, no throttling.

## Results

Power via the energy method (primary). Raw data: [`results-2026-07-23.csv`](results-2026-07-23.csv).
Figure: [`power-figure.html`](power-figure.html) (open in a browser; a print SVG/PDF
can be derived for the paper if these graduate past exploratory).

| Level | Load | Power (energy) | Δ vs idle | Marginal energy | Latency ingest→publish |
|-------|------|----------------|-----------|-----------------|------------------------|
| L0 · OS only   | idle     | 3.096 W | —        | —         | —       |
| L1 · + NATS    | idle     | 3.099 W | +0.003 W | —         | —       |
| L2 · + Nephtys | idle     | 3.096 W | 0.000 W  | —         | —       |
| L3 · low       | 10 ev/s  | 3.714 W | +0.62 W  | 64 mJ/ev  | 0.41 ms |
| L3 · mid       | 100 ev/s | 3.717 W | +0.62 W  | 6.3 mJ/ev | 0.24 ms |
| L3 · high      | 1000 ev/s| 4.338 W | +1.24 W  | 1.3 mJ/ev | 0.21 ms |

All load runs: ingested bytes = published bytes (zero loss); 168.7 MB / 1.19 M events
at 1000 ev/s, in real time, no backpressure.

## Observations (not claims)

1. Within meter resolution, the idle software stack (NATS + Nephtys) adds no
   measurable power over the bare OS — the ~3.1 W is hardware.
2. The load curve is strongly sublinear: a fixed ~0.6 W activation cost, then a small
   marginal term; energy per event falls ~50× (64 → 1.3 mJ) as throughput rises.
3. No degradation: latency stays ~0.2 ms/event even at 1000 ev/s; CPU 55 °C, load 0.29.

Per the protocol's reporting guidance, absolute wall power is primary; the
idle-baseline deltas are secondary context, **not** a subtracted energy-superiority
claim within meter resolution or trial variability.
