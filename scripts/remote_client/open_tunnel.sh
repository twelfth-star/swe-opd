#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../shared/common.sh"

load_bootstrap_env remote_rollout_client

USE_TUNNEL="${REMOTE_ROLLOUT_USE_SSH_TUNNEL:-true}"
if [[ "${USE_TUNNEL}" != "true" ]]; then
    echo "REMOTE_ROLLOUT_USE_SSH_TUNNEL=false, skipping tunnel setup." >&2
    exit 0
fi

require_env REMOTE_ROLLOUT_SSH_USER
require_env REMOTE_ROLLOUT_SSH_HOST
require_env REMOTE_ROLLOUT_SSH_KEY

LOCAL_PORT="${REMOTE_ROLLOUT_LOCAL_PORT:-18080}"
REMOTE_HOST="${REMOTE_ROLLOUT_REMOTE_HOST:-127.0.0.1}"
REMOTE_PORT="${REMOTE_ROLLOUT_REMOTE_PORT:-18080}"

LOG_DIR="${SWE_OPD_PROJECT_ROOT}/outputs/remote_client"
mkdir -p "${LOG_DIR}"
PID_FILE="${LOG_DIR}/service_tunnel_${LOCAL_PORT}.pid"
LOG_FILE="${LOG_DIR}/service_tunnel_${LOCAL_PORT}.log"

if [[ -f "${PID_FILE}" ]]; then
    pid="$(cat "${PID_FILE}")"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
        echo "Remote rollout tunnel already running with PID ${pid}" >&2
        exit 0
    fi
    rm -f "${PID_FILE}"
fi

nohup ssh -i "${REMOTE_ROLLOUT_SSH_KEY}" \
  -o StrictHostKeyChecking=accept-new \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -N \
  -L "127.0.0.1:${LOCAL_PORT}:${REMOTE_HOST}:${REMOTE_PORT}" \
  "${REMOTE_ROLLOUT_SSH_USER}@${REMOTE_ROLLOUT_SSH_HOST}" \
  >"${LOG_FILE}" 2>&1 &
pid=$!
echo "${pid}" >"${PID_FILE}"

echo "Started remote rollout tunnel" >&2
echo "PID file : ${PID_FILE}" >&2
echo "Log file : ${LOG_FILE}" >&2
echo "PID      : ${pid}" >&2
