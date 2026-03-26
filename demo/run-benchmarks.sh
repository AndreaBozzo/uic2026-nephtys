#!/usr/bin/env bash
# run-benchmarks.sh — Reproducible benchmark for the Nephtys short paper.
#
# Prerequisites:
#   - Nephtys running on localhost:3002 with NEPHTYS_ADMIN_TOKEN=bench
#   - sensor-sim running on localhost:9091
#   - NATS JetStream on localhost:4222
#
# Usage: ./run-benchmarks.sh [DURATION_SECONDS]
#   Default duration: 300 (5 minutes)

set -euo pipefail

BASE="http://localhost:3002"
TOKEN="bench"
DURATION="${1:-300}"
AUTH=(-H "Authorization: Bearer $TOKEN")

echo "============================================="
echo " Nephtys Benchmark — ${DURATION}s per run"
echo "============================================="

cleanup() {
  echo "==> Cleaning up streams..."
  curl -s -X DELETE "$BASE/v1/streams/bench-baseline" "${AUTH[@]}" 2>/dev/null || true
  curl -s -X DELETE "$BASE/v1/streams/bench-pipeline" "${AUTH[@]}" 2>/dev/null || true
}
trap cleanup EXIT

# ---- Phase 1: Baseline (no pipeline) ----
echo ""
echo "==> Phase 1: Baseline run (no pipeline)"
curl -s -X POST "$BASE/v1/streams" \
  -H "Content-Type: application/json" "${AUTH[@]}" \
  -d '{
  "id": "bench-baseline",
  "kind": "websocket",
  "url": "ws://localhost:9091/ws",
  "topic": "nephtys.stream.bench.baseline"
}' > /dev/null

sleep 3
# Snapshot T0
T0_BL=$(curl -s "$BASE/metrics" | grep 'bench-baseline' | grep -v '^#')
echo "   Collecting for ${DURATION}s..."
sleep "$DURATION"
# Snapshot T1
T1_BL=$(curl -s "$BASE/metrics" | grep 'bench-baseline' | grep -v '^#')

# Extract deltas
bl_events_in_0=$(echo "$T0_BL" | grep 'events_ingested_total' | awk '{print $2}')
bl_events_in_1=$(echo "$T1_BL" | grep 'events_ingested_total' | awk '{print $2}')
bl_bytes_in_0=$(echo "$T0_BL"  | grep 'bytes_ingested_total'  | awk '{print $2}')
bl_bytes_in_1=$(echo "$T1_BL"  | grep 'bytes_ingested_total'  | awk '{print $2}')
bl_events_pub_0=$(echo "$T0_BL" | grep 'events_published_total' | awk '{print $2}')
bl_events_pub_1=$(echo "$T1_BL" | grep 'events_published_total' | awk '{print $2}')
bl_bytes_pub_0=$(echo "$T0_BL"  | grep 'bytes_published_total'  | awk '{print $2}')
bl_bytes_pub_1=$(echo "$T1_BL"  | grep 'bytes_published_total'  | awk '{print $2}')

curl -s -X DELETE "$BASE/v1/streams/bench-baseline" "${AUTH[@]}" > /dev/null
echo "   Baseline complete."

# ---- Phase 2: Full pipeline ----
echo ""
echo "==> Phase 2: Pipeline run (transform + dedup + threshold + batch)"
curl -s -X POST "$BASE/v1/streams" \
  -H "Content-Type: application/json" "${AUTH[@]}" \
  -d '{
  "id": "bench-pipeline",
  "kind": "websocket",
  "url": "ws://localhost:9091/ws",
  "topic": "nephtys.stream.bench.pipeline",
  "pipeline": {
    "transform": {
      "mapping": {
        "station": "station_id",
        "pm25":    "pm25",
        "no2":     "no2",
        "temp":    "temperature",
        "ts":      "ts"
      }
    },
    "dedup": {
      "enabled":    true,
      "cache_size": 500,
      "ttl":        "30s"
    },
    "threshold": {
      "enabled": true,
      "path":    "pm25",
      "delta":   1.0
    },
    "batch": {
      "enabled":        true,
      "max_batch_size":  50,
      "flush_interval": "5s"
    }
  }
}' > /dev/null

