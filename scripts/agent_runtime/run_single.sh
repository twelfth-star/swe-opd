#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../shared/common.sh"

load_bootstrap_env agent_rollout
require_env MINI_SWE_AGENT_PLUS_ROOT
require_env REMOTE_MODEL_NAME

INSTANCE_SPEC="${1:-${SWEBENCH_INSTANCE:-}}"
if [[ -z "${INSTANCE_SPEC}" ]]; then
    echo "Usage: bash scripts/agent_runtime/run_single.sh <instance_id_or_index>" >&2
    exit 1
fi

"${SCRIPT_DIR}/render_config.sh" >/dev/null

CONFIG_PATH="${REMOTE_CONFIG_OUTPUT_PATH:-${SWE_OPD_PROJECT_ROOT}/generated/bootstrap/mini_sweagent.remote_sglang.yaml}"
OUTPUT_DIR="${SWEBENCH_OUTPUT_ROOT:-${SWE_OPD_PROJECT_ROOT}/outputs/agent_runtime/single}"
mkdir -p "${OUTPUT_DIR}"
OUTPUT_FILE="${OUTPUT_DIR}/${INSTANCE_SPEC}.traj.json"

exec "${MINI_PYTHON_BIN:-python3}" \
    "${MINI_SWE_AGENT_PLUS_ROOT}/src/minisweagent/run/extra/swebench_single.py" \
    --subset "${SWEBENCH_SUBSET:-verified}" \
    --split "${SWEBENCH_SPLIT:-test}" \
    --instance "${INSTANCE_SPEC}" \
    --model "${REMOTE_MODEL_NAME}" \
    --config "${CONFIG_PATH}" \
    --output "${OUTPUT_FILE}" \
    "${@:2}"
