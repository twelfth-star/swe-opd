#!/usr/bin/env bash

set -euo pipefail

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${COMMON_DIR}/../.." && pwd)"

load_bootstrap_env() {
    local role="$1"
    local env_file="${PROJECT_ROOT}/config/bootstrap/${role}.env"
    local env_local_file="${PROJECT_ROOT}/config/bootstrap/${role}.local.env"
    local selected_file

    if [[ -f "${env_local_file}" ]]; then
        selected_file="${env_local_file}"
    elif [[ -f "${env_file}" ]]; then
        selected_file="${env_file}"
    else
        echo "Missing env file for ${role}." >&2
        echo "Create one from config/bootstrap/${role}.example.env" >&2
        exit 1
    fi

    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line//[[:space:]]/}" ]] && continue

        if [[ "${line}" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)= ]]; then
            local var_name="${BASH_REMATCH[1]}"
            if [[ -n "${!var_name+x}" ]]; then
                continue
            fi
        fi

        eval "export ${line}"
    done < "${selected_file}"

    echo "Loaded env from ${selected_file}" >&2

    export SWE_OPD_PROJECT_ROOT="${PROJECT_ROOT}"
    export PYTHONPATH="${PROJECT_ROOT}/src${PYTHONPATH:+:${PYTHONPATH}}"
}

require_env() {
    local var_name="$1"
    if [[ -z "${!var_name:-}" ]]; then
        echo "Required env var ${var_name} is not set." >&2
        exit 1
    fi
}

bootstrap_python_bin() {
    if [[ -n "${BOOTSTRAP_PYTHON_BIN:-}" ]]; then
        printf '%s\n' "${BOOTSTRAP_PYTHON_BIN}"
    elif [[ -n "${MINI_PYTHON_BIN:-}" ]]; then
        printf '%s\n' "${MINI_PYTHON_BIN}"
    else
        printf '%s\n' python3
    fi
}
