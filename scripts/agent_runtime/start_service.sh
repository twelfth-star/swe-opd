#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../shared/common.sh"

load_bootstrap_env rollout_service
load_bootstrap_env agent_rollout

HOST="${ROLLOUT_SERVICE_HOST:-0.0.0.0}"
PORT="${ROLLOUT_SERVICE_PORT:-18080}"
JOB_ROOT="${ROLLOUT_SERVICE_JOB_ROOT:-${SWE_OPD_PROJECT_ROOT}/outputs/rollout_service_jobs}"
MAX_WORKERS="${ROLLOUT_SERVICE_MAX_WORKERS:-2}"

cmd=(
    "$(bootstrap_python_bin)" -m swe_opd.rollout_service serve
    --host "${HOST}"
    --port "${PORT}"
    --project-root "${SWE_OPD_PROJECT_ROOT}"
    --job-root "${JOB_ROOT}"
    --max-workers "${MAX_WORKERS}"
)

if [[ -n "${ROLLOUT_SERVICE_API_TOKEN:-}" ]]; then
    cmd+=(--api-token "${ROLLOUT_SERVICE_API_TOKEN}")
fi

printf 'Starting rollout service\n' >&2
printf 'Bind      : http://%s:%s\n' "${HOST}" "${PORT}" >&2
printf 'Project   : %s\n' "${SWE_OPD_PROJECT_ROOT}" >&2
printf 'Job root  : %s\n' "${JOB_ROOT}" >&2
printf 'Workers   : %s\n' "${MAX_WORKERS}" >&2
printf 'Command   : %s\n' "${cmd[*]}" >&2

exec "${cmd[@]}"
