#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../shared/common.sh"

load_bootstrap_env remote_rollout_client

KIND="${1:-}"
if [[ -z "${KIND}" ]]; then
    echo "Usage: bash scripts/remote_client/run_rollout.sh <single|batch> [args...]" >&2
    exit 1
fi
shift

"${SCRIPT_DIR}/open_tunnel.sh" >/dev/null

SERVICE_BASE="${REMOTE_ROLLOUT_SERVICE_BASE:-http://127.0.0.1:${REMOTE_ROLLOUT_LOCAL_PORT:-18080}}"
API_TOKEN="${REMOTE_ROLLOUT_API_TOKEN:-}"
OUTPUT_ROOT="${REMOTE_ROLLOUT_OUTPUT_ROOT:-${SWE_OPD_PROJECT_ROOT}/outputs/remote_client/results}"
mkdir -p "${OUTPUT_ROOT}"

submit_cmd=("$(bootstrap_python_bin)" -m swe_opd.rollout_service submit --service-base "${SERVICE_BASE}" --kind "${KIND}")
if [[ -n "${API_TOKEN}" ]]; then
    submit_cmd+=(--api-token "${API_TOKEN}")
fi

case "${KIND}" in
    single)
        INSTANCE_ID="${1:-}"
        if [[ -z "${INSTANCE_ID}" ]]; then
            echo "Usage: ... run_rollout.sh single <instance_id> [extra submit args...]" >&2
            exit 1
        fi
        shift
        submit_cmd+=(--instance-id "${INSTANCE_ID}")
        ;;
    batch)
        ;;
    *)
        echo "Unsupported kind: ${KIND}" >&2
        exit 1
        ;;
esac

submit_cmd+=("$@")

submit_json="$("${submit_cmd[@]}")"
printf '%s\n' "${submit_json}"

job_id="$(
    printf '%s' "${submit_json}" | "$(bootstrap_python_bin)" -c 'import json,sys; print(json.load(sys.stdin)["job_id"])'
)"

wait_cmd=("$(bootstrap_python_bin)" -m swe_opd.rollout_service wait --service-base "${SERVICE_BASE}" --job-id "${job_id}" --timeout "${REMOTE_ROLLOUT_WAIT_TIMEOUT:-0}")
result_cmd=("$(bootstrap_python_bin)" -m swe_opd.rollout_service result --service-base "${SERVICE_BASE}" --job-id "${job_id}")
if [[ -n "${API_TOKEN}" ]]; then
    wait_cmd+=(--api-token "${API_TOKEN}")
    result_cmd+=(--api-token "${API_TOKEN}")
fi

"${wait_cmd[@]}" >/dev/null

result_json="$("${result_cmd[@]}")"
result_path="${OUTPUT_ROOT}/${job_id}.json"
printf '%s\n' "${result_json}" >"${result_path}"

echo "Saved result to ${result_path}" >&2
printf '%s\n' "${result_json}"
