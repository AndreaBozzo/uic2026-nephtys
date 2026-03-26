#!/usr/bin/env bash
# run-benchmarks.sh -- Reproducible benchmark for the Nephtys short paper.
#
# Prerequisites:
#   - Nephtys running on localhost:3002 with NEPHTYS_ADMIN_TOKEN=bench
#   - sensor-sim running on localhost:9091 (for synthetic phases)
#   - NATS JetStream on localhost:4222
#   - Internet access (for real-data phase)
#
# Usage: ./run-benchmarks.sh [SIM_DURATION] [REAL_DURATION]
#   Defaults: SIM_DURATION=300 (5 min), REAL_DURATION=1800 (30 min)

set -euo pipefail

BASE="http://localhost:3002"
TOKEN="${NEPHTYS_ADMIN_TOKEN:-bench}"
SIM_DURATION="${1:-300}"
REAL_DURATION="${2:-1800}"
AUTH=(-H "Authorization: Bearer $TOKEN")

# Helper: extract a metric delta between two snapshots
metric_val() {
  echo "$1" | grep "$2" | awk '{print $2}' | head -1
}

echo "============================================="
echo " Nephtys Benchmark"
echo " Synthetic: ${SIM_DURATION}s | Real data: ${REAL_DURATION}s"
echo "============================================="

cleanup() {
  echo "==> Cleaning up streams..."
  for sid in bench-baseline bench-pipeline real-meteo-cosenza real-aq-cosenza real-aq-catanzaro real-aq-reggio real-citizen-78066; do
    curl -s -X DELETE "$BASE/v1/streams/$sid" "${AUTH[@]}" 2>/dev/null || true
  done
}
trap cleanup EXIT

###########################################################
# Phase 1: Synthetic baseline (no pipeline)
###########################################################
echo ""
echo "==> Phase 1: Synthetic baseline (no pipeline, ${SIM_DURATION}s)"
curl -s -X POST "$BASE/v1/streams" \
  -H "Content-Type: application/json" "${AUTH[@]}" \
  -d '{
  "id": "bench-baseline",
  "kind": "websocket",
  "url": "ws://localhost:9091/ws",
  "topic": "nephtys.stream.bench.baseline"
}' > /dev/null

sleep 3
T0_BL=$(curl -s "$BASE/metrics" | grep 'bench-baseline' | grep -v '^#')
echo "   Collecting for ${SIM_DURATION}s..."
sleep "$SIM_DURATION"
T1_BL=$(curl -s "$BASE/metrics" | grep 'bench-baseline' | grep -v '^#')

bl_events_in_0=$(metric_val "$T0_BL" 'events_ingested_total')
bl_events_in_1=$(metric_val "$T1_BL" 'events_ingested_total')
bl_bytes_in_0=$(metric_val "$T0_BL" 'bytes_ingested_total')
bl_bytes_in_1=$(metric_val "$T1_BL" 'bytes_ingested_total')
bl_events_pub_0=$(metric_val "$T0_BL" 'events_published_total')
bl_events_pub_1=$(metric_val "$T1_BL" 'events_published_total')
bl_bytes_pub_0=$(metric_val "$T0_BL" 'bytes_published_total')
bl_bytes_pub_1=$(metric_val "$T1_BL" 'bytes_published_total')

curl -s -X DELETE "$BASE/v1/streams/bench-baseline" "${AUTH[@]}" > /dev/null
echo "   Synthetic baseline complete."

###########################################################
# Phase 2: Synthetic with full pipeline
###########################################################
echo ""
echo "==> Phase 2: Synthetic with pipeline (${SIM_DURATION}s)"
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
T0_PL=$(curl -s "$BASE/metrics" | grep 'bench-pipeline' | grep -v '^#')
echo "   Collecting for ${SIM_DURATION}s..."
sleep "$SIM_DURATION"
T1_PL=$(curl -s "$BASE/metrics" | grep 'bench-pipeline' | grep -v '^#')

pl_events_in_0=$(metric_val "$T0_PL" 'events_ingested_total')
pl_events_in_1=$(metric_val "$T1_PL" 'events_ingested_total')
pl_bytes_in_0=$(metric_val "$T0_PL" 'bytes_ingested_total')
pl_bytes_in_1=$(metric_val "$T1_PL" 'bytes_ingested_total')
pl_events_pub_0=$(metric_val "$T0_PL" 'events_published_total')
pl_events_pub_1=$(metric_val "$T1_PL" 'events_published_total')
pl_bytes_pub_0=$(metric_val "$T0_PL" 'bytes_published_total')
pl_bytes_pub_1=$(metric_val "$T1_PL" 'bytes_published_total')
pl_dedup_0=$(metric_val "$T0_PL" 'dedup')
pl_dedup_1=$(metric_val "$T1_PL" 'dedup')
pl_thresh_0=$(metric_val "$T0_PL" 'threshold')
pl_thresh_1=$(metric_val "$T1_PL" 'threshold')

