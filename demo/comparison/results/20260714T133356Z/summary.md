# Controlled Nephtys vs. Node-RED comparison

Valid trials: 3 per system. Values are arithmetic mean +/- sample SD.
The timestamp-independent retained-event sequence matched between systems in every paired trial.

| Metric | Nephtys | Node-RED |
|---|---:|---:|
| Byte reduction (%) | 67.30 +/- 0.00 | 67.30 +/- 0.00 |
| Message reduction (%) | 98.71 +/- 0.00 | 98.71 +/- 0.00 |
| Retained events | 7733.00 +/- 0.00 | 7733.00 +/- 0.00 |
| Throughput (events/s) | 40.00 +/- 0.00 | 40.03 +/- 0.00 |
| Tool RSS mean (MB) | 19.14 +/- 0.07 | 109.60 +/- 0.40 |
| Tool RSS peak (MB) | 19.82 +/- 0.08 | 121.70 +/- 0.32 |
| Tool CPU mean (% of one logical CPU) | 0.03 +/- 0.02 | 0.31 +/- 0.08 |
| NATS RSS mean (MB) | 8.01 +/- 0.12 | 7.71 +/- 0.05 |
| NATS CPU mean (%) | 2.61 +/- 0.16 | 2.66 +/- 0.16 |
| Tool + NATS RSS mean (MB) | 27.15 +/- 0.09 | 117.31 +/- 0.36 |
| Latency p50 (ms) | 1004.33 +/- 0.58 | 1006.33 +/- 0.58 |
| Latency p95 (ms) | 2004.33 +/- 0.58 | 2006.67 +/- 0.58 |

## Per-run results

- Order 1: nephtys trial 1 - bytes 67.30%, messages 98.71%, RSS 19.18 MB, CPU 0.04%, p95 2004.00 ms.
- Order 2: nodered trial 1 - bytes 67.30%, messages 98.71%, RSS 109.21 MB, CPU 0.26%, p95 2007.00 ms.
- Order 3: nodered trial 2 - bytes 67.30%, messages 98.71%, RSS 110.02 MB, CPU 0.26%, p95 2006.00 ms.
- Order 4: nephtys trial 2 - bytes 67.30%, messages 98.71%, RSS 19.18 MB, CPU 0.03%, p95 2005.00 ms.
- Order 5: nephtys trial 3 - bytes 67.30%, messages 98.71%, RSS 19.05 MB, CPU 0.01%, p95 2004.00 ms.
- Order 6: nodered trial 3 - bytes 67.30%, messages 98.71%, RSS 109.58 MB, CPU 0.40%, p95 2007.00 ms.
