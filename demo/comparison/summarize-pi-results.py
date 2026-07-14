#!/usr/bin/env python3
import csv
import json
import statistics
import sys
from pathlib import Path

METRICS = [
    ("byte_reduction_percent", "Byte reduction", "%"),
    ("message_reduction_percent", "Message reduction", "%"),
    ("tool_rss_mean_mb", "Tool RSS mean", "MB"),
    ("stack_rss_mean_mb", "Tool + NATS RSS mean", "MB"),
    ("tool_cpu_mean_percent", "Tool CPU", "% one logical CPU"),
    ("latency_p50_ms", "Latency p50", "ms"),
    ("latency_p95_ms", "Latency p95", "ms"),
    ("temperature_mean_c", "SoC temperature mean", "C"),
    ("temperature_peak_c", "SoC temperature peak", "C"),
    ("power_mean_w", "Wall power mean", "W"),
    ("energy_wh", "Wall energy per run", "Wh"),
    ("joules_per_input_event", "Energy per input event", "J/event"),
]


def number(value: str) -> float:
    return float(value.replace(",", "."))


def main() -> None:
    root = Path(sys.argv[1])
    with (root / "runs.csv").open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
    valid = [row for row in rows if row.get("valid", "").lower() == "true"]
    grouped = {system: [r for r in valid if r["system"] == system] for system in ("nephtys", "nodered")}
    if any(len(grouped[s]) != 3 for s in grouped):
        raise SystemExit("Summary requires exactly three valid trials per system")
    for trial in (1, 2, 3):
        pair = [r for r in valid if int(r["trial"]) == trial]
        if len(pair) != 2 or pair[0]["sequence_sha256"] != pair[1]["sequence_sha256"]:
            raise SystemExit(f"Sequence mismatch in trial {trial}")

    lines = ["# Raspberry Pi 5 controlled comparison", "", "Three valid trials per system; arithmetic mean +/- sample SD.", "",
             "| Metric | Nephtys | Node-RED |", "|---|---:|---:|"]
    machine = {}
    for key, label, unit in METRICS:
        machine[key] = {}
        cells = []
        for system in ("nephtys", "nodered"):
            values = [number(r[key]) for r in grouped[system]]
            mean, sd = statistics.mean(values), statistics.stdev(values)
            machine[key][system] = {"mean": mean, "sample_sd": sd, "unit": unit}
            cells.append(f"{mean:.2f} +/- {sd:.2f} {unit}")
        lines.append(f"| {label} | {cells[0]} | {cells[1]} |")
    lines += ["", "Power covers the complete Pi and official PSU. No idle baseline is subtracted.",
              "Energy superiority must not be claimed when differences are within meter resolution or trial variability."]
    (root / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (root / "summary.json").write_text(json.dumps(machine, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
