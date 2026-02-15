#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

log() {
  echo "[wsl-gpu-diagnose] $*"
}

try_cmd() {
  echo
  echo "$ $*"
  sh -c "$*" || true
}

log "Host baseline"
try_cmd "uname -a"
try_cmd "cat /etc/os-release"
try_cmd "podman --version"
try_cmd "podman-compose --version"
try_cmd "nvidia-smi"
try_cmd "ls -l /dev/dxg"
try_cmd "ls -l /usr/lib/wsl/lib/libcuda.so.1"

log "Container status"
try_cmd "podman-compose ps"
try_cmd "podman-compose exec ai-server sh -c 'ls -l /dev/dxg; ls -l /usr/lib/wsl/lib/libcuda.so.1'"
try_cmd "podman-compose exec ai-server ollama ps"

log "Force one inference, then re-check processor"
try_cmd "podman-compose exec ai-server ollama run llama3 'gpu check ping'"
try_cmd "podman-compose exec ai-server ollama ps"

log "Ollama logs (last 300 lines)"
try_cmd "podman-compose logs --tail=300 ai-server"

log "Podman direct CUDA checks"
try_cmd "podman run --rm --device /dev/dxg:/dev/dxg -v /usr/lib/wsl/lib:/usr/lib/wsl/lib:ro -e LD_LIBRARY_PATH=/usr/lib/wsl/lib docker.io/nvidia/cuda:12.4.1-base-ubuntu22.04 /bin/sh -lc 'command -v nvidia-smi || true; command -v /usr/lib/wsl/lib/nvidia-smi || true; /usr/lib/wsl/lib/nvidia-smi || nvidia-smi'"
try_cmd "podman run --rm --privileged --device /dev/dxg:/dev/dxg -v /usr/lib/wsl/lib:/usr/lib/wsl/lib:ro -e LD_LIBRARY_PATH=/usr/lib/wsl/lib docker.io/nvidia/cuda:12.4.1-base-ubuntu22.04 /bin/sh -lc '/usr/lib/wsl/lib/nvidia-smi || nvidia-smi'"

log "Done. Share full output for diagnosis."
