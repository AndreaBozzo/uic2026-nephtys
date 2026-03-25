// sensor-sim serves a WebSocket endpoint that emits synthetic air-quality
// sensor readings at a configurable rate. It is used for reproducible
// benchmarks and offline demos of the Nephtys edge connector.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"math/rand/v2"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
)

type Reading struct {
	StationID   string  `json:"station_id"`
	PM25        float64 `json:"pm25"`
	PM10        float64 `json:"pm10"`
	NO2         float64 `json:"no2"`
	Temperature float64 `json:"temperature"`
	Humidity    float64 `json:"humidity"`
	Lat         float64 `json:"lat"`
	Lon         float64 `json:"lon"`
	Timestamp   int64   `json:"ts"`
}

var upgrader = websocket.Upgrader{CheckOrigin: func(*http.Request) bool { return true }}

func main() {
	stations := flag.Int("stations", 20, "number of virtual sensor stations")
	intervalMs := flag.Int("interval", 500, "emission interval per station in milliseconds")
	port := flag.Int("port", 9090, "WebSocket server port")
	dupRatio := flag.Float64("dup-ratio", 0.3, "fraction of duplicate readings (0.0-1.0)")
	flag.Parse()

	http.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Printf("upgrade: %v", err)
			return
		}
		defer conn.Close()

		log.Printf("client connected, streaming %d stations every %dms (dup ratio %.0f%%)",
			*stations, *intervalMs, *dupRatio*100)

		ticker := time.NewTicker(time.Duration(*intervalMs) * time.Millisecond)
		defer ticker.Stop()

		// Base values per station — readings jitter around these.
		type state struct {
			lat, lon    float64
			pm25, pm10  float64
			no2         float64
			temp, humid float64
		}
		bases := make([]state, *stations)
		for i := range bases {
			bases[i] = state{
				lat:   39.30 + rand.Float64()*0.1,
				lon:   16.20 + rand.Float64()*0.1,
				pm25:  10 + rand.Float64()*30,
				pm10:  20 + rand.Float64()*50,
				no2:   5 + rand.Float64()*40,
				temp:  15 + rand.Float64()*15,
				humid: 40 + rand.Float64()*40,
			}
		}

		var lastPayload []byte

		for range ticker.C {
			for i := 0; i < *stations; i++ {
				b := &bases[i]

				r := Reading{
					StationID:   fmt.Sprintf("AQ-%03d", i),
					PM25:        b.pm25 + rand.Float64()*2 - 1,
					PM10:        b.pm10 + rand.Float64()*4 - 2,
					NO2:         b.no2 + rand.Float64()*3 - 1.5,
					Temperature: b.temp + rand.Float64()*0.6 - 0.3,
					Humidity:    b.humid + rand.Float64()*2 - 1,
					Lat:         b.lat,
					Lon:         b.lon,
					Timestamp:   time.Now().UnixMilli(),
				}

				// Simulate duplicates: re-send previous payload.
				if lastPayload != nil && rand.Float64() < *dupRatio {
					if err := conn.WriteMessage(websocket.TextMessage, lastPayload); err != nil {
						return
					}
					continue
				}

				data, _ := json.Marshal(r)
				lastPayload = data
				if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
					return
				}
			}
		}
	})

	addr := fmt.Sprintf(":%d", *port)
	log.Printf("sensor-sim listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}
