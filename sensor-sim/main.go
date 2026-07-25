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
	"sync"
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

type runController struct {
	mu          sync.Mutex
	controlled  bool
	state       string
	connections int
	target      int64
	sent        int64
	bytesSent   int64
	startedAt   time.Time
	completedAt time.Time
}

type runStats struct {
	State       string `json:"state"`
	Connections int    `json:"connections"`
	Target      int64  `json:"target_events"`
	EventsSent  int64  `json:"events_sent"`
	BytesSent   int64  `json:"bytes_sent"`
	StartedAt   string `json:"started_at,omitempty"`
	CompletedAt string `json:"completed_at,omitempty"`
}

func (c *runController) reset() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.state == "running" {
		return fmt.Errorf("cannot reset while a run is active")
	}
	c.state = "idle"
	c.target = 0
	c.sent = 0
	c.bytesSent = 0
	c.startedAt = time.Time{}
	c.completedAt = time.Time{}
	return nil
}

func (c *runController) start(target int64) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.controlled {
		return fmt.Errorf("controlled mode is disabled")
	}
	if c.state == "running" {
		return fmt.Errorf("a run is already active")
	}
	if c.connections != 1 {
		return fmt.Errorf("exactly one WebSocket client is required, found %d", c.connections)
	}
	if target <= 0 {
		return fmt.Errorf("events must be positive")
	}
	c.state = "running"
	c.target = target
	c.sent = 0
	c.bytesSent = 0
	c.startedAt = time.Now()
	c.completedAt = time.Time{}
	return nil
}

func (c *runController) snapshot() runStats {
	c.mu.Lock()
	defer c.mu.Unlock()
	stats := runStats{
		State:       c.state,
		Connections: c.connections,
		Target:      c.target,
		EventsSent:  c.sent,
		BytesSent:   c.bytesSent,
	}
	if !c.startedAt.IsZero() {
		stats.StartedAt = c.startedAt.UTC().Format(time.RFC3339Nano)
	}
	if !c.completedAt.IsZero() {
		stats.CompletedAt = c.completedAt.UTC().Format(time.RFC3339Nano)
	}
	return stats
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func main() {
	stations := flag.Int("stations", 20, "number of virtual sensor stations")
	intervalMs := flag.Int("interval", 500, "emission interval per station in milliseconds")
	port := flag.Int("port", 9090, "WebSocket server port")
	dupRatio := flag.Float64("dup-ratio", 0.3, "fraction of duplicate readings (0.0-1.0)")
	seed := flag.Uint64("seed", 2646958770, "deterministic random seed")
	controlled := flag.Bool("controlled", false, "pause emission until started through the control API")
	flag.Parse()

	controller := &runController{controlled: *controlled, state: "idle"}

	http.HandleFunc("/control/reset", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "POST required"})
			return
		}
		if err := controller.reset(); err != nil {
			writeJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, controller.snapshot())
	})

	http.HandleFunc("/control/run", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "POST required"})
			return
		}
		var request struct {
			Events int64 `json:"events"`
		}
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
			return
		}
		if err := controller.start(request.Events); err != nil {
			writeJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusAccepted, controller.snapshot())
	})

	http.HandleFunc("/stats", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "GET required"})
			return
		}
		writeJSON(w, http.StatusOK, controller.snapshot())
	})

	http.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Printf("upgrade: %v", err)
			return
		}
		defer conn.Close()

		controller.mu.Lock()
		controller.connections++
		controller.mu.Unlock()
		defer func() {
			controller.mu.Lock()
			controller.connections--
			if controller.controlled && controller.state == "running" {
				controller.state = "interrupted"
				controller.completedAt = time.Now()
			}
			controller.mu.Unlock()
		}()

		log.Printf("client connected, streaming %d stations every %dms (dup ratio %.0f%%)",
			*stations, *intervalMs, *dupRatio*100)
		rng := rand.New(rand.NewPCG(*seed, *seed^0x9e3779b97f4a7c15))

		ticker := time.NewTicker(time.Duration(*intervalMs) * time.Millisecond)
		defer ticker.Stop()
		pingTicker := time.NewTicker(time.Second)
		defer pingTicker.Stop()
		_ = conn.SetReadDeadline(time.Now().Add(4 * time.Second))
		conn.SetPongHandler(func(string) error {
			return conn.SetReadDeadline(time.Now().Add(4 * time.Second))
		})
		readDone := make(chan struct{})
		go func() {
			defer close(readDone)
			for {
				if _, _, err := conn.ReadMessage(); err != nil {
					return
				}
			}
		}()

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
				lat:   39.30 + rng.Float64()*0.1,
				lon:   16.20 + rng.Float64()*0.1,
				pm25:  10 + rng.Float64()*30,
				pm10:  20 + rng.Float64()*50,
				no2:   5 + rng.Float64()*40,
				temp:  15 + rng.Float64()*15,
				humid: 40 + rng.Float64()*40,
			}
		}

		var lastPayload []byte

		for {
			select {
			case <-readDone:
				return
			case <-pingTicker.C:
				if err := conn.WriteControl(websocket.PingMessage, nil, time.Now().Add(time.Second)); err != nil {
					return
				}
			case <-ticker.C:
				if controller.controlled {
					controller.mu.Lock()
					running := controller.state == "running"
					remaining := controller.target - controller.sent
					controller.mu.Unlock()
					if !running || remaining <= 0 {
						break
					}
				}

				for i := 0; i < *stations; i++ {
					if controller.controlled {
						controller.mu.Lock()
						if controller.state != "running" || controller.sent >= controller.target {
							controller.mu.Unlock()
							break
						}
						controller.mu.Unlock()
					}

					b := &bases[i]

					r := Reading{
						StationID:   fmt.Sprintf("AQ-%03d", i),
						PM25:        b.pm25 + rng.Float64()*2 - 1,
						PM10:        b.pm10 + rng.Float64()*4 - 2,
						NO2:         b.no2 + rng.Float64()*3 - 1.5,
						Temperature: b.temp + rng.Float64()*0.6 - 0.3,
						Humidity:    b.humid + rng.Float64()*2 - 1,
						Lat:         b.lat,
						Lon:         b.lon,
						Timestamp:   time.Now().UnixMilli(),
					}

					// Simulate duplicates: re-send previous payload.
					data := lastPayload
					if lastPayload == nil || rng.Float64() >= *dupRatio {
						data, _ = json.Marshal(r)
						lastPayload = data
					}
					if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
						return
					}

					if controller.controlled {
						controller.mu.Lock()
						controller.sent++
						controller.bytesSent += int64(len(data))
						if controller.sent >= controller.target {
							controller.state = "complete"
							controller.completedAt = time.Now()
						}
						controller.mu.Unlock()
					}
				}
			}
		}
	})

	addr := fmt.Sprintf(":%d", *port)
	log.Printf("sensor-sim listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}
