#!/bin/sh
set -eu

DEFAULT_OLLAMA_MODELS="llama3 mistral"
RAW_OLLAMA_MODELS="${OLLAMA_MODELS:-}"

if [ -z "${RAW_OLLAMA_MODELS}" ] ||
  [ "${RAW_OLLAMA_MODELS}" = '${OLLAMA_MODELS}' ] ||
  [ "${RAW_OLLAMA_MODELS}" = '${OLLAMA_MODELS:-llama3 mistral}' ] ||
  [ "${RAW_OLLAMA_MODELS}" = '${OLLAMA_MODELS:-"llama3 mistral"}' ]; then
  OLLAMA_MODELS="${DEFAULT_OLLAMA_MODELS}"
else
  # Normalize accidental surrounding quotes (for example: "llama3 mistral").
  OLLAMA_MODELS="$(printf '%s' "${RAW_OLLAMA_MODELS}" | sed -e 's/^"//' -e 's/"$//')"
fi

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
