#!/bin/sh
set -eu

DEFAULT_BOOTSTRAP_MODELS="llama3 mistral"
RAW_BOOTSTRAP_MODELS="${BOOTSTRAP_MODELS:-}"

if [ -z "${RAW_BOOTSTRAP_MODELS}" ] ||
  [ "${RAW_BOOTSTRAP_MODELS}" = '${BOOTSTRAP_MODELS}' ] ||
  [ "${RAW_BOOTSTRAP_MODELS}" = '${BOOTSTRAP_MODELS:-llama3 mistral}' ] ||
  [ "${RAW_BOOTSTRAP_MODELS}" = '${BOOTSTRAP_MODELS:-"llama3 mistral"}' ]; then
  BOOTSTRAP_MODELS="${DEFAULT_BOOTSTRAP_MODELS}"
else
  # Normalize accidental surrounding quotes (for example: "llama3 mistral").
  BOOTSTRAP_MODELS="$(printf '%s' "${RAW_BOOTSTRAP_MODELS}" | sed -e 's/^"//' -e 's/"$//')"
fi

# NOTE: OLLAMA_MODELS is an official Ollama env var for model storage path.
# Do not overwrite it with model-name lists.
echo "[ai-server] bootstrap models: ${BOOTSTRAP_MODELS}"
if [ -n "${OLLAMA_MODELS:-}" ]; then
  echo "[ai-server] ollama model dir (OLLAMA_MODELS): ${OLLAMA_MODELS}"
fi

ollama serve &
OLLAMA_PID=$!

# wait API ready
until ollama list >/dev/null 2>&1; do
  sleep 1
done

for model in ${BOOTSTRAP_MODELS}; do
  echo "[ai-server] ensuring model: ${model}"
  ollama pull "${model}"

  # Wait until this model appears in local list (avoids race when checking too early).
  until ollama list | awk 'NR>1 {print $1}' | grep -Eq "^${model}(:|$)"; do
    echo "[ai-server] waiting model to appear in local list: ${model}"
    sleep 2
  done
done

echo "[ai-server] model bootstrap complete"

wait "${OLLAMA_PID}"
