#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../shared/common.sh"

load_bootstrap_env rollout_service
load_bootstrap_env agent_rollout

LOG_DIR="${SWE_OPD_PROJECT_ROOT}/outputs/rollout_service"
mkdir -p "${LOG_DIR}"
PID_FILE="${LOG_DIR}/rollout_service.pid"
LOG_FILE="${LOG_DIR}/rollout_service.log"

if [[ -f "${PID_FILE}" ]]; then
    existing_pid="$(cat "${PID_FILE}")"
    if [[ -n "${existing_pid}" ]] && kill -0 "${existing_pid}" 2>/dev/null; then
        echo "Rollout service already running with PID ${existing_pid}" >&2
        exit 0
    fi
    rm -f "${PID_FILE}"
fi

nohup bash "${SCRIPT_DIR}/start_service.sh" >"${LOG_FILE}" 2>&1 &
pid=$!
echo "${pid}" >"${PID_FILE}"

echo "Started rollout service in background" >&2
echo "PID file : ${PID_FILE}" >&2
echo "Log file : ${LOG_FILE}" >&2
echo "PID      : ${pid}" >&2

# To check if the service is running, you can use:
# ps -ef | grep -E "sglang|sglang_router" | grep -v grep
