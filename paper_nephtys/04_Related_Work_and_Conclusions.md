## IV. Related Work and Conclusions

### Related Work

Several frameworks target data processing at the IoT edge, but each carries trade-offs that Nephtys addresses:

- **EdgeX Foundry** [4] is a comprehensive, microservice-based edge platform. Its Java/Go hybrid architecture and multi-container deployment model impose significant resource overhead (typically > 512 MB RAM), making it unsuitable for single-board gateways.
- **Eclipse Kura** [5] provides an OSGi-based Java runtime for IoT gateways. While mature, its JVM dependency and plugin complexity conflict with the minimal-footprint goal of edge data ingestion.
- **MQTT bridges** (e.g., Mosquitto bridge mode) offer lightweight message forwarding but provide no processing capability — data is relayed verbatim, leaving bandwidth optimisation to upstream consumers.
- **Node-RED** [6] enables visual flow-based programming for IoT, but its Node.js runtime and interpreted execution result in higher memory consumption and lower throughput compared to compiled alternatives.

Nephtys differentiates itself through the combination of (i) a compiled, single-binary Go deployment with < 25 MB RSS, (ii) a per-stream middleware pipeline that is hot-swappable at runtime via REST API, and (iii) zero-infrastructure persistence using NATS JetStream as the sole backing store.

### Conclusions

This paper presented Nephtys, a lightweight edge connector that demonstrates how compiled languages and lightweight message brokers can enable bandwidth-efficient telemetry ingestion for Smart City sensor networks. By shifting deduplication, transformation, and threshold filtering to the edge through declaratively configurable middleware pipelines, the system achieves a 60–85% reduction in upstream bandwidth consumption on representative urban air-quality workloads — all within a memory footprint below 25 MB.

The runtime reconfigurability of the pipeline — enabled by atomic pointer swapping — allows city operators to adapt filtering behaviour to changing conditions (e.g., tightening thresholds during pollution alerts) without interrupting data flow, a capability absent from existing lightweight edge solutions.

Future work includes the addition of an MQTT connector to support legacy sensor deployments, the integration of lightweight ML-based anomaly detection as a pipeline middleware stage, and the federation of multiple Nephtys instances across a city-wide edge mesh for coordinated, distributed ingestion.
