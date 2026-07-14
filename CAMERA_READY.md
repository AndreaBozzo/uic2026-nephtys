# IEEE UIC 2026 Camera-Ready Plan

## Submission baseline

- Paper ID: `2646958770`
- Track: Short Paper, 23rd IEEE International Conference on Ubiquitous Intelligence and Computing (UIC 2026), co-located within IEEE Smart World Congress 2026
- Camera-ready deadline: **2026-07-31**
- Internal completion target: **2026-07-25**
- Companion repository submission commit: `fac71735d16f5668b3261ea7e62034aed33e721e`
- Submitted PDF: `paper_nephtys/main.pdf`
- Submitted PDF SHA-256: `3480AB424A68044FC4CCFAB1492833C72F48E67609649FA6237BD03B980CF2C6`
- Nephtys commit identified by the companion README: `14b548b59af784a682184505e9533165d6c84e75`
- Evaluated Nephtys commit: `c146ee7c397fd415194635b0e872d30f3cc87c0a` (the earlier commit predates the runnable `cmd/nephtys` entry point)
- Camera-ready working branch: `camera-ready-2026`

The baseline commit and PDF remain available in Git history. Do not overwrite the baseline PDF until a revised PDF has compiled successfully and been visually inspected.

## Reviewer-action matrix

### Minimum camera-ready scope decision

The paper is already accepted, and Reviewer 2 explicitly presented edge-hardware testing as an optional suggestion. The camera-ready revision will therefore prioritize changes that can be completed reproducibly with the submitted artifact:

1. cautious novelty and positioning claims;
2. a qualitative comparison table based on official documentation;
3. three repetitions of the existing experiments on the documented host;
4. aggregate results with dispersion;
5. an explicit limitation that edge-device and controlled platform comparisons remain future work.

Purchasing a Raspberry Pi and adding a scale sweep remain deferred. The controlled Node-RED comparison was subsequently completed and added to the camera-ready evaluation.

Post-camera-ready evaluation order: run controlled competitor benchmarks first.
Treat Raspberry Pi measurements and feature/scale expansion as optional final
work, undertaken only if time remains and the comparison results justify it.

| Review observation | Camera-ready response | Evidence required | Status |
|---|---|---|---|
| Novelty is moderate and primarily integrative | Position Nephtys as an evaluated systems design point, not a new algorithm or universal platform | Revised abstract, introduction, related work, and conclusion | Drafted |
| The claim that no lightweight solution supports runtime reconfiguration is too strong | Replace exclusivity claims with cautious combination-based wording | Comparison against Node-RED, Redpanda Connect, EdgeX Foundry, and MQTT bridging | Drafted |
| Recent related work is incomplete | Add Redpanda Connect and distinguish stream replacement from Nephtys's in-place pipeline swap | Official project documentation and compact comparison table | Drafted |
| Direct comparison with established platforms is missing | Run an equivalent Node-RED flow against the identical controlled sequence | Three interleaved trials, neutral output collector, matched sequence hashes | Complete |
| Evaluation uses a small deployment | State the limitation explicitly; add a stream-count/load sweep only if it fits the schedule | 20/50/100 stream or equivalent event-rate sweep | Planned, secondary |
| Results come from a single run | Repeat each retained quantitative experiment at least three times | Mean and sample standard deviation from retained raw counters | Complete |
| Actual edge hardware is not evaluated | Remove unsupported Raspberry Pi claims and disclose host-machine evaluation | Revised claims and limitations | Camera-ready draft complete; device run deferred |
| Statistical performance analysis is limited | Report dispersion for the retained throughput, reduction, and RSS metrics | Raw per-run results retained in the companion repository | Complete for camera-ready scope |
| Strong claims in introduction/conclusion | Replace "no solution" and "absent" wording; avoid unmeasured competitor RAM claims | Claim audit | Drafted |

## Claim audit

The submitted manuscript contains the following claims that require correction or qualification:

1. "Traditional message brokers are too heavy" is an overgeneralization and conflicts with the use of NATS. The relevant distinction is between forwarding-only tools, general integration platforms, and a narrowly scoped connector with processing.
2. "No lightweight ... solution" is contradicted by modern stream tools such as Redpanda Connect, which supports runtime stream updates. Nephtys's narrower differentiator is updating a per-stream processing pipeline while leaving its source connector running.
3. "Nephtys runs on constrained edge hardware" is not established by the submitted host-machine experiment. Use "designed for resource-conscious edge deployment" until a device experiment exists.
4. "All connectors implement automatic reconnection" is incorrect. WebSocket and SSE reconnect with exponential backoff, REST polling retries on the next interval, and inbound webhook/gRPC connectors delegate retry to their clients.
5. "Zero-infrastructure" and "no external dependencies" are misleading because NATS is a required process. Use "no separate application database" or "database-free configuration persistence."
6. Competitor RAM figures were not produced under the paper's workload. Remove them until controlled measurements exist.
7. Runtime pipeline updates are transient in the evaluated implementation. Persisted stream registration and event durability must not be phrased as persistence of hot-swapped pipeline state.

## Controlled experiment protocol

### General rules

