#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../shared/common.sh"

load_bootstrap_env agent_rollout
require_env REMOTE_API_BASE
require_env REMOTE_MODEL_NAME

"${SCRIPT_DIR}/render_config.sh"

"$(bootstrap_python_bin)" -m swe_opd.distributed_rollout openai-smoke \
    --api-base "${REMOTE_API_BASE}" \
    --api-key "${REMOTE_API_KEY:-EMPTY}" \
    --model-name "${REMOTE_MODEL_NAME}" \
    --prompt "${REMOTE_SMOKE_PROMPT:-Reply with exactly: bootstrap-ok}"

"$(bootstrap_python_bin)" -m swe_opd.distributed_rollout litellm-smoke \
    --api-base "${REMOTE_API_BASE}" \
    --api-key "${REMOTE_API_KEY:-EMPTY}" \
    --model-name "${REMOTE_MODEL_NAME}" \
    --custom-llm-provider "${REMOTE_PROVIDER:-openai}" \
    --temperature "${REMOTE_TEMPERATURE:-0.0}" \
    --drop-params "${REMOTE_DROP_PARAMS:-true}" \
    --prompt "${REMOTE_SMOKE_PROMPT:-Reply with exactly: bootstrap-ok}"
