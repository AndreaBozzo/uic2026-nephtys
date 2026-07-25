#!/usr/bin/env bash
# Run the paper benchmark repeatedly and retain raw aggregate counters.
#
# Usage: ./run-repeated-benchmarks.sh [REPETITIONS] [SIM_DURATION] [REAL_DURATION]
# Defaults: 3 repetitions, 5 min synthetic, 30 min live-data per repetition.

set -euo pipefail

REPETITIONS="${1:-3}"
SIM_DURATION="${2:-300}"
REAL_DURATION="${3:-1800}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RESULTS_DIR="${RESULTS_DIR:-results/$STAMP}"
RESULTS_CSV="$RESULTS_DIR/runs.csv"

if ! [[ "$REPETITIONS" =~ ^[1-9][0-9]*$ ]]; then
  echo "REPETITIONS must be a positive integer" >&2
  exit 2
fi

mkdir -p "$RESULTS_DIR"
{
  echo "timestamp_utc=$STAMP"
  echo "repetitions=$REPETITIONS"
  echo "synthetic_duration_s=$SIM_DURATION"
  echo "real_duration_s=$REAL_DURATION"
  echo "host=$(uname -a)"
  echo "python=$($PYTHON_BIN --version 2>&1)"
  echo "sensor_sim_seed=2646958770"
} > "$RESULTS_DIR/metadata.txt"

for ((run = 1; run <= REPETITIONS; run++)); do
  echo "==> Repetition $run/$REPETITIONS"
  RUN_ID="$run" RESULTS_CSV="$RESULTS_CSV" \
    ./run-benchmarks.sh "$SIM_DURATION" "$REAL_DURATION" \
    | tee "$RESULTS_DIR/run-$run.log"
done

"$PYTHON_BIN" ./summarize-results.py "$RESULTS_CSV" \
  --output "$RESULTS_DIR/summary.md"
echo "Repeated benchmark complete. Results: $RESULTS_DIR"
