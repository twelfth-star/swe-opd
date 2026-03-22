#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../shared/common.sh"

load_bootstrap_env model_serving

require_env SGLANG_TUNNEL_SSH_USER
require_env SGLANG_TUNNEL_SSH_HOST
require_env SGLANG_TUNNEL_SSH_KEY

LOCAL_HOST="${SGLANG_HOST:-127.0.0.1}"
LOCAL_PORT="${SGLANG_PORT:-30000}"
REMOTE_HOST="${SGLANG_TUNNEL_REMOTE_HOST:-127.0.0.1}"
REMOTE_PORT="${SGLANG_TUNNEL_REMOTE_PORT:-32000}"

LOG_DIR="${SWE_OPD_PROJECT_ROOT}/outputs/model_serving"
mkdir -p "${LOG_DIR}"
PID_FILE="${LOG_DIR}/model_tunnel_${REMOTE_PORT}.pid"
LOG_FILE="${LOG_DIR}/model_tunnel_${REMOTE_PORT}.log"

if [[ -f "${PID_FILE}" ]]; then
    existing_pid="$(cat "${PID_FILE}")"
    if [[ -n "${existing_pid}" ]] && kill -0 "${existing_pid}" 2>/dev/null; then
        echo "Model reverse tunnel already running with PID ${existing_pid}" >&2
        exit 0
    fi
    rm -f "${PID_FILE}"
fi

nohup ssh -i "${SGLANG_TUNNEL_SSH_KEY}" \
  -o StrictHostKeyChecking=accept-new \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -N \
  -R "${REMOTE_HOST}:${REMOTE_PORT}:${LOCAL_HOST}:${LOCAL_PORT}" \
  "${SGLANG_TUNNEL_SSH_USER}@${SGLANG_TUNNEL_SSH_HOST}" \
  >"${LOG_FILE}" 2>&1 &
pid=$!
echo "${pid}" >"${PID_FILE}"

echo "Started model reverse tunnel" >&2
echo "PID file : ${PID_FILE}" >&2
echo "Log file : ${LOG_FILE}" >&2
echo "PID      : ${pid}" >&2

# To verify the tunnel is working, you can run the following command on server B:
# curl -s http://127.0.0.1:32000/v1/models