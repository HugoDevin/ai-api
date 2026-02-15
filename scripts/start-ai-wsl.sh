#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

BASE_COMPOSE="podman-compose.yml"
WSL_OVERRIDE="podman-compose.nvidia.wsl.yml"
LEGACY_OVERRIDE="podman-compose.nvidia.legacy.yml"

log() {
  echo "[wsl-ai-start] $*"
}

warn() {
  echo "[wsl-ai-start][WARN] $*" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[wsl-ai-start][ERROR] missing required command: $1" >&2
    exit 1
  fi
}

use_file="$WSL_OVERRIDE"

require_cmd podman-compose
require_cmd curl

if ! command -v nvidia-smi >/dev/null 2>&1; then
  warn "nvidia-smi not found. If you expect GPU, install NVIDIA driver/toolkit first."
else
  log "nvidia-smi detected."
  nvidia-smi >/dev/null 2>&1 || warn "nvidia-smi command returned non-zero."
fi

if [ ! -f "$BASE_COMPOSE" ]; then
  echo "[wsl-ai-start][ERROR] missing $BASE_COMPOSE in $ROOT_DIR" >&2
  exit 1
fi

if [ ! -f "$WSL_OVERRIDE" ]; then
  echo "[wsl-ai-start][ERROR] missing $WSL_OVERRIDE in $ROOT_DIR" >&2
  exit 1
fi

if [ ! -e /dev/dxg ]; then
  warn "/dev/dxg not found; WSL GPU path not available. Falling back to legacy override."
  if [ -f "$LEGACY_OVERRIDE" ]; then
    use_file="$LEGACY_OVERRIDE"
  else
    warn "legacy override file not found; continuing with WSL override."
  fi
fi

log "Stopping existing stack..."
podman-compose down || true

log "Starting ai stack with override: $use_file"
podman-compose -f "$BASE_COMPOSE" -f "$use_file" up -d --build

log "Waiting for Ollama API /api/tags on http://127.0.0.1:11434 ..."
i=1
while [ "$i" -le 30 ]; do
  if curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    log "Ollama API is ready."
    break
  fi

  if [ "$i" -eq 30 ]; then
    echo "[wsl-ai-start][ERROR] Ollama API not ready after timeout." >&2
    podman-compose logs --tail=200 ai-server || true
    exit 1
  fi

  i=$((i + 1))
  sleep 2
done

log "Checking GPU-related files inside container..."
podman-compose exec ai-server sh -c 'ls -l /dev/dxg 2>/dev/null || true; ls -l /usr/lib/wsl/lib/libcuda.so.1 2>/dev/null || true'

log "Showing Ollama runtime processors/models..."
podman-compose exec ai-server ollama ps || warn "ollama ps failed"

log "Done. Useful follow-up commands:"
echo "  podman-compose logs -f ai-server"
echo "  podman-compose exec ai-server ollama run llama3 \"hello\""
echo "  curl http://127.0.0.1:11434/api/tags"
