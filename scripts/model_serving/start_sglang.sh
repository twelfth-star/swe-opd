#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../shared/common.sh"

load_bootstrap_env model_serving
require_env SGLANG_MODEL_PATH

SGLANG_PYTHON_BIN="${SGLANG_PYTHON_BIN:-python3}"
SGLANG_LAUNCH_MODE="${SGLANG_LAUNCH_MODE:-single}"
SGLANG_HOST="${SGLANG_HOST:-0.0.0.0}"
SGLANG_PORT="${SGLANG_PORT:-30000}"
SGLANG_TP="${SGLANG_TP:-1}"
SGLANG_DP_SIZE="${SGLANG_DP_SIZE:-1}"
SGLANG_MEM_FRACTION_STATIC="${SGLANG_MEM_FRACTION_STATIC:-0.80}"
LOG_DIR="${SWE_OPD_PROJECT_ROOT}/outputs/model_serving"
mkdir -p "${LOG_DIR}"

build_single_cmd() {
    local -n cmd_ref="$1"
    cmd_ref=(
        "${SGLANG_PYTHON_BIN}" -m sglang.launch_server
        --model-path "${SGLANG_MODEL_PATH}"
        --host "${SGLANG_HOST}"
        --port "${SGLANG_PORT}"
        --tp "${SGLANG_TP}"
        --mem-fraction-static "${SGLANG_MEM_FRACTION_STATIC}"
    )

    if [[ -n "${SGLANG_CONTEXT_LENGTH:-}" ]]; then
        cmd_ref+=(--context-length "${SGLANG_CONTEXT_LENGTH}")
    fi

    if [[ -n "${SGLANG_EXTRA_ARGS:-}" ]]; then
        # shellcheck disable=SC2206
        local extra_args=( ${SGLANG_EXTRA_ARGS} )
        cmd_ref+=("${extra_args[@]}")
    fi
}

build_router_cmd() {
    local -n cmd_ref="$1"
    cmd_ref=(
        "${SGLANG_PYTHON_BIN}" -m sglang_router.launch_server
        --model "${SGLANG_MODEL_PATH}"
        --host "${SGLANG_HOST}"
        --port "${SGLANG_PORT}"
        --tp-size "${SGLANG_TP}"
        --dp-size "${SGLANG_DP_SIZE}"
        --mem-fraction-static "${SGLANG_MEM_FRACTION_STATIC}"
    )

    if [[ -n "${SGLANG_CONTEXT_LENGTH:-}" ]]; then
        cmd_ref+=(--context-length "${SGLANG_CONTEXT_LENGTH}")
    fi

    if [[ -n "${SGLANG_EXTRA_ARGS:-}" ]]; then
        # shellcheck disable=SC2206
        local extra_args=( ${SGLANG_EXTRA_ARGS} )
        cmd_ref+=("${extra_args[@]}")
    fi

    if [[ -n "${SGLANG_ROUTER_EXTRA_ARGS:-}" ]]; then
        # shellcheck disable=SC2206
        local router_extra_args=( ${SGLANG_ROUTER_EXTRA_ARGS} )
        cmd_ref+=("${router_extra_args[@]}")
    fi
}

case "${SGLANG_LAUNCH_MODE}" in
    single)
        build_single_cmd cmd
        ;;
    router)
        build_router_cmd cmd
        ;;
    *)
        echo "Unsupported SGLANG_LAUNCH_MODE: ${SGLANG_LAUNCH_MODE}" >&2
        echo "Expected one of: single, router" >&2
        exit 1
        ;;
esac

echo "Starting SGLang model serving"
echo "Launch mode: ${SGLANG_LAUNCH_MODE}"
echo "Model path : ${SGLANG_MODEL_PATH}"
if [[ "${SGLANG_LAUNCH_MODE}" == "router" ]]; then
    echo "TP size    : ${SGLANG_TP}"
    echo "DP size    : ${SGLANG_DP_SIZE}"
else
    echo "TP size    : ${SGLANG_TP}"
fi
echo "HTTP base  : http://${SGLANG_HOST}:${SGLANG_PORT}"
echo "OpenAI base: http://${SGLANG_HOST}:${SGLANG_PORT}/v1"
printf 'Command    :'
printf ' %q' "${cmd[@]}"
printf '\n'

exec "${cmd[@]}"
