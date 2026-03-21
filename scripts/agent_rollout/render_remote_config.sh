#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/common.sh"

load_bootstrap_env agent_rollout
require_env MINI_SWE_AGENT_PLUS_ROOT
require_env REMOTE_API_BASE
require_env REMOTE_MODEL_NAME

if [[ -n "${MINI_BASE_CONFIG:-}" ]]; then
    BASE_CONFIG="${MINI_BASE_CONFIG}"
else
    BASE_CONFIG="${MINI_SWE_AGENT_PLUS_ROOT}/src/minisweagent/config/extra/swebench_add_edit_tool.yaml"
fi

OUTPUT_PATH="${SWE_OPD_PROJECT_ROOT}/generated/bootstrap/mini_sweagent.remote_sglang.yaml"
if [[ -n "${REMOTE_CONFIG_OUTPUT_PATH:-}" ]]; then
    OUTPUT_PATH="${REMOTE_CONFIG_OUTPUT_PATH}"
fi
mkdir -p "$(dirname "${OUTPUT_PATH}")"

cmd=(
    "$(bootstrap_python_bin)" -m swe_opd.distributed_rollout render-mini-config
    --base-config "${BASE_CONFIG}"
    --output-path "${OUTPUT_PATH}"
    --model-name "${REMOTE_MODEL_NAME}"
    --api-base "${REMOTE_API_BASE}"
    --api-key "${REMOTE_API_KEY:-EMPTY}"
    --custom-llm-provider "${REMOTE_PROVIDER:-openai}"
    --temperature "${REMOTE_TEMPERATURE:-0.0}"
    --drop-params "${REMOTE_DROP_PARAMS:-true}"
)

if [[ -n "${REMOTE_EXTRA_MODEL_KWARGS_JSON:-}" ]]; then
    cmd+=(--extra-model-kwargs-json "${REMOTE_EXTRA_MODEL_KWARGS_JSON}")
fi

"${cmd[@]}"
