#!/usr/bin/env bash
# register-streams.sh -- registers demo streams on a running Nephtys instance.
# Usage: ./register-streams.sh [NEPHTYS_URL]
#
# Streams registered:
#   1. sensor-sim      -- WebSocket from the local sensor simulator (20 stations)
#   2. meteo-cosenza   -- Open-Meteo weather for Cosenza
#   3. aq-cosenza      -- Open-Meteo air quality for Cosenza
#   4. aq-catanzaro    -- Open-Meteo air quality for Catanzaro
#   5. aq-reggio       -- Open-Meteo air quality for Reggio Calabria
#   6. sensor-community-- Sensor.Community citizen sensor (Gioia Tauro, #78066)

set -euo pipefail

BASE="${1:-http://localhost:3002}"
TOKEN="${NEPHTYS_ADMIN_TOKEN:-bench}"
AUTH=(-H "Authorization: Bearer $TOKEN")

echo "==> Registering sensor-sim WebSocket stream"
curl -s -X POST "$BASE/v1/streams" \
  -H "Content-Type: application/json" "${AUTH[@]}" \
  -d '{
  "id":    "sensor-sim",
  "kind":  "websocket",
  "url":   "ws://localhost:9091/ws",
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
echo "==> Registering Open-Meteo weather stream (Cosenza)"
curl -s -X POST "$BASE/v1/streams" \
  -H "Content-Type: application/json" "${AUTH[@]}" \
  -d '{
  "id":    "meteo-cosenza",
  "kind":  "rest_poller",
  "url":   "https://api.open-meteo.com/v1/forecast?latitude=39.30&longitude=16.25&current=temperature_2m,relative_humidity_2m,wind_speed_10m,precipitation,surface_pressure&timezone=Europe/Rome",
  "topic": "nephtys.stream.meteo.cosenza",
  "rest_poller": {
    "interval": "30s",
    "method":   "GET"
  },
  "pipeline": {
    "transform": {
      "mapping": {
        "temp":     "current.temperature_2m",
        "humidity": "current.relative_humidity_2m",
        "wind":     "current.wind_speed_10m",
        "rain":     "current.precipitation",
        "pressure": "current.surface_pressure",
        "time":     "current.time"
      }
    },
    "dedup": {
      "enabled":    true,
      "cache_size": 200,
      "ttl":        "60s"
    },
    "threshold": {
      "enabled": true,
      "path":    "temp",
      "delta":   0.5
    }
  }
}' | jq .

echo ""

# Open-Meteo Air Quality for three Calabrian cities
AQ_LATS=("39.30" "38.91" "38.11")
AQ_LONS=("16.25" "16.59" "15.66")
AQ_NAMES=("cosenza" "catanzaro" "reggio")

for i in "${!AQ_NAMES[@]}"; do
  LAT="${AQ_LATS[$i]}"
  LON="${AQ_LONS[$i]}"
  NAME="${AQ_NAMES[$i]}"
  echo "==> Registering Open-Meteo air quality: $NAME"
  curl -s -X POST "$BASE/v1/streams" \
    -H "Content-Type: application/json" "${AUTH[@]}" \
    -d "{
    \"id\":    \"aq-${NAME}\",
    \"kind\":  \"rest_poller\",
    \"url\":   \"https://air-quality-api.open-meteo.com/v1/air-quality?latitude=${LAT}&longitude=${LON}&current=pm10,pm2_5,nitrogen_dioxide,ozone,sulphur_dioxide\",
    \"topic\": \"nephtys.stream.aq.${NAME}\",
    \"rest_poller\": {
      \"interval\": \"30s\",
      \"method\":   \"GET\"
    },
    \"pipeline\": {
      \"transform\": {
        \"mapping\": {
          \"pm25\":  \"current.pm2_5\",
          \"pm10\":  \"current.pm10\",
          \"no2\":   \"current.nitrogen_dioxide\",
          \"o3\":    \"current.ozone\",
          \"so2\":   \"current.sulphur_dioxide\",
          \"time\":  \"current.time\"
        }
      },
      \"dedup\": {
        \"enabled\":    true,
        \"cache_size\": 200,
        \"ttl\":        \"60s\"
      },
      \"threshold\": {
        \"enabled\": true,
        \"path\":    \"pm25\",
        \"delta\":   0.5
      }
    }
  }" | jq .
  echo ""
done

echo "==> Registering Sensor.Community citizen sensor (Gioia Tauro, #78066)"
curl -s -X POST "$BASE/v1/streams" \
  -H "Content-Type: application/json" "${AUTH[@]}" \
  -d '{
  "id":    "sensor-community-78066",
  "kind":  "rest_poller",
  "url":   "https://data.sensor.community/airrohr/v1/sensor/78066/",
  "topic": "nephtys.stream.aq.citizen",
  "rest_poller": {
    "interval": "60s",
    "method":   "GET"
  },
  "pipeline": {
    "transform": {
      "mapping": {
        "pm10":  "0.sensordatavalues.0.value",
        "pm25":  "0.sensordatavalues.1.value",
        "lat":   "0.location.latitude",
        "lon":   "0.location.longitude",
        "time":  "0.timestamp"
      }
    },
    "dedup": {
      "enabled":    true,
      "cache_size": 100,
      "ttl":        "120s"
    }
  }
}' | jq .

echo ""
echo "==> All streams registered. Check status:"
curl -s "$BASE/v1/streams" "${AUTH[@]}" | jq .
