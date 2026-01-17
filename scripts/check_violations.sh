#!/usr/bin/env bash
#
# Radish Violation Checker
# Checks for guardrail violations in the current state
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/radish.yaml"
SESSION_LOG_DIR="${1:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

violations_found=0
violations_json="[]"

# Supabase telemetry config
SUPABASE_URL="https://xlxzgeohjnseqioynwsj.supabase.co/functions/v1/radish-log"
TELEMETRY_ENABLED="${RADISH_TELEMETRY:-true}"

#######################################
# Send telemetry to Supabase
#######################################
send_telemetry() {
    local event_type="$1"
    local check_results="$2"
    local violations="$3"
    
    if [[ "${TELEMETRY_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    # Get session metadata
    local task=""
    local agent=""
    local timeout=""
    
    if [[ -n "${SESSION_LOG_DIR}" && -f "${SESSION_LOG_DIR}/metadata.json" ]]; then
        task=$(python3 -c "import json; print(json.load(open('${SESSION_LOG_DIR}/metadata.json')).get('task', ''))" 2>/dev/null || echo "")
        agent=$(python3 -c "import json; print(json.load(open('${SESSION_LOG_DIR}/metadata.json')).get('agent', ''))" 2>/dev/null || echo "")
        timeout=$(python3 -c "import json; print(json.load(open('${SESSION_LOG_DIR}/metadata.json')).get('timeout', 0))" 2>/dev/null || echo "0")
    fi
    
    # Extract session ID from log dir path
    local session_id=""
    if [[ -n "${SESSION_LOG_DIR}" ]]; then
        session_id=$(basename "${SESSION_LOG_DIR}")
    fi
    
    # Send to Supabase (async, don't block)
    curl -s -X POST "${SUPABASE_URL}" \
        -H "Content-Type: application/json" \
        -d "{
            \"session_id\": \"${session_id}\",
            \"event_type\": \"${event_type}\",
            \"task\": \"${task}\",
            \"agent\": \"${agent}\",
            \"timeout_seconds\": ${timeout:-0},
            \"check_results\": ${check_results},
            \"violations\": ${violations}
        }" > /dev/null 2>&1 &
}

log_violation() {
    local type="$1"
    local message="$2"
    local file="${3:-}"

    echo -e "${RED}[VIOLATION]${NC} ${type}: ${message}"

    local violation="{\"type\": \"${type}\", \"message\": \"${message}\", \"file\": \"${file}\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"

    if [[ "${violations_json}" == "[]" ]]; then
        violations_json="[${violation}]"
    else
        violations_json="${violations_json%]}, ${violation}]"
    fi

    violations_found=1
}

check_forbidden_paths() {
    echo "Checking forbidden paths..."

    # Get list of changed files
    local changed_files=$(git diff --name-only HEAD~1 2>/dev/null || git diff --name-only)

    # Forbidden patterns (from default config)
    local forbidden_patterns=(
        ".env"
        ".env.*"
        "*.pem"
        "*.key"
        "secrets/*"
        "credentials/*"
    )

    for file in ${changed_files}; do
        for pattern in "${forbidden_patterns[@]}"; do
            if [[ "${file}" == ${pattern} ]]; then
                log_violation "FORBIDDEN_PATH" "Modified forbidden file" "${file}"
            fi
        done
    done
}

check_forbidden_commands() {
    echo "Checking for forbidden commands in history..."

    # Check bash history for dangerous commands
    local forbidden_commands=(
        "rm -rf /"
        "rm -rf ~"
        "rm -rf \*"
        "DROP DATABASE"
        "DROP TABLE"
        "TRUNCATE"
        "mkfs"
    )

    # If we have a session log, check commands
    if [[ -n "${SESSION_LOG_DIR}" && -f "${SESSION_LOG_DIR}/commands.log" ]]; then
        for cmd in "${forbidden_commands[@]}"; do
            if grep -q "${cmd}" "${SESSION_LOG_DIR}/commands.log" 2>/dev/null; then
                log_violation "FORBIDDEN_COMMAND" "Attempted forbidden command: ${cmd}"
            fi
        done
    fi
}

check_secrets_in_code() {
    echo "Checking for secrets in code..."

    # Patterns that might indicate hardcoded secrets
    local secret_patterns=(
        "password\s*=\s*['\"][^'\"]+['\"]"
        "api_key\s*=\s*['\"][^'\"]+['\"]"
        "secret\s*=\s*['\"][^'\"]+['\"]"
        "AWS_SECRET"
        "PRIVATE_KEY"
    )

    local changed_files=$(git diff --name-only HEAD~1 2>/dev/null || git diff --name-only)

    for file in ${changed_files}; do
        if [[ -f "${file}" ]]; then
            for pattern in "${secret_patterns[@]}"; do
                if grep -qE "${pattern}" "${file}" 2>/dev/null; then
                    log_violation "POTENTIAL_SECRET" "Possible secret in file" "${file}"
                fi
            done
        fi
    done
}

check_file_limits() {
    echo "Checking file change limits..."

    local max_files=50
    local max_lines=2000

    local files_changed=$(git diff --stat HEAD~1 2>/dev/null | tail -1 | grep -oE '[0-9]+' | head -1 || echo "0")
    local lines_changed=$(git diff --stat HEAD~1 2>/dev/null | tail -1 | grep -oE '[0-9]+' | tail -1 || echo "0")

    if [[ "${files_changed}" -gt "${max_files}" ]]; then
        log_violation "FILE_LIMIT" "Too many files changed: ${files_changed} (max: ${max_files})"
    fi

    if [[ "${lines_changed}" -gt "${max_lines}" ]]; then
        log_violation "LINE_LIMIT" "Too many lines changed: ${lines_changed} (max: ${max_lines})"
    fi
}

main() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Radish Violation Checker"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Run all checks
    check_forbidden_paths
    check_forbidden_commands
    check_secrets_in_code
    check_file_limits

    echo ""

    # Save violations to session log if provided
    if [[ -n "${SESSION_LOG_DIR}" && -d "${SESSION_LOG_DIR}" ]]; then
        echo "${violations_json}" > "${SESSION_LOG_DIR}/violations.json"
    fi

    # Send telemetry to Supabase
    local check_results="{\"forbidden_paths\": false, \"forbidden_commands\": false, \"secrets\": false, \"file_limits\": false}"
    if [[ ${violations_found} -eq 1 ]]; then
        # Parse which checks failed (simplified - mark all as potentially failed if any violation)
        check_results="{\"forbidden_paths\": true, \"forbidden_commands\": true, \"secrets\": true, \"file_limits\": true}"
    fi
    send_telemetry "checkpoint" "${check_results}" "${violations_json}"

    # Summary
    if [[ ${violations_found} -eq 0 ]]; then
        echo -e "${GREEN}✓ No violations detected${NC}"
        exit 0
    else
        echo -e "${RED}✗ Violations detected - review above${NC}"
        exit 1
    fi
}

main "$@"
