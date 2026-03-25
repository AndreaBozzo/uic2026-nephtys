## II. System Architecture and Resilience

Nephtys is designed from the ground up for the constraints of edge computing: limited memory, unreliable network connectivity, and the absence of orchestration infrastructure. Fig. 1 illustrates the overall architecture: urban sensor stations feed data into Nephtys through protocol-specific connectors; each stream traverses a configurable middleware pipeline before publication to NATS JetStream, from which cloud-side consumers subscribe.

<!-- Fig. 1: Architecture diagram — Sensor Stations → Connectors → Pipeline → NATS JetStream → Cloud -->

### A. Fault-Tolerant Ingestion

Each data source is managed by a *connector* abstraction that encapsulates the protocol-specific logic (WebSocket, REST poller, SSE, webhook, gRPC). In a Smart City deployment, connectors may simultaneously ingest high-frequency air-quality readings via WebSocket from a local sensor gateway and poll a municipal open-data REST API for meteorological context.

All connectors implement automatic reconnection with **exponential backoff** (initial delay 1 s, capped at 30 s). This prevents accidental denial-of-service flooding when an upstream sensor gateway reboots or loses connectivity — a common occurrence on battery-powered or solar-powered field nodes. The system never crashes on connection loss; it transitions to a *reconnecting* state and resumes ingestion transparently once the source is available again.

### B. Zero-Infrastructure Persistence

Edge nodes frequently lack the resources to run a relational database or even an embedded key-value store alongside the application. Nephtys addresses this by leveraging **NATS JetStream** as both the event transport and the configuration store:

- **Event durability**: Published sensor events are stored in a durable JetStream stream with configurable retention (default: 72 hours), surviving process restarts without data loss.
- **Configuration persistence**: Active stream configurations are serialised in a JetStream Key-Value bucket (`nephtys_streams`). On startup, the Stream Manager reads all persisted entries and re-registers the corresponding connectors and pipelines — achieving full state recovery with no external dependencies.

This design means Nephtys and NATS are the *only two processes* required on an edge node — a minimal footprint suitable for single-board computers such as the Raspberry Pi 4.

### C. Edge Pipeline for Bandwidth Reduction

The core innovation is the **Pipeline Middleware** engine. Before an event reaches the broker, it traverses a chain of composable middleware stages, each independently configurable per stream:

- **Transform**: Extracts only the relevant fields from deeply nested JSON payloads using dot-notation path mapping. For example, a raw air-quality API response containing 40+ fields can be reduced to just `pm25`, `no2`, and `temperature`, cutting the payload size by over 80%.
- **Dedup**: Computes the FNV-64a hash of each payload and blocks duplicates within a configurable time-to-live window (e.g., 30 s). Environmental sensors often report identical readings across consecutive intervals when conditions are stable — deduplication eliminates this redundancy.
- **Threshold**: Passes an event only if the absolute change in a numerical field exceeds a configurable delta (e.g., Δpm25 ≥ 1.0 µg/m³). This filters out sensor noise and micro-fluctuations that carry no informational value.
- **Batch**: Buffers events and flushes them as a single aggregated message at a configurable interval or batch size, reducing per-message overhead.
- **Filter** and **Enrich**: Drop events not matching specified types, or inject static metadata tags (e.g., `city: Cosenza`, `network: aq-south`).

The pipeline configuration is a JSON object attached to each stream registration and can be **hot-swapped at runtime** via a `PUT /v1/streams/{id}/pipeline` REST call. Internally, the active pipeline handler is stored behind a Go `atomic.Pointer`, so the swap is lock-free and takes effect on the very next event — with sub-millisecond latency and zero downtime. This allows city operators to dynamically tighten or relax filtering thresholds in response to air-quality alerts without interrupting data flow.
