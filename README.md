# Nephtys Short Paper -- Companion Repository

Companion material for the IEEE UIC 2026 short paper:

> **Nephtys: Lightweight Edge Connector for Bandwidth-Efficient Ingestion of Urban Sensor Streams**
> Andrea Bozzo, Independent Researcher

This repository contains the sensor simulator, demo scripts, benchmark
automation, and LaTeX source used to produce the results in the paper.
A pre-compiled PDF is available at [`paper_nephtys/main.pdf`](paper_nephtys/main.pdf).
Nephtys itself lives in a [separate repository](https://github.com/AndreaBozzo/Nephtys).

![Grafana dashboard](paper_nephtys/fig_grafana_dashboard.png)
*Grafana dashboard during a mixed workload showing ingested vs. published rates, per-middleware drop breakdown, and reduction gauges (65.7% bandwidth, 98.6% events).*

## Prerequisites

| Component | Version | Notes |
|-----------|---------|-------|
| [Nephtys](https://github.com/AndreaBozzo/Nephtys) | commit `14b548b` or later | Edge connector under evaluation |
| Go | 1.25+ | To build sensor-sim and Nephtys |
| Docker + Docker Compose | any recent | For NATS, Prometheus, Grafana |
| Python 3 | 3.8+ | Benchmark result computation |
| jq | any | Used by demo scripts |

## Repository Layout

```
sensor-sim/          WebSocket-based air-quality simulator (Go)
demo/
  register-streams.sh   Register demo streams on a running Nephtys instance
  run-benchmarks.sh     Automated three-phase benchmark (synthetic + real data)
  grafana-dashboard.json Pre-configured Grafana dashboard for live monitoring
paper_nephtys/
  main.tex              LaTeX source (IEEEtran conference, 4 pages)
  fig_architecture_inline.tex  TikZ architecture diagram
  fig_grafana_dashboard.png    Dashboard screenshot from evaluation run
  references.bib        BibTeX references
```

## Reproducing the Benchmark

### 1. Start the infrastructure

Clone Nephtys and bring up the Docker Compose stack:

```bash
cd /path/to/Nephtys
docker compose up -d     # starts NATS JetStream, Prometheus, Grafana
```

### 2. Build and start Nephtys

```bash
cd /path/to/Nephtys
go build -o nephtys ./cmd/nephtys
NEPHTYS_ADMIN_TOKEN=bench ./nephtys
```

Nephtys listens on `http://localhost:3002` by default.

### 3. Start the sensor simulator

```bash
cd sensor-sim/
go run main.go -stations 20 -interval 500 -dup-ratio 0.3 -port 9091
```

This launches 20 virtual air-quality stations emitting at 2 Hz with a 30%
duplicate ratio, matching the paper's experimental setup.

### 4. Run the benchmark

```bash
cd demo/
./run-benchmarks.sh 300 1800   # 5 min synthetic, 30 min real data
```

The script runs three phases:

1. **Synthetic baseline** -- ingests sensor-sim data with no middleware pipeline.
2. **Synthetic pipeline** -- applies Transform, Dedup (TTL=30s), Threshold
   (delta=1.0), and Batch (size=50, flush=5s).
3. **Real-data streams** -- registers five REST poller streams hitting
   Open-Meteo and Sensor.Community APIs with Transform + Dedup + Threshold.

At the end it prints bandwidth reduction, message-count reduction, per-middleware
drop breakdown, and RSS memory -- the numbers reported in Table I of the paper.

### 5. (Optional) Live dashboard

Import `demo/grafana-dashboard.json` into Grafana at `http://localhost:3000`
to watch ingestion rates and reduction gauges in real time.

### 6. (Optional) Register demo streams manually

```bash
cd demo/
./register-streams.sh
```

This registers the sensor-sim WebSocket stream, four Open-Meteo REST poller
streams (weather + air quality for Cosenza, Catanzaro, Reggio Calabria), and
one Sensor.Community citizen sensor stream (Gioia Tauro), all with full
pipeline configurations.

## Compiling the Paper

```bash
cd paper_nephtys/
pdflatex main.tex
bibtex main
pdflatex main.tex
pdflatex main.tex
```

Requires a TeX Live or MiKTeX installation with the `IEEEtran` class.

## License

The companion material in this repository is released under the MIT License.
Nephtys is licensed separately; see its own repository for details.
