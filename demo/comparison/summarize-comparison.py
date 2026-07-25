#!/usr/bin/env python3
"""Summarize valid Nephtys/Node-RED comparison trials."""

from __future__ import annotations

import argparse
import csv
import statistics
from pathlib import Path


METRICS = [
    ("Byte reduction (%)", "byte_reduction_pct"),
    ("Message reduction (%)", "message_reduction_pct"),
    ("Retained events", "output_events"),
    ("Throughput (events/s)", "throughput_eps"),
    ("Tool RSS mean (MB)", "tool_rss_mean_mb"),
    ("Tool RSS peak (MB)", "tool_rss_peak_mb"),
    ("Tool CPU mean (% of one logical CPU)", "tool_cpu_mean_pct"),
    ("NATS RSS mean (MB)", "nats_rss_mean_mb"),
    ("NATS CPU mean (%)", "nats_cpu_mean_pct"),
    ("Tool + NATS RSS mean (MB)", "stack_rss_mean_mb"),
    ("Latency p50 (ms)", "latency_p50_ms"),
    ("Latency p95 (ms)", "latency_p95_ms"),
]


def describe(rows: list[dict[str, str]], key: str) -> tuple[float, float]:
    values = [number(row[key]) for row in rows]
    return statistics.mean(values), statistics.stdev(values) if len(values) > 1 else 0.0


def number(value: str) -> float:
    """Parse PowerShell CSV numbers independently of the host locale."""
    return float(value.replace(",", "."))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv_path", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    with args.csv_path.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
    systems = {system: [row for row in rows if row["system"] == system] for system in ("nephtys", "nodered")}
    if not all(systems.values()):
        raise SystemExit("both Nephtys and Node-RED require valid rows")

    mismatches: list[str] = []
    for trial in sorted({int(row["trial"]) for row in rows}):
        hashes = {
            row["system"]: row["sequence_sha256"]
            for row in rows
            if int(row["trial"]) == trial
        }
        if len(hashes) != 2 or len(set(hashes.values())) != 1:
            mismatches.append(f"trial {trial}: {hashes}")
    if mismatches:
        raise SystemExit("semantic sequence mismatch: " + "; ".join(mismatches))

    lines = [
        "# Controlled Nephtys vs. Node-RED comparison",
        "",
        f"Valid trials: {len(systems['nephtys'])} per system. Values are arithmetic mean +/- sample SD.",
        "The timestamp-independent retained-event sequence matched between systems in every paired trial.",
        "",
        "| Metric | Nephtys | Node-RED |",
        "|---|---:|---:|",
    ]
    for label, key in METRICS:
        nephtys = describe(systems["nephtys"], key)
        nodered = describe(systems["nodered"], key)
        lines.append(
            f"| {label} | {nephtys[0]:.2f} +/- {nephtys[1]:.2f} | "
            f"{nodered[0]:.2f} +/- {nodered[1]:.2f} |"
        )

    lines.extend(["", "## Per-run results", ""])
    for row in sorted(rows, key=lambda item: int(item["order"])):
        lines.append(
            f"- Order {row['order']}: {row['system']} trial {row['trial']} - "
            f"bytes {number(row['byte_reduction_pct']):.2f}%, messages {number(row['message_reduction_pct']):.2f}%, "
            f"RSS {number(row['tool_rss_mean_mb']):.2f} MB, CPU {number(row['tool_cpu_mean_pct']):.2f}%, "
            f"p95 {number(row['latency_p95_ms']):.2f} ms."
        )

    output = "\n".join(lines) + "\n"
    print(output, end="")
    if args.output:
        args.output.write_text(output, encoding="utf-8")


if __name__ == "__main__":
    main()
