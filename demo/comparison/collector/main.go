package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"hash"
	"log"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/nats-io/nats.go"
)

type event struct {
	Station string  `json:"station"`
	PM25    float64 `json:"pm25"`
	NO2     float64 `json:"no2"`
	Temp    float64 `json:"temp"`
	TS      int64   `json:"ts"`
}

type counters struct {
	messages    int64
	bytes       int64
	events      int64
	malformed   int64
	negativeLat int64
	latencies   []float64
	sequence    hash.Hash
	firstEvents []event
	stations    map[string]int64
}

type snapshot struct {
	System             string           `json:"system"`
	OutputMessages     int64            `json:"output_messages"`
	OutputPayloadBytes int64            `json:"output_payload_bytes"`
	OutputEvents       int64            `json:"output_events"`
	MalformedMessages  int64            `json:"malformed_messages"`
	NegativeLatencies  int64            `json:"negative_latencies"`
	LatencyP50MS       float64          `json:"latency_p50_ms"`
	LatencyP95MS       float64          `json:"latency_p95_ms"`
	SequenceSHA256     string           `json:"sequence_sha256"`
	FirstEvents        []event          `json:"first_events,omitempty"`
	StationCounts      map[string]int64 `json:"station_counts,omitempty"`
}

type collector struct {
	mu      sync.Mutex
	systems map[string]*counters
}

func newCounters() *counters {
	return &counters{sequence: sha256.New(), stations: make(map[string]int64)}
}

func newCollector() *collector {
	return &collector{systems: map[string]*counters{
		"nephtys": newCounters(),
		"nodered": newCounters(),
	}}
}

func (c *collector) reset(system string) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if _, ok := c.systems[system]; !ok {
		return fmt.Errorf("unknown system %q", system)
	}
	c.systems[system] = newCounters()
	return nil
}

func percentile(values []float64, fraction float64) float64 {
	if len(values) == 0 {
		return 0
	}
	copyOfValues := append([]float64(nil), values...)
	sort.Float64s(copyOfValues)
	index := int(float64(len(copyOfValues)-1) * fraction)
	return copyOfValues[index]
}

func (c *collector) snapshot(system string) (snapshot, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	value, ok := c.systems[system]
	if !ok {
		return snapshot{}, fmt.Errorf("unknown system %q", system)
	}
	return snapshot{
		System:             system,
		OutputMessages:     value.messages,
		OutputPayloadBytes: value.bytes,
		OutputEvents:       value.events,
		MalformedMessages:  value.malformed,
		NegativeLatencies:  value.negativeLat,
		LatencyP50MS:       percentile(value.latencies, 0.50),
		LatencyP95MS:       percentile(value.latencies, 0.95),
		SequenceSHA256:     hex.EncodeToString(value.sequence.Sum(nil)),
		FirstEvents:        append([]event(nil), value.firstEvents...),
		StationCounts:      value.stations,
	}, nil
}

func normalizedPayload(data []byte) ([]byte, []event, error) {
	var envelope struct {
		Payload json.RawMessage `json:"payload"`
	}
	if len(data) == 0 {
		return nil, nil, errors.New("empty message")
	}

	normalized := data
	if data[0] == '{' {
		if err := json.Unmarshal(data, &envelope); err != nil {
			return nil, nil, err
		}
		if len(envelope.Payload) == 0 {
			return nil, nil, errors.New("Nephtys envelope has no payload")
		}
		normalized = envelope.Payload
	}

	var events []event
	if err := json.Unmarshal(normalized, &events); err != nil {
		return nil, nil, fmt.Errorf("decode normalized batch: %w", err)
	}
	return normalized, events, nil
}

func (c *collector) record(system string, data []byte) {
	normalized, events, err := normalizedPayload(data)
	now := time.Now().UnixMilli()

	c.mu.Lock()
	defer c.mu.Unlock()
	value, ok := c.systems[system]
	if !ok {
		return
	}
	if err != nil {
		value.malformed++
		return
	}
	value.messages++
	value.bytes += int64(len(normalized))
	for _, item := range events {
		value.events++
		if len(value.firstEvents) < 5 {
			value.firstEvents = append(value.firstEvents, item)
		}
		value.stations[item.Station]++
		latency := float64(now - item.TS)
		if latency < 0 {
			value.negativeLat++
		} else {
			value.latencies = append(value.latencies, latency)
		}
		canonical, _ := json.Marshal(struct {
			Station string  `json:"station"`
			PM25    float64 `json:"pm25"`
			NO2     float64 `json:"no2"`
			Temp    float64 `json:"temp"`
		}{item.Station, item.PM25, item.NO2, item.Temp})
		_, _ = value.sequence.Write(canonical)
		_, _ = value.sequence.Write([]byte{'\n'})
	}
}

func systemFromSubject(subject string) string {
	if strings.HasSuffix(subject, ".nephtys") {
		return "nephtys"
	}
	if strings.HasSuffix(subject, ".nodered") {
		return "nodered"
	}
	return ""
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func main() {
	natsURL := flag.String("nats", "nats://127.0.0.1:4322", "NATS server URL")
	httpAddr := flag.String("http", "127.0.0.1:9092", "HTTP control address")
	createStream := flag.Bool("create-stream", true, "create the comparison JetStream stream")
	flag.Parse()

	nc, err := nats.Connect(*natsURL, nats.Name("nephtys-comparison-collector"))
	if err != nil {
		log.Fatalf("connect to NATS: %v", err)
	}
	defer nc.Close()

	if *createStream {
		js, err := nc.JetStream()
		if err != nil {
			log.Fatalf("JetStream context: %v", err)
		}
		if _, err := js.StreamInfo("NEPHTYS"); errors.Is(err, nats.ErrStreamNotFound) {
			if _, err := js.AddStream(&nats.StreamConfig{
				Name:     "NEPHTYS",
				Subjects: []string{"nephtys.stream.>"},
				Storage:  nats.MemoryStorage,
			}); err != nil {
				log.Fatalf("create comparison stream: %v", err)
			}
		} else if err != nil {
			log.Fatalf("inspect comparison stream: %v", err)
		}
	}

	state := newCollector()
	if _, err := nc.Subscribe("nephtys.stream.compare.*", func(message *nats.Msg) {
		if system := systemFromSubject(message.Subject); system != "" {
			state.record(system, message.Data)
		}
	}); err != nil {
		log.Fatalf("subscribe: %v", err)
	}
	if err := nc.Flush(); err != nil {
		log.Fatalf("flush subscription: %v", err)
	}

	http.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	http.HandleFunc("/reset", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "POST required"})
			return
		}
		if err := state.reset(r.URL.Query().Get("system")); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "reset"})
	})
	http.HandleFunc("/snapshot", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "GET required"})
			return
		}
		value, err := state.snapshot(r.URL.Query().Get("system"))
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, value)
	})

	log.Printf("collector listening on http://%s", *httpAddr)
	log.Fatal(http.ListenAndServe(*httpAddr, nil))
}
