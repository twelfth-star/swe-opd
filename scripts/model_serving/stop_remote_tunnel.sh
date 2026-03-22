#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../shared/common.sh"

load_bootstrap_env model_serving

REMOTE_PORT="${SGLANG_TUNNEL_REMOTE_PORT:-32000}"
LOG_DIR="${SWE_OPD_PROJECT_ROOT}/outputs/model_serving"
PID_FILE="${LOG_DIR}/model_tunnel_${REMOTE_PORT}.pid"

if [[ ! -f "${PID_FILE}" ]]; then
    echo "No model reverse tunnel pid file found." >&2
    exit 0
fi

pid="$(cat "${PID_FILE}")"
if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}"
    echo "Stopped model reverse tunnel PID ${pid}" >&2
else
    echo "PID ${pid} is not running." >&2
fi

rm -f "${PID_FILE}"
