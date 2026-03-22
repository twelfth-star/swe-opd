#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../shared/common.sh"

load_bootstrap_env model_serving

LOG_DIR="${SWE_OPD_PROJECT_ROOT}/outputs/model_serving"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/start_sglang.log"

nohup bash "${SCRIPT_DIR}/start_sglang.sh" >"${LOG_FILE}" 2>&1 &
pid=$!
echo "Started SGLang in background" >&2
echo "PID : ${pid}" >&2
echo "Log : ${LOG_FILE}" >&2
