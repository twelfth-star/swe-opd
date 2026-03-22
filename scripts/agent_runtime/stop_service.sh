#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../shared/common.sh"

export SWE_OPD_PROJECT_ROOT="${PROJECT_ROOT}"

PID_FILE="${SWE_OPD_PROJECT_ROOT}/outputs/rollout_service/rollout_service.pid"

if [[ ! -f "${PID_FILE}" ]]; then
    echo "No rollout service pid file found." >&2
    exit 0
fi

pid="$(cat "${PID_FILE}")"
if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}"
    echo "Stopped rollout service PID ${pid}" >&2
else
    echo "PID ${pid} is not running." >&2
fi

rm -f "${PID_FILE}"
