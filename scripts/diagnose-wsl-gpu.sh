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
echo
CMD1="podman run --rm --device /dev/dxg:/dev/dxg -v /usr/lib/wsl/lib:/usr/lib/wsl/lib:ro -e LD_LIBRARY_PATH=/usr/lib/wsl/lib docker.io/nvidia/cuda:12.4.1-base-ubuntu22.04 /bin/sh -lc 'command -v nvidia-smi || true; command -v /usr/lib/wsl/lib/nvidia-smi || true; /usr/lib/wsl/lib/nvidia-smi || nvidia-smi'"
echo "$ $CMD1"
OUT1=$(sh -c "$CMD1" 2>&1 || true)
echo "$OUT1"

echo
CMD2="podman run --rm --privileged --device /dev/dxg:/dev/dxg -v /usr/lib/wsl/lib:/usr/lib/wsl/lib:ro -e LD_LIBRARY_PATH=/usr/lib/wsl/lib docker.io/nvidia/cuda:12.4.1-base-ubuntu22.04 /bin/sh -lc '/usr/lib/wsl/lib/nvidia-smi || nvidia-smi'"
echo "$ $CMD2"
OUT2=$(sh -c "$CMD2" 2>&1 || true)
echo "$OUT2"

if printf '%s\n%s\n' "$OUT1" "$OUT2" | grep -q "Driver Not Loaded"; then
  echo
  echo "[wsl-gpu-diagnose][RESULT] Podman-in-container NVML check failed with 'Driver Not Loaded'."
  echo "[wsl-gpu-diagnose][RESULT] This indicates a Podman+WSL runtime integration limitation (not Spring Boot code)."
  echo "[wsl-gpu-diagnose][NEXT] Recommended path: run Ollama via Docker GPU runtime or directly on WSL host."
fi

log "Done. Share full output for diagnosis."
