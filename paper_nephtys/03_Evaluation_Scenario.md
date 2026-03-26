## III. Evaluation Scenario

We evaluate Nephtys in an urban air-quality monitoring scenario representative of a Smart City edge deployment. The objective is to quantify the bandwidth reduction, resource footprint, and resilience characteristics of the system under realistic sensor workloads. All source code, the sensor simulator, and an automated benchmark script are publicly available in the companion repository\footnote{\url{https://github.com/AndreaBozzo/short\_paper\_demo\_Nephtys}} to allow full reproducibility of the results presented below.

### A. Experimental Setup

Nephtys runs inside a Docker container with a 128\,MB memory limit, emulating a constrained edge gateway. NATS JetStream, Prometheus, and Grafana are co-deployed via Docker Compose. Two classes of data sources feed the system:

1. **Synthetic sensor streams**: A lightweight WebSocket-based simulator (\texttt{sensor-sim}) generates air-quality readings for 20 virtual stations at 2\,Hz, producing $\sim$40 events/s. Each event contains PM$_{2.5}$, PM$_{10}$, NO$_2$, temperature, and humidity values with configurable jitter and a 30\% duplicate ratio — modelling the redundancy typical of low-cost particulate-matter sensors.

2. **Real-world open data**: Three REST poller streams ingest measurements from the OpenAQ v3 API \cite{openaq2024} for monitoring stations in Southern Italy (Cosenza, Catanzaro, Reggio Calabria), polled every 30 seconds. These payloads are deeply nested JSON objects averaging $\sim$2.4\,KB per response.

The full middleware pipeline is configured as follows:
- **Transform**: maps \texttt{pm25}, \texttt{no2}, \texttt{temperature}, \texttt{ts} from nested payloads (5 fields from 40+)
- **Dedup**: TTL = 30\,s, cache size = 500 entries
- **Threshold**: path = \texttt{pm25}, $\delta = 1.0\;\mu\mathrm{g/m^3}$
- **Batch**: max size = 50 events, flush interval = 5\,s

### B. Results

Table~I reports the key metrics collected over a 5-minute run with 20 virtual sensor stations emitting at 2\,Hz ($\sim$40 events/s, 30\% duplicate ratio).

| Metric | No Pipeline | Full Pipeline | Reduction |
|--------|------------|---------------|-----------|
| Bytes published (5 min) | 2,946,146 | 901,087 | **66.9\%** |
| Messages published | 12,940 | 156 | **98.7\%** |
| Nephtys RSS memory | 22.6 MB | 22.6 MB | — |

The bandwidth reduction is decomposed by middleware stage using the \texttt{events\_dropped\_by\_pipeline\_total\{middleware\}} Prometheus counter. Of the 12,000 events ingested during the pipeline run, **Dedup** dropped 3,474 (82.3\% of all drops) — redundant identical readings within the 30\,s TTL window. **Threshold** filtered an additional 749 events (17.7\% of drops) — sub-delta PM$_{2.5}$ fluctuations below 1.0\,$\mu\mathrm{g/m^3}$. The remaining 7,777 events were compacted by **Batch** into 156 messages (avg.\ 50 events per message), and **Transform** reduced the per-event payload from 227 bytes to 116 bytes (49\% reduction by extracting 5 fields from the original 8).

**Resilience**: When the sensor simulator process is killed, the WebSocket connector detects the disconnection and enters exponential backoff (1\,s, 2\,s, 4\,s, 8\,s, 16\,s, capped at 30\,s). After the simulator is restarted, Nephtys reconnects automatically at the next backoff attempt. In our test, recovery occurred within 1–2\,s of the source becoming available. No crash, no manual intervention — ingestion simply pauses and resumes.

**Hot-reload latency**: Issuing a \texttt{PUT /v1/streams/\{id\}/pipeline} request to change the threshold delta from 1.0 to 5.0\,$\mu\mathrm{g/m^3}$ completes in under 16\,ms (including the full HTTP round-trip). The atomic pointer swap in the Stream Manager ensures the new pipeline takes effect on the very next event, with no loss or reordering.

### C. Live Demonstration

The demonstration is designed for interactive exploration:

1. **Launch**: Start the infrastructure (\texttt{docker compose up}) and the sensor simulator. Register streams via the provided shell scripts.
2. **Observe**: A pre-configured Grafana dashboard displays real-time panels: ingested vs. published event/byte rates, per-middleware drop breakdown, and gauge widgets showing the overall bandwidth reduction ratio.
3. **Interact**: The audience can issue REST API calls to (a) add new sensor streams on the fly, (b) hot-swap pipeline parameters (e.g., tighten the threshold delta), and (c) observe the immediate effect on the Grafana gauges — demonstrating runtime reconfigurability without service interruption.
