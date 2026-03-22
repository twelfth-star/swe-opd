#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../shared/common.sh"

load_bootstrap_env model_serving

REMOTE_PORT="${SGLANG_TUNNEL_REMOTE_PORT:-32000}"
LOG_DIR="${SWE_OPD_PROJECT_ROOT}/outputs/model_serving"
PID_FILE="${LOG_DIR}/model_tunnel_${REMOTE_PORT}.pid"
LOG_FILE="${LOG_DIR}/model_tunnel_${REMOTE_PORT}.log"

if [[ -f "${PID_FILE}" ]]; then
    pid="$(cat "${PID_FILE}")"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
        echo "Model reverse tunnel is running with PID ${pid}"
    else
        echo "Model reverse tunnel pid file exists but PID is not alive: ${pid}"
    fi
else
    echo "Model reverse tunnel is not running"
fi

if [[ -f "${LOG_FILE}" ]]; then
    echo
    echo "Log tail:"
    tail -n 20 "${LOG_FILE}"
fi
