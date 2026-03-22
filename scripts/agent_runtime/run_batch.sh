#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../shared/common.sh"

load_bootstrap_env agent_rollout
require_env MINI_SWE_AGENT_PLUS_ROOT
require_env REMOTE_MODEL_NAME

"${SCRIPT_DIR}/render_config.sh" >/dev/null

CONFIG_PATH="${REMOTE_CONFIG_OUTPUT_PATH:-${SWE_OPD_PROJECT_ROOT}/generated/bootstrap/mini_sweagent.remote_sglang.yaml}"
OUTPUT_ROOT="${SWEBENCH_OUTPUT_ROOT:-${SWE_OPD_PROJECT_ROOT}/outputs/agent_runtime/batch}"
if [[ -n "${SWEBENCH_OUTPUT_DIR:-}" ]]; then
    OUTPUT_DIR="${SWEBENCH_OUTPUT_DIR}"
else
    TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
    OUTPUT_DIR="${OUTPUT_ROOT}/${TIMESTAMP}"
fi
mkdir -p "${OUTPUT_DIR}"

exec "${MINI_PYTHON_BIN:-python3}" \
    "${MINI_SWE_AGENT_PLUS_ROOT}/src/minisweagent/run/extra/swebench_pool_way.py" \
    --subset "${SWEBENCH_SUBSET:-verified}" \
    --split "${SWEBENCH_SPLIT:-test}" \
    --model "${REMOTE_MODEL_NAME}" \
    --config "${CONFIG_PATH}" \
    --output "${OUTPUT_DIR}" \
    --workers "${SWEBENCH_WORKERS:-2}" \
    --docker-start-concurrency "${SWEBENCH_DOCKER_START_CONCURRENCY:-1}" \
    "$@"
