#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

BASE_COMPOSE="docker-compose.yml"
GPU_OVERRIDE="docker-compose.nvidia.yml"
TEMP_DOCKER_CONFIG=""

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

cleanup() {
  if [ -n "$TEMP_DOCKER_CONFIG" ] && [ -d "$TEMP_DOCKER_CONFIG" ]; then
    rm -rf "$TEMP_DOCKER_CONFIG"
  fi
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

prepare_docker_credentials_config() {
  docker_cfg_dir=${DOCKER_CONFIG:-"$HOME/.docker"}
  docker_cfg_file="$docker_cfg_dir/config.json"

  if [ ! -f "$docker_cfg_file" ]; then
    return
  fi

  helper=$(sed -n 's/.*"credsStore"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$docker_cfg_file" | head -n 1)
  if [ -z "$helper" ]; then
    return
  fi

  helper_bin="docker-credential-$helper"
  if command -v "$helper_bin" >/dev/null 2>&1 || command -v "$helper_bin.exe" >/dev/null 2>&1; then
    return
  fi

  TEMP_DOCKER_CONFIG=$(mktemp -d)
  export DOCKER_CONFIG="$TEMP_DOCKER_CONFIG"

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$docker_cfg_file" "$DOCKER_CONFIG/config.json" <<'PY'
import json,sys
src,dst=sys.argv[1],sys.argv[2]
with open(src,'r',encoding='utf-8') as f:
    data=json.load(f)
data.pop('credsStore',None)
data.pop('credHelpers',None)
with open(dst,'w',encoding='utf-8') as f:
    json.dump(data,f,indent=2,ensure_ascii=False)
    f.write('\n')
PY
  else
    # fallback: drop credsStore/credHelpers lines to avoid missing helper call
    sed '/"credsStore"/d;/"credHelpers"/d' "$docker_cfg_file" > "$DOCKER_CONFIG/config.json"
  fi

  warn "docker credential helper '$helper_bin' not found; using temporary DOCKER_CONFIG without credsStore/credHelpers."
  warn "If you need private registry auth, run 'docker login' (or fix Docker Desktop WSL integration)."
}

trap cleanup EXIT INT TERM

if [ ! -f "$BASE_COMPOSE" ]; then
  err "missing $BASE_COMPOSE in $ROOT_DIR"
fi

if [ ! -f "$GPU_OVERRIDE" ]; then
  err "missing $GPU_OVERRIDE in $ROOT_DIR"
fi

require_cmd curl
require_cmd docker

COMPOSE_CMD=$(resolve_compose_cmd)
prepare_docker_credentials_config

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
