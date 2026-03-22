#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../shared/common.sh"

load_bootstrap_env model_serving

SGLANG_HOST="${SGLANG_HOST:-127.0.0.1}"
SGLANG_PORT="${SGLANG_PORT:-30000}"
SGLANG_API_KEY="${SGLANG_API_KEY:-EMPTY}"
SGLANG_SMOKE_PROMPT="${SGLANG_SMOKE_PROMPT:-Reply with exactly: bootstrap-ok}"

if [[ -n "${SGLANG_MODEL_NAME:-}" ]]; then
    MODEL_NAME="${SGLANG_MODEL_NAME}"
else
    MODEL_NAME="${SGLANG_MODEL_PATH}"
fi

"$(bootstrap_python_bin)" -m swe_opd.distributed_rollout probe-sglang \
    --api-base "http://${SGLANG_HOST}:${SGLANG_PORT}"

"$(bootstrap_python_bin)" -m swe_opd.distributed_rollout openai-smoke \
    --api-base "http://${SGLANG_HOST}:${SGLANG_PORT}" \
    --api-key "${SGLANG_API_KEY}" \
    --model-name "${MODEL_NAME}" \
    --prompt "${SGLANG_SMOKE_PROMPT}"
