#!/usr/bin/env bash
set -euo pipefail

ROOT="${HOME}/nephtys-pi-bench"
NODE_VERSION=24.16.0
NATS_VERSION=2.14.3

if [[ "$(uname -m)" != "aarch64" ]]; then
  echo "This setup requires 64-bit Raspberry Pi OS (aarch64)." >&2
  exit 1
fi

sudo apt-get update
sudo apt-get install -y curl xz-utils ca-certificates git jq
mkdir -p "${ROOT}/bin" "${ROOT}/nodered" "${ROOT}/run" "${ROOT}/node"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-arm64.tar.xz" -o "${tmp}/node.tar.xz"
tar -xJf "${tmp}/node.tar.xz" -C "${tmp}"
cp -a "${tmp}/node-v${NODE_VERSION}-linux-arm64/." "${ROOT}/node"

curl -fsSL "https://github.com/nats-io/nats-server/releases/download/v${NATS_VERSION}/nats-server-v${NATS_VERSION}-linux-arm64.tar.gz" -o "${tmp}/nats.tar.gz"
tar -xzf "${tmp}/nats.tar.gz" -C "${tmp}"
install -m 0755 "${tmp}/nats-server-v${NATS_VERSION}-linux-arm64/nats-server" "${ROOT}/bin/nats-server"

echo "Pi prerequisites installed under ${ROOT}. The Windows orchestrator uploads the benchmark binaries and Node-RED project."
