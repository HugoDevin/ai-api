#!/bin/sh
set -eu

OLLAMA_MODELS="${OLLAMA_MODELS:-llama3 mistral}"

ollama serve &
OLLAMA_PID=$!

# wait API ready
until ollama list >/dev/null 2>&1; do
  sleep 1
done

echo "[ai-server] configured models: ${OLLAMA_MODELS}"

for model in ${OLLAMA_MODELS}; do
  echo "[ai-server] ensuring model: ${model}"
  ollama pull "${model}"
done

wait "${OLLAMA_PID}"
