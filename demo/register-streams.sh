#!/usr/bin/env bash
# register-streams.sh — registers demo streams on a running Nephtys instance.
# Usage: ./register-streams.sh [NEPHTYS_URL]
#
# Streams registered:
#   1. sensor-sim  — WebSocket from the local sensor simulator
#   2. openaq-*    — REST pollers for real OpenAQ air-quality stations

set -euo pipefail

BASE="${1:-http://localhost:3002}"

echo "==> Registering sensor-sim WebSocket stream"
curl -s -X POST "$BASE/v1/streams" \
  -H "Content-Type: application/json" \
  -d '{
  "id":    "sensor-sim",
  "kind":  "websocket",
  "url":   "ws://localhost:9090/ws",
  "topic": "nephtys.stream.aq.sim",
  "pipeline": {
    "transform": {
      "mapping": {
        "station":    "station_id",
        "pm25":       "pm25",
        "no2":        "no2",
        "temp":       "temperature",
        "ts":         "ts"
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
}' | jq .

echo ""

# OpenAQ station IDs for cities in Calabria / Southern Italy (close to UIC venue).
# These are location IDs from the OpenAQ v3 API.
OPENAQ_LOCATIONS=("2178" "2236" "8036")
OPENAQ_NAMES=("cosenza" "catanzaro" "reggio-calabria")

for i in "${!OPENAQ_LOCATIONS[@]}"; do
  LOC="${OPENAQ_LOCATIONS[$i]}"
  NAME="${OPENAQ_NAMES[$i]}"
  echo "==> Registering OpenAQ poller: $NAME (location $LOC)"
  curl -s -X POST "$BASE/v1/streams" \
    -H "Content-Type: application/json" \
    -d "{
    \"id\":    \"openaq-${NAME}\",
    \"kind\":  \"rest_poller\",
    \"url\":   \"https://api.openaq.org/v3/locations/${LOC}/measurements?limit=10\",
    \"topic\": \"nephtys.stream.aq.${NAME}\",
    \"rest_poller\": {
      \"interval\": \"30s\",
      \"method\":   \"GET\"
    },
    \"pipeline\": {
      \"transform\": {
        \"mapping\": {
          \"parameter\": \"results.0.parameter.name\",
          \"value\":     \"results.0.value\",
          \"unit\":      \"results.0.parameter.units\",
          \"datetime\":  \"results.0.datetime.utc\"
        }
      },
      \"dedup\": {
        \"enabled\":    true,
        \"cache_size\": 200,
        \"ttl\":        \"60s\"
      }
    }
  }" | jq .
  echo ""
done

echo "==> All streams registered. Check status:"
curl -s "$BASE/v1/streams" | jq .
