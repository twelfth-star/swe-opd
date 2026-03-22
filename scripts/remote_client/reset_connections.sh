#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../shared/common.sh"

load_bootstrap_env remote_rollout_client
load_bootstrap_env model_serving

SSH_USER="${REMOTE_ROLLOUT_SSH_USER:-}"
SSH_HOST="${REMOTE_ROLLOUT_SSH_HOST:-}"
SSH_KEY="${REMOTE_ROLLOUT_SSH_KEY:-}"
ROLLOUT_LOCAL_PORT="${REMOTE_ROLLOUT_LOCAL_PORT:-18080}"
ROLLOUT_REMOTE_HOST="${REMOTE_ROLLOUT_REMOTE_HOST:-127.0.0.1}"
ROLLOUT_REMOTE_PORT="${REMOTE_ROLLOUT_REMOTE_PORT:-18080}"
MODEL_REMOTE_PORT="${REMOTE_MODEL_TUNNEL_REMOTE_PORT:-}"
MODEL_LOCAL_PORT="${SGLANG_PORT:-30000}"
if [[ -z "${MODEL_REMOTE_PORT}" && -n "${SGLANG_TUNNEL_REMOTE_PORT:-}" ]]; then
    MODEL_REMOTE_PORT="${SGLANG_TUNNEL_REMOTE_PORT}"
fi

REMOTE_LOG_DIR="${SWE_OPD_PROJECT_ROOT}/outputs/remote_client"
TUNNEL_PID_FILE="${REMOTE_LOG_DIR}/service_tunnel_${ROLLOUT_LOCAL_PORT}.pid"
MODEL_TUNNEL_PID_FILE="${SWE_OPD_PROJECT_ROOT}/outputs/model_serving/model_tunnel_${MODEL_REMOTE_PORT:-32000}.pid"

kill_pid_file_if_alive() {
    local pid_file="$1"
    if [[ -f "${pid_file}" ]]; then
        local pid
        pid="$(cat "${pid_file}")"
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            kill "${pid}" 2>/dev/null || true
            echo "Killed PID ${pid} from ${pid_file}" >&2
        fi
        rm -f "${pid_file}"
    fi
}

kill_matching_ssh() {
    local match="$1"
    if [[ -z "${match}" ]]; then
        return 0
    fi
    pkill -f "${match}" 2>/dev/null || true
}

echo "Resetting A<->B connections" >&2
kill_pid_file_if_alive "${TUNNEL_PID_FILE}"
kill_pid_file_if_alive "${MODEL_TUNNEL_PID_FILE}"

if [[ -n "${SSH_USER}" && -n "${SSH_HOST}" ]]; then
    kill_matching_ssh "-L 127.0.0.1:${ROLLOUT_LOCAL_PORT}:${ROLLOUT_REMOTE_HOST}:${ROLLOUT_REMOTE_PORT} ${SSH_USER}@${SSH_HOST}"
fi

if [[ -n "${SSH_USER}" && -n "${SSH_HOST}" && -n "${MODEL_REMOTE_PORT}" ]]; then
    kill_matching_ssh "-R 127.0.0.1:${MODEL_REMOTE_PORT}:127.0.0.1:${MODEL_LOCAL_PORT} ${SSH_USER}@${SSH_HOST}"
fi

if [[ -n "${SSH_KEY}" && -n "${SSH_USER}" && -n "${SSH_HOST}" ]]; then
    kill_matching_ssh "ssh -i ${SSH_KEY} .* ${SSH_USER}@${SSH_HOST}"
fi

echo "Done." >&2
