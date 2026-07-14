package main

import (
	"encoding/json"
	"testing"
)

func TestNormalizedPayload(t *testing.T) {
	batch := `[ {"station":"AQ-001","pm25":12.5,"no2":4,"temp":20,"ts":1000} ]`
	envelope, err := json.Marshal(map[string]any{
		"source":  "test",
		"payload": json.RawMessage(batch),
	})
	if err != nil {
		t.Fatal(err)
	}

	for _, input := range [][]byte{[]byte(batch), envelope} {
		normalized, events, err := normalizedPayload(input)
		if err != nil {
			t.Fatalf("normalize: %v", err)
		}
		if len(events) != 1 || events[0].Station != "AQ-001" {
			t.Fatalf("unexpected events: %#v", events)
		}
		if len(normalized) == 0 {
			t.Fatal("normalized payload is empty")
		}
	}
}

func TestCollectorSequenceIgnoresTimestamp(t *testing.T) {
	c := newCollector()
	c.record("nodered", []byte(`[{"station":"AQ-001","pm25":12.5,"no2":4,"temp":20,"ts":1000}]`))
	first, err := c.snapshot("nodered")
	if err != nil {
		t.Fatal(err)
	}
	if err := c.reset("nodered"); err != nil {
		t.Fatal(err)
	}
	c.record("nodered", []byte(`[{"station":"AQ-001","pm25":12.5,"no2":4,"temp":20,"ts":2000}]`))
	second, err := c.snapshot("nodered")
	if err != nil {
		t.Fatal(err)
	}
	if first.SequenceSHA256 != second.SequenceSHA256 {
		t.Fatalf("sequence hash changed with timestamp: %s != %s", first.SequenceSHA256, second.SequenceSHA256)
	}
}