curl -s -X DELETE "$BASE/v1/streams/bench-pipeline" "${AUTH[@]}" > /dev/null
echo "   Synthetic pipeline complete."

###########################################################
# Phase 3: Real-data streams (Open-Meteo + Sensor.Community)
###########################################################
echo ""
echo "==> Phase 3: Real-data streams (${REAL_DURATION}s)"

# Register 5 real-data streams
echo "   Registering Open-Meteo weather (Cosenza)..."
curl -s -X POST "$BASE/v1/streams" \
  -H "Content-Type: application/json" "${AUTH[@]}" \
  -d '{
  "id": "real-meteo-cosenza",
  "kind": "rest_poller",
  "url": "https://api.open-meteo.com/v1/forecast?latitude=39.30&longitude=16.25&current=temperature_2m,relative_humidity_2m,wind_speed_10m,precipitation,surface_pressure&timezone=Europe/Rome",
  "topic": "nephtys.stream.real.meteo.cosenza",
  "rest_poller": { "interval": "30s", "method": "GET" },
  "pipeline": {
    "transform": {
      "mapping": {
        "temp": "current.temperature_2m",
        "humidity": "current.relative_humidity_2m",
        "wind": "current.wind_speed_10m",
        "rain": "current.precipitation",
        "pressure": "current.surface_pressure",
        "time": "current.time"
      }
    },
    "dedup": { "enabled": true, "cache_size": 200, "ttl": "60s" },
    "threshold": { "enabled": true, "path": "temp", "delta": 0.5 }
  }
}' > /dev/null

REAL_AQ_LATS=("39.30" "38.91" "38.11")
REAL_AQ_LONS=("16.25" "16.59" "15.66")
REAL_AQ_IDS=("real-aq-cosenza" "real-aq-catanzaro" "real-aq-reggio")

for i in "${!REAL_AQ_IDS[@]}"; do
  echo "   Registering Open-Meteo AQ (${REAL_AQ_IDS[$i]})..."
  curl -s -X POST "$BASE/v1/streams" \
    -H "Content-Type: application/json" "${AUTH[@]}" \
    -d "{
    \"id\": \"${REAL_AQ_IDS[$i]}\",
    \"kind\": \"rest_poller\",
    \"url\": \"https://air-quality-api.open-meteo.com/v1/air-quality?latitude=${REAL_AQ_LATS[$i]}&longitude=${REAL_AQ_LONS[$i]}&current=pm10,pm2_5,nitrogen_dioxide,ozone,sulphur_dioxide\",
    \"topic\": \"nephtys.stream.real.aq.${REAL_AQ_IDS[$i]##real-aq-}\",
    \"rest_poller\": { \"interval\": \"30s\", \"method\": \"GET\" },
    \"pipeline\": {
      \"transform\": {
        \"mapping\": {
          \"pm25\": \"current.pm2_5\",
          \"pm10\": \"current.pm10\",
          \"no2\": \"current.nitrogen_dioxide\",
          \"o3\": \"current.ozone\",
          \"so2\": \"current.sulphur_dioxide\",
          \"time\": \"current.time\"
        }
      },
      \"dedup\": { \"enabled\": true, \"cache_size\": 200, \"ttl\": \"60s\" },
      \"threshold\": { \"enabled\": true, \"path\": \"pm25\", \"delta\": 0.5 }
    }
  }" > /dev/null
done

echo "   Registering Sensor.Community citizen sensor (#78066)..."
curl -s -X POST "$BASE/v1/streams" \
  -H "Content-Type: application/json" "${AUTH[@]}" \
  -d '{
  "id": "real-citizen-78066",
  "kind": "rest_poller",
  "url": "https://data.sensor.community/airrohr/v1/sensor/78066/",
  "topic": "nephtys.stream.real.citizen",
  "rest_poller": { "interval": "60s", "method": "GET" },
  "pipeline": {
    "transform": {
      "mapping": {
        "pm10": "0.sensordatavalues.0.value",
        "pm25": "0.sensordatavalues.1.value",
        "lat":  "0.location.latitude",
        "lon":  "0.location.longitude",
        "time": "0.timestamp"
      }
    },
    "dedup": { "enabled": true, "cache_size": 100, "ttl": "120s" }
  }
}' > /dev/null

echo "   5 real-data streams registered."

sleep 3
# Snapshot T0 for all real streams
T0_REAL=$(curl -s "$BASE/metrics" | grep -E 'real-(meteo|aq|citizen)' | grep -v '^#')
echo "   Collecting for ${REAL_DURATION}s..."
sleep "$REAL_DURATION"
T1_REAL=$(curl -s "$BASE/metrics" | grep -E 'real-(meteo|aq|citizen)' | grep -v '^#')

