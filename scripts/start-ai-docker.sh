#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

BASE_COMPOSE="docker-compose.yml"
GPU_OVERRIDE="docker-compose.nvidia.yml"

log() {
  echo "[docker-ai-start] $*"
}

warn() {
  echo "[docker-ai-start][WARN] $*" >&2
}

err() {
  echo "[docker-ai-start][ERROR] $*" >&2
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "missing required command: $1"
  fi
}

resolve_compose_cmd() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    echo "docker compose"
    return
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
    return
  fi

  err "docker compose plugin not found (and docker-compose not installed)."
}

if [ ! -f "$BASE_COMPOSE" ]; then
  err "missing $BASE_COMPOSE in $ROOT_DIR"
fi

if [ ! -f "$GPU_OVERRIDE" ]; then
  err "missing $GPU_OVERRIDE in $ROOT_DIR"
fi

require_cmd curl
require_cmd docker

COMPOSE_CMD=$(resolve_compose_cmd)

if command -v nvidia-smi >/dev/null 2>&1; then
  log "nvidia-smi detected on host."
  nvidia-smi >/dev/null 2>&1 || warn "host nvidia-smi returned non-zero."
else
  warn "nvidia-smi not found. Container may run in CPU mode."
fi

log "Stopping existing stack (if any)..."
sh -c "$COMPOSE_CMD -f '$BASE_COMPOSE' -f '$GPU_OVERRIDE' down" || true

log "Starting ai stack with Docker + NVIDIA override..."
sh -c "$COMPOSE_CMD -f '$BASE_COMPOSE' -f '$GPU_OVERRIDE' up -d --build"

log "Waiting for Ollama API /api/tags on http://127.0.0.1:11434 ..."
i=1
while [ "$i" -le 45 ]; do
  if curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    log "Ollama API is ready."
    break
  fi

  if [ "$i" -eq 45 ]; then
    warn "Ollama API not ready after timeout. Showing ai-server logs..."
    sh -c "$COMPOSE_CMD -f '$BASE_COMPOSE' -f '$GPU_OVERRIDE' logs --tail=200 ai-server" || true
    exit 1
  fi

  i=$((i + 1))
  sleep 2
done

log "Runtime check (processor/model):"
sh -c "$COMPOSE_CMD -f '$BASE_COMPOSE' -f '$GPU_OVERRIDE' exec ai-server ollama ps" || warn "ollama ps failed"

log "Done. Useful follow-up commands:"
echo "  $COMPOSE_CMD -f $BASE_COMPOSE -f $GPU_OVERRIDE logs -f ai-server"
echo "  $COMPOSE_CMD -f $BASE_COMPOSE -f $GPU_OVERRIDE exec ai-server ollama run llama3 \"hello\""
echo "  curl http://127.0.0.1:11434/api/tags"
