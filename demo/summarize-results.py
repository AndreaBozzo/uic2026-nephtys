#!/usr/bin/env python3
"""Summarize retained Nephtys benchmark CSV rows as mean and sample SD."""

from __future__ import annotations

import argparse
import csv
import statistics
from pathlib import Path


def delta(row: dict[str, str], end: str, start: str) -> float:
    return float(row[end]) - float(row[start])


def reduction(output: float, input_: float) -> float:
    return 100.0 * (1.0 - output / input_) if input_ else 0.0


def describe(values: list[float]) -> tuple[float, float]:
    return statistics.mean(values), statistics.stdev(values) if len(values) > 1 else 0.0


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv_path", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    with args.csv_path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) < 3:
        raise SystemExit(f"expected at least 3 retained runs, found {len(rows)}")

    metrics: dict[str, list[float]] = {
        "Synthetic baseline bytes": [],
        "Synthetic pipeline bytes": [],
        "Synthetic byte reduction (%)": [],
        "Synthetic baseline messages": [],
        "Synthetic pipeline messages": [],
        "Synthetic message reduction (%)": [],
        "Real-data input bytes": [],
        "Real-data published bytes": [],
        "Real-data byte reduction (%)": [],
        "Real-data input messages": [],
        "Real-data published messages": [],
        "Real-data message reduction (%)": [],
        "RSS (MB)": [],
    }

    for row in rows:
        synthetic_bytes_in = delta(row, "bl_bytes_in_1", "bl_bytes_in_0")
        synthetic_bytes_out = delta(row, "pl_bytes_pub_1", "pl_bytes_pub_0")
        synthetic_events_in = delta(row, "bl_events_in_1", "bl_events_in_0")
        synthetic_events_out = delta(row, "pl_events_pub_1", "pl_events_pub_0")
        real_bytes_in = delta(row, "real_bytes_in_1", "real_bytes_in_0")
        real_bytes_out = delta(row, "real_bytes_pub_1", "real_bytes_pub_0")
        real_events_in = delta(row, "real_events_in_1", "real_events_in_0")
        real_events_out = delta(row, "real_events_pub_1", "real_events_pub_0")

        metrics["Synthetic baseline bytes"].append(synthetic_bytes_in)
        metrics["Synthetic pipeline bytes"].append(synthetic_bytes_out)
        metrics["Synthetic byte reduction (%)"].append(
            reduction(synthetic_bytes_out, synthetic_bytes_in)
        )
        metrics["Synthetic baseline messages"].append(synthetic_events_in)
        metrics["Synthetic pipeline messages"].append(synthetic_events_out)
        metrics["Synthetic message reduction (%)"].append(
            reduction(synthetic_events_out, synthetic_events_in)
        )
        metrics["Real-data input bytes"].append(real_bytes_in)
        metrics["Real-data published bytes"].append(real_bytes_out)
        metrics["Real-data byte reduction (%)"].append(
            reduction(real_bytes_out, real_bytes_in)
        )
        metrics["Real-data input messages"].append(real_events_in)
        metrics["Real-data published messages"].append(real_events_out)
        metrics["Real-data message reduction (%)"].append(
            reduction(real_events_out, real_events_in)
        )
        metrics["RSS (MB)"].append(float(row["rss_mb"]))

    lines = [
        f"# Benchmark summary ({len(rows)} runs)",
        "",
        "Values are arithmetic mean and sample standard deviation.",
        "",
        "| Metric | Mean | SD |",
        "|---|---:|---:|",
    ]
    for name, values in metrics.items():
        mean, sd = describe(values)
        if "%" in name or "RSS" in name:
            lines.append(f"| {name} | {mean:.2f} | {sd:.2f} |")
        else:
            lines.append(f"| {name} | {mean:,.0f} | {sd:,.0f} |")

    lines.extend(["", "## Per-run derived values", ""])
    for index, row in enumerate(rows, start=1):
        synthetic_bytes_in = delta(row, "bl_bytes_in_1", "bl_bytes_in_0")
        synthetic_bytes_out = delta(row, "pl_bytes_pub_1", "pl_bytes_pub_0")
        synthetic_events_in = delta(row, "bl_events_in_1", "bl_events_in_0")
        synthetic_events_out = delta(row, "pl_events_pub_1", "pl_events_pub_0")
        real_bytes_in = delta(row, "real_bytes_in_1", "real_bytes_in_0")
        real_bytes_out = delta(row, "real_bytes_pub_1", "real_bytes_pub_0")
        real_events_in = delta(row, "real_events_in_1", "real_events_in_0")
        real_events_out = delta(row, "real_events_pub_1", "real_events_pub_0")
        lines.append(
            f"- Run {row.get('run_id', index)}: synthetic "
            f"{reduction(synthetic_bytes_out, synthetic_bytes_in):.2f}% bytes / "
            f"{reduction(synthetic_events_out, synthetic_events_in):.2f}% messages; "
            f"real-data {reduction(real_bytes_out, real_bytes_in):.2f}% bytes / "
            f"{reduction(real_events_out, real_events_in):.2f}% messages; "
            f"RSS {float(row['rss_mb']):.2f} MB."
        )

    output = "\n".join(lines) + "\n"
    print(output, end="")
    if args.output:
        args.output.write_text(output, encoding="utf-8")


if __name__ == "__main__":
    main()