# Aggregate across all real streams
r_events_in_0=$(echo "$T0_REAL" | grep 'events_ingested_total' | awk '{s+=$2} END{print s+0}')
r_events_in_1=$(echo "$T1_REAL" | grep 'events_ingested_total' | awk '{s+=$2} END{print s+0}')
r_bytes_in_0=$(echo "$T0_REAL" | grep 'bytes_ingested_total' | awk '{s+=$2} END{print s+0}')
r_bytes_in_1=$(echo "$T1_REAL" | grep 'bytes_ingested_total' | awk '{s+=$2} END{print s+0}')
r_events_pub_0=$(echo "$T0_REAL" | grep 'events_published_total' | awk '{s+=$2} END{print s+0}')
r_events_pub_1=$(echo "$T1_REAL" | grep 'events_published_total' | awk '{s+=$2} END{print s+0}')
r_bytes_pub_0=$(echo "$T0_REAL" | grep 'bytes_published_total' | awk '{s+=$2} END{print s+0}')
r_bytes_pub_1=$(echo "$T1_REAL" | grep 'bytes_published_total' | awk '{s+=$2} END{print s+0}')
r_dedup_0=$(echo "$T0_REAL" | grep 'dedup' | awk '{s+=$2} END{print s+0}')
r_dedup_1=$(echo "$T1_REAL" | grep 'dedup' | awk '{s+=$2} END{print s+0}')
r_thresh_0=$(echo "$T0_REAL" | grep 'threshold' | awk '{s+=$2} END{print s+0}')
r_thresh_1=$(echo "$T1_REAL" | grep 'threshold' | awk '{s+=$2} END{print s+0}')

# Clean up real streams
for sid in real-meteo-cosenza real-aq-cosenza real-aq-catanzaro real-aq-reggio real-citizen-78066; do
  curl -s -X DELETE "$BASE/v1/streams/$sid" "${AUTH[@]}" > /dev/null 2>&1 || true
done
echo "   Real-data phase complete."

###########################################################
# Memory
###########################################################
NEPHTYS_PID=$(pgrep -f nephtys | head -1)
RSS_KB=$(ps -o rss= -p "$NEPHTYS_PID" 2>/dev/null || echo "0")
RSS_MB=$(echo "scale=1; $RSS_KB / 1024" | bc)

###########################################################
# Report
###########################################################
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

r_ev_in   = ${r_events_in_1} - ${r_events_in_0}
r_ev_pub  = ${r_events_pub_1} - ${r_events_pub_0}
r_by_in   = ${r_bytes_in_1} - ${r_bytes_in_0}
r_by_pub  = ${r_bytes_pub_1} - ${r_bytes_pub_0}
r_dedup   = ${r_dedup_1} - ${r_dedup_0}
r_thresh  = ${r_thresh_1} - ${r_thresh_0}

byte_red = (1 - pl_by_pub / bl_by_in) * 100 if bl_by_in > 0 else 0
msg_red  = (1 - pl_ev_pub / bl_ev_in) * 100 if bl_ev_in > 0 else 0

r_byte_red = (1 - r_by_pub / r_by_in) * 100 if r_by_in > 0 else 0
r_msg_red  = (1 - r_ev_pub / r_ev_in) * 100 if r_ev_in > 0 else 0

print('--- Synthetic Streams (sensor-sim, ${SIM_DURATION}s) ---')
print(f'Baseline:  {bl_ev_in:>8,.0f} events | {bl_by_in:>12,.0f} bytes')
print(f'Pipeline:  {pl_ev_in:>8,.0f} events in -> {pl_ev_pub:,.0f} messages out | {pl_by_in:>12,.0f} -> {pl_by_pub:,.0f} bytes')
print(f'Bandwidth reduction:     {byte_red:.1f}%')
print(f'Message count reduction: {msg_red:.1f}%')
total_drops = pl_dedup + pl_thresh
if total_drops > 0:
    print(f'Dedup drops:             {pl_dedup:,.0f} ({pl_dedup/total_drops*100:.1f}% of drops)')
    print(f'Threshold drops:         {pl_thresh:,.0f} ({pl_thresh/total_drops*100:.1f}% of drops)')
print(f'Avg events per batch:    {(pl_ev_in - pl_dedup - pl_thresh) / max(pl_ev_pub,1):.1f}')
print()
print('--- Real-Data Streams (Open-Meteo + Sensor.Community, ${REAL_DURATION}s) ---')
print(f'Ingested:  {r_ev_in:>8,.0f} events | {r_by_in:>12,.0f} bytes')
print(f'Published: {r_ev_pub:>8,.0f} events | {r_by_pub:>12,.0f} bytes')
print(f'Bandwidth reduction:     {r_byte_red:.1f}%')
print(f'Message count reduction: {r_msg_red:.1f}%')
r_total_drops = r_dedup + r_thresh
if r_total_drops > 0:
    print(f'Dedup drops:             {r_dedup:,.0f}')
    print(f'Threshold drops:         {r_thresh:,.0f}')
print()
print(f'RSS memory:              ${RSS_MB} MB')
"
