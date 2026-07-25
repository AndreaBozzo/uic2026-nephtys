# Raspberry Pi 5 controlled comparison

Three valid trials per system; arithmetic mean +/- sample SD.

| Metric | Nephtys | Node-RED |
|---|---:|---:|
| Byte reduction | 67.30 +/- 0.00 % | 67.30 +/- 0.00 % |
| Message reduction | 98.71 +/- 0.00 % | 98.71 +/- 0.00 % |
| Tool RSS mean | 19.51 +/- 0.07 MB | 128.47 +/- 0.44 MB |
| Tool + NATS RSS mean | 38.85 +/- 0.10 MB | 147.07 +/- 0.48 MB |
| Tool CPU | 0.32 +/- 0.00 % one logical CPU | 0.72 +/- 0.01 % one logical CPU |
| Latency p50 | 1006.00 +/- 0.00 ms | 1009.00 +/- 1.00 ms |
| Latency p95 | 2009.00 +/- 1.00 ms | 2013.00 +/- 1.00 ms |
| SoC temperature mean | 47.26 +/- 0.55 C | 47.23 +/- 0.32 C |
| SoC temperature peak | 49.20 +/- 1.56 C | 49.03 +/- 1.27 C |
| Wall power mean | 3.61 +/- 0.01 W | 3.58 +/- 0.01 W |
| Wall energy per run | 0.31 +/- 0.00 Wh | 0.30 +/- 0.00 Wh |
| Energy per input event | 0.09 +/- 0.00 J/event | 0.09 +/- 0.00 J/event |

Power covers the complete Pi and official PSU. No idle baseline is subtracted.
Energy superiority must not be claimed when differences are within meter resolution or trial variability.