- Retain raw results for every run; never copy values only from terminal output.
- Record repository commits, binary versions, OS/kernel, CPU model, core count, RAM, power mode, and whether services run natively or in containers.
- Use a fixed simulator seed and identical input sequence for comparative runs.
- Use at least three complete repetitions. Take each initial counter snapshot after the script's 3-second per-phase warm-up.
- Delete registered benchmark streams between phases and repetitions; use counter deltas so continuously increasing process metrics do not contaminate later trials.
- Randomize or alternate system order where practical to reduce thermal and background-load bias.
- Report arithmetic mean and sample standard deviation for each retained quantitative metric.
- Do not compare memory numbers obtained using different boundaries. State whether RSS covers the connector only or the complete required stack.

### Experiment A: repeated Nephtys workload

- Existing synthetic workload: 20 virtual stations, 2 Hz each, 30% duplicate probability, five minutes.
- Existing full pipeline: Transform, Dedup, Threshold, Batch.
- Run baseline and pipeline configurations three times each using the same seed.
- Capture bytes/events ingested and published, per-stage drops, and connector RSS. CPU and processing-latency distributions remain outside the minimum camera-ready scope.
- Treat the five live APIs as ecological validation, not a deterministic comparison. Repeat them if API availability permits, but do not imply identical input across trials.

### Deferred experiment B: actual edge device

- Preferred target: Raspberry Pi 4 or 5; acceptable fallback: a clearly specified low-power mini-PC.
- Run the same synthetic workload locally to avoid WAN variability.
- Measure idle and loaded RSS, mean/peak CPU, median/p95 processing latency, achieved event rate, and bandwidth reduction.
- Do not include Raspberry Pi language in the paper if no such device is tested.

### Completed experiment C: controlled baseline

- Baseline: Node-RED 5.0.1, running natively with its core WebSocket, JSON, Change, RBE, and Join nodes.
- The only custom glue is a NATS JetStream sink using the pinned official JavaScript client packages.
- Both systems process the same deterministic 12,000-event sequence after a discarded 1,200-event warm-up; three measured trials are interleaved.
- A neutral NATS subscriber normalizes the Nephtys envelope, checks timestamp-independent accepted-event sequence hashes, and measures output and latency.
- Tool-only and tool-plus-NATS CPU/RSS boundaries are retained. Redpanda Connect, EdgeX Foundry, and Mosquitto remain qualitative entries.
- The pinned Nephtys revision uses global threshold state despite accepting a `group_by` field; Node-RED's separate-topic behavior is disabled to match the evaluated implementation.

### Deferred experiment D: scale sweep

- Only after A--C are complete.
- Sweep event rate or active stream count at three levels and report throughput, p95 latency, CPU, and RSS.
- Stop before saturation claims unless the load generator itself is independently verified not to be the bottleneck.

## Camera-ready completion checklist

- [ ] Official camera-ready instructions and registration link published and reviewed
- [ ] Author metadata and final proceedings/conference name confirmed
- [x] All absolute novelty claims removed or substantiated
- [x] Related-work comparison table included
- [x] Retained results repeated at least three times
- [x] Unsupported edge-hardware language removed; device experiment deferred
- [x] Controlled quantitative Node-RED comparison included
- [x] Limitations include small scale, single node, delivery semantics, transient hot-swap state, and baseline scope
- [x] Four-page limit checked; extra pages used only by explicit decision
- [x] LaTeX compiles without warnings that affect publication
- [x] Final PDF visually inspected
- [x] Public artifact repository links resolve
- [x] README citation updated from under review to accepted
- [ ] At least one author registration completed when registration opens
- [ ] In-person presenter and travel confirmed

## Retained camera-ready benchmark

- Results: `demo/results/camera-ready-minimum-20260713/runs.csv`
- Aggregate summary: `demo/results/camera-ready-minimum-20260713/summary.md`
- Trials: three 5-minute synthetic baseline/pipeline pairs and three 30-minute live workloads
- Host: Windows 11 Pro 10.0.26200, Intel Core Ultra 7 258V (8 logical processors), 31.5 GiB RAM
- Toolchain: Go 1.26.4 windows/amd64; Docker Engine 29.6.1; NATS container image `nats:latest`
- Mean $\pm$ sample SD: synthetic bytes 67.30 $\pm$ 0.03%, synthetic messages 98.71 $\pm$ 0.00%, live bytes 88.96 $\pm$ 0.34%, live messages 92.71 $\pm$ 0.22%, connector RSS 25.60 $\pm$ 0.26 MB
- One Sensor.Community TCP reset occurred in trial 1 and recovered at the next REST polling interval. The synthetic workload was unaffected. The interrupted third attempt is archived separately and excluded; trial 3 was rerun in full.

## Retained controlled comparison

- Results: `demo/comparison/results/20260714T133356Z/runs.csv`
- Summary: `demo/comparison/results/20260714T133356Z/summary.md`
- All six slots completed on attempt 1; no invalid attempt was retained.
- Paired timestamp-independent accepted-event hashes matched in all three trials.
- Both systems: 67.30% byte reduction, 98.71% message reduction, 7,733 retained events, and 155 output batches.
- Tool RSS mean: Nephtys 19.14 +/- 0.07 MB; Node-RED 109.60 +/- 0.40 MB.
- Tool-plus-NATS RSS mean: Nephtys 27.15 +/- 0.09 MB; Node-RED 117.31 +/- 0.36 MB.
- CPU mean (100% = one logical CPU): Nephtys 0.03 +/- 0.02%; Node-RED 0.31 +/- 0.08%.
- Latency p95: Nephtys 2004.33 +/- 0.58 ms; Node-RED 2006.67 +/- 0.58 ms.
