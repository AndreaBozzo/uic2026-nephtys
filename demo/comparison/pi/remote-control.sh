#!/usr/bin/env bash
set -euo pipefail

ROOT="${HOME}/nephtys-pi-bench"
RUN="${ROOT}/run"
mkdir -p "${RUN}"

pid_file() { printf '%s/%s.pid' "${RUN}" "$1"; }
read_pid() { [[ -f "$(pid_file "$1")" ]] && cat "$(pid_file "$1")" || true; }
stop_one() {
  local name="$1" pid
  pid="$(read_pid "${name}")"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}" 2>/dev/null || true
    for _ in {1..50}; do kill -0 "${pid}" 2>/dev/null || break; sleep 0.1; done
    kill -9 "${pid}" 2>/dev/null || true
  fi
  rm -f "$(pid_file "${name}")"
}
start_bg() {
  local name="$1"; shift
  stop_one "${name}"
  nohup "$@" >"${RUN}/${name}.out" 2>"${RUN}/${name}.err" &
  echo $! >"$(pid_file "${name}")"
}
proc_json() {
  local name="$1" pid rss ticks
  pid="$(read_pid "${name}")"
  if [[ -z "${pid}" ]] || [[ ! -r "/proc/${pid}/stat" ]]; then
    printf '"%s":null' "${name}"
    return
  fi
  rss="$(awk '/^VmRSS:/{print $2}' "/proc/${pid}/status")"
  ticks="$(awk '{print $14+$15}' "/proc/${pid}/stat")"
  printf '"%s":{"pid":%s,"rss_kb":%s,"cpu_ticks":%s}' "${name}" "${pid}" "${rss:-0}" "${ticks:-0}"
}

case "${1:-}" in
  start-nats)
    stop_one nats
    rm -rf "${RUN}/jetstream" && mkdir -p "${RUN}/jetstream"
    start_bg nats "${ROOT}/bin/nats-server" -js -p 4322 -m 8322 -sd "${RUN}/jetstream"
    ;;
  start-nephtys)
    start_bg tool env NATS_URL=nats://127.0.0.1:4322 NEPHTYS_PORT=3002 NEPHTYS_ADMIN_TOKEN=bench "${ROOT}/bin/nephtys"
    ;;
  start-nodered)
    start_bg tool "${ROOT}/node/bin/node" "${ROOT}/nodered/node_modules/node-red/red.js" --userDir "${ROOT}/nodered" --settings "${ROOT}/nodered/settings.js" --port 1880
    ;;
  stop-tool) stop_one tool ;;
  stop-all) stop_one tool; stop_one nats ;;
  sample)
    temp="$(vcgencmd measure_temp | sed -E "s/[^0-9.]*([0-9]+\.[0-9]+).*/\1/")"
    throttle="$(vcgencmd get_throttled | cut -d= -f2)"
    freq="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo 0)"
    printf '{'; proc_json tool; printf ','; proc_json nats
    printf ',"temperature_c":%s,"frequency_khz":%s,"throttled":"%s","clock_ticks":%s,"logical_cpus":%s}\n' "${temp:-0}" "${freq:-0}" "${throttle}" "$(getconf CLK_TCK)" "$(nproc)"
    ;;
  metadata)
    printf '{"model":%s,"kernel":%s,"os":%s,"governor":%s,"firmware":%s}\n' \
      "$(jq -Rs . </proc/device-tree/model)" "$(uname -r | jq -Rs .)" \
      "$(grep PRETTY_NAME /etc/os-release | cut -d= -f2- | tr -d '"' | jq -Rs .)" \
      "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor | jq -Rs .)" \
      "$(vcgencmd version | tr '\n' ' ' | jq -Rs .)"
    ;;
  logs)
    tar -C "${RUN}" -czf - .
    ;;
  *) echo "usage: $0 {start-nats|start-nephtys|start-nodered|stop-tool|stop-all|sample|metadata|logs}" >&2; exit 2 ;;
esac
