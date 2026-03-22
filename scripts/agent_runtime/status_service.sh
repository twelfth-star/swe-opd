#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../shared/common.sh"

load_bootstrap_env rollout_service

LOG_DIR="${SWE_OPD_PROJECT_ROOT}/outputs/rollout_service"
PID_FILE="${LOG_DIR}/rollout_service.pid"
LOG_FILE="${LOG_DIR}/rollout_service.log"
HOST="${ROLLOUT_SERVICE_HOST:-0.0.0.0}"
PORT="${ROLLOUT_SERVICE_PORT:-18080}"

if [[ -f "${PID_FILE}" ]]; then
    pid="$(cat "${PID_FILE}")"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
        echo "Rollout service is running with PID ${pid}"
    else
        echo "Rollout service pid file exists but PID is not alive: ${pid}"
    fi
else
    echo "Rollout service is not running"
fi

echo "Health URL: http://${HOST}:${PORT}/healthz"
if [[ -f "${LOG_FILE}" ]]; then
    echo
    echo "Log tail:"
    tail -n 20 "${LOG_FILE}"
fi
