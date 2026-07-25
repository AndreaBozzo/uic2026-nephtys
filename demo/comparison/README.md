# Controlled Nephtys vs. Node-RED comparison

This benchmark compares Nephtys commit `c146ee7` with Node-RED 5.0.1 on
identical deterministic synthetic sensor sequences. Run it from the companion
repository root:

```powershell
pwsh ./demo/comparison/run-comparison.ps1
```

The default protocol uses three interleaved trials per system. Every fresh tool
process receives a discarded 1,200-event warm-up followed by exactly 12,000
measured events. A dedicated NATS 2.14.3 container is recreated for each slot.

## Processing equivalence

The Node-RED flow uses only core processing nodes: WebSocket, RBE, JSON,
Change/JSONata, a global `deadbandEq` RBE, and Join. A Function node provides
transport glue through the official NATS JavaScript client; it performs no
processing. The neutral collector normalizes Nephtys's outer event envelope
and Node-RED's raw array before counting bytes and events.

At the pinned Nephtys revision, threshold state is global even though the API
accepts `group_by`. The Node-RED deadband therefore has separate-topic behavior
disabled. The exact-dedup RBE is equivalent for this simulator because injected
duplicates immediately repeat the preceding raw payload; it is not a general
replacement for Nephtys's TTL/LRU deduplication semantics.

Every paired trial must produce the same timestamp-independent retained-event
sequence hash. The summarizer fails if the hashes differ.

## Measurement boundaries

- Simulator and neutral collector resources are excluded.
- Tool RSS is Windows `WorkingSet64` sampled once per second.
- Tool CPU uses process CPU-time deltas; 100% equals one logical CPU.
- NATS RSS/CPU comes from Docker stats and is reported separately.
- Complete-stack RSS is tool RSS plus the common NATS container RSS.
- Latency runs from each sensor timestamp to receipt by the local NATS subscriber
  and includes the configured batch delay.
- The fixed 40 events/s workload establishes behavior at the paper load; it is
  not a saturation or maximum-throughput test.

The pinned npm dependency tree currently reports six high-severity audit
findings. Versions are intentionally not auto-upgraded during the experiment;
this environment is local benchmark infrastructure and must not be exposed as
a network service.