sleep 3
# Snapshot T0
T0_PL=$(curl -s "$BASE/metrics" | grep 'bench-pipeline' | grep -v '^#')
echo "   Collecting for ${DURATION}s..."
sleep "$DURATION"
# Snapshot T1
T1_PL=$(curl -s "$BASE/metrics" | grep 'bench-pipeline' | grep -v '^#')

pl_events_in_0=$(echo "$T0_PL" | grep 'events_ingested_total' | awk '{print $2}')
pl_events_in_1=$(echo "$T1_PL" | grep 'events_ingested_total' | awk '{print $2}')
pl_bytes_in_0=$(echo "$T0_PL"  | grep 'bytes_ingested_total'  | awk '{print $2}')
pl_bytes_in_1=$(echo "$T1_PL"  | grep 'bytes_ingested_total'  | awk '{print $2}')
pl_events_pub_0=$(echo "$T0_PL" | grep 'events_published_total' | awk '{print $2}')
pl_events_pub_1=$(echo "$T1_PL" | grep 'events_published_total' | awk '{print $2}')
pl_bytes_pub_0=$(echo "$T0_PL"  | grep 'bytes_published_total'  | awk '{print $2}')
pl_bytes_pub_1=$(echo "$T1_PL"  | grep 'bytes_published_total'  | awk '{print $2}')
pl_dedup_0=$(echo "$T0_PL"   | grep 'dedup'     | awk '{print $2}')
pl_dedup_1=$(echo "$T1_PL"   | grep 'dedup'     | awk '{print $2}')
pl_thresh_0=$(echo "$T0_PL"  | grep 'threshold' | awk '{print $2}')
pl_thresh_1=$(echo "$T1_PL"  | grep 'threshold' | awk '{print $2}')

curl -s -X DELETE "$BASE/v1/streams/bench-pipeline" "${AUTH[@]}" > /dev/null
echo "   Pipeline complete."

# ---- Phase 3: Memory ----
NEPHTYS_PID=$(pgrep -f nephtys | head -1)
RSS_KB=$(ps -o rss= -p "$NEPHTYS_PID" 2>/dev/null || echo "0")
RSS_MB=$(echo "scale=1; $RSS_KB / 1024" | bc)

# ---- Report ----
echo ""
echo "============================================="
echo " RESULTS"
echo "============================================="

python3 -c "
bl_ev_in  = ${bl_events_in_1} - ${bl_events_in_0}
bl_ev_pub = ${bl_events_pub_1} - ${bl_events_pub_0}
bl_by_in  = ${bl_bytes_in_1} - ${bl_bytes_in_0}
bl_by_pub = ${bl_bytes_pub_1} - ${bl_bytes_pub_0}

pl_ev_in  = ${pl_events_in_1} - ${pl_events_in_0}
pl_ev_pub = ${pl_events_pub_1} - ${pl_events_pub_0}
pl_by_in  = ${pl_bytes_in_1} - ${pl_bytes_in_0}
pl_by_pub = ${pl_bytes_pub_1} - ${pl_bytes_pub_0}
pl_dedup  = ${pl_dedup_1} - ${pl_dedup_0}
pl_thresh = ${pl_thresh_1} - ${pl_thresh_0}

byte_red = (1 - pl_by_pub / bl_by_in) * 100 if bl_by_in > 0 else 0
msg_red  = (1 - pl_ev_pub / bl_ev_in) * 100 if bl_ev_in > 0 else 0

print(f'Baseline:  {bl_ev_in:>8,.0f} events | {bl_by_in:>12,.0f} bytes')
print(f'Pipeline:  {pl_ev_in:>8,.0f} events in → {pl_ev_pub:,.0f} messages out | {pl_by_in:>12,.0f} → {pl_by_pub:,.0f} bytes')
print(f'')
print(f'Bandwidth reduction:     {byte_red:.1f}%')
print(f'Message count reduction: {msg_red:.1f}%')
print(f'Dedup drops:             {pl_dedup:,.0f} ({pl_dedup/(pl_dedup+pl_thresh)*100:.1f}% of drops)')
print(f'Threshold drops:         {pl_thresh:,.0f} ({pl_thresh/(pl_dedup+pl_thresh)*100:.1f}% of drops)')
print(f'Avg events per batch:    {(pl_ev_in - pl_dedup - pl_thresh) / max(pl_ev_pub,1):.1f}')
print(f'RSS memory:              ${RSS_MB} MB')
"
