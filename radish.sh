#!/usr/bin/env bash
#
# Radish - Autonomous coding loops with safety guardrails
# https://github.com/longarcstudios/radish
#
# Usage: ./radish.sh [OPTIONS] "task description"
#

set -euo pipefail

VERSION="0.1.1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/radish.yaml"
LOG_DIR="${SCRIPT_DIR}/logs"
SESSION_ID="session-$(date +%Y%m%d-%H%M%S)"
SESSION_LOG_DIR="${LOG_DIR}/${SESSION_ID}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
AGENT="claude"
TIMEOUT=3600
CHECKPOINT_INTERVAL=300
DRY_RUN=false
VERBOSE=false

#######################################
# Print usage information
#######################################
usage() {
    cat << EOF
Radish v${VERSION} - Autonomous coding loops with safety guardrails

Usage: $(basename "$0") [OPTIONS] "task description"

Options:
    -a, --agent AGENT       Agent to use (claude, cursor, aider) [default: claude]
    -c, --config FILE       Path to config file [default: radish.yaml]
    -t, --timeout SECONDS   Session timeout [default: 3600]
    -d, --dry-run           Show what would be done without executing
    -v, --verbose           Enable verbose output
    -h, --help              Show this help message
    --version               Show version

Examples:
    $(basename "$0") "Implement user authentication"
    $(basename "$0") --agent=aider --timeout=1800 "Add unit tests"
    $(basename "$0") --dry-run "Refactor database layer"

Configuration:
    Edit radish.yaml to set guardrails, limits, and behavior.
    See README.md for full documentation.

EOF
}

#######################################
# Log message with timestamp
#######################################
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    case "$level" in
        INFO)  echo -e "${BLUE}[${timestamp}]${NC} ${message}" ;;
        WARN)  echo -e "${YELLOW}[${timestamp}] ⚠️  ${message}${NC}" ;;
        ERROR) echo -e "${RED}[${timestamp}] ❌ ${message}${NC}" ;;
        OK)    echo -e "${GREEN}[${timestamp}] ✓ ${message}${NC}" ;;
    esac

    # Also write to log file if session started
    if [[ -d "${SESSION_LOG_DIR}" ]]; then
        echo "[${timestamp}] [${level}] ${message}" >> "${SESSION_LOG_DIR}/session.log"
    fi
}

#######################################
# Parse YAML config (basic parser)
#######################################
parse_config() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log WARN "Config file not found: ${CONFIG_FILE}, using defaults"
        return
    fi

    # Extract key values (simple parsing)
    TIMEOUT=$(grep -E "^\s*timeout:" "${CONFIG_FILE}" | head -1 | awk '{print $2}' || echo "${TIMEOUT}")
    CHECKPOINT_INTERVAL=$(grep -E "^\s*checkpoint_interval:" "${CONFIG_FILE}" | head -1 | awk '{print $2}' || echo "${CHECKPOINT_INTERVAL}")

    log INFO "Loaded config from ${CONFIG_FILE}"
}

#######################################
# Create session directory and initial checkpoint
#######################################
init_session() {
    local task="$1"

    mkdir -p "${SESSION_LOG_DIR}"

    # Copy config to session
    if [[ -f "${CONFIG_FILE}" ]]; then
        cp "${CONFIG_FILE}" "${SESSION_LOG_DIR}/config.yaml"
    fi

    # Create session metadata
    cat > "${SESSION_LOG_DIR}/metadata.json" << EOF
{
    "session_id": "${SESSION_ID}",
    "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "task": "${task}",
    "agent": "${AGENT}",
    "timeout": ${TIMEOUT},
    "checkpoint_interval": ${CHECKPOINT_INTERVAL},
    "working_directory": "$(pwd)",
    "git_branch": "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'none')",
    "git_commit": "$(git rev-parse HEAD 2>/dev/null || echo 'none')"
}
EOF

    # Initialize changes tracking
    echo "[]" > "${SESSION_LOG_DIR}/changes.json"
    touch "${SESSION_LOG_DIR}/commands.log"
    echo "[]" > "${SESSION_LOG_DIR}/violations.json"

    log OK "Session initialized: ${SESSION_ID}"
}

#######################################
# Create a checkpoint (git commit)
#######################################
create_checkpoint() {
    local message="${1:-Auto-checkpoint}"

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log WARN "Not a git repository, skipping checkpoint"
        return
    fi

    # Check if there are changes to commit
    if git diff --quiet && git diff --staged --quiet; then
        log INFO "No changes to checkpoint"
        return
    fi

    git add -A
    git commit -m "[radish] ${message} (${SESSION_ID})" --no-verify 2>/dev/null || true

    log OK "Checkpoint created: ${message}"
}

#######################################
# Check for violations
#######################################
check_violations() {
    local violations=0

    # Run violation checker
    if [[ -x "${SCRIPT_DIR}/scripts/check_violations.sh" ]]; then
        if ! "${SCRIPT_DIR}/scripts/check_violations.sh" "${SESSION_LOG_DIR}"; then
            violations=1
        fi
    fi

    return ${violations}
}

#######################################
# Record file change
#######################################
record_change() {
    local file="$1"
    local action="$2"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Append to changes log (simplified JSON append)
    local change="{\"file\": \"${file}\", \"action\": \"${action}\", \"timestamp\": \"${timestamp}\"}"

    # Read existing, append, write back
    local existing=$(cat "${SESSION_LOG_DIR}/changes.json")
    if [[ "${existing}" == "[]" ]]; then
        echo "[${change}]" > "${SESSION_LOG_DIR}/changes.json"
    else
        echo "${existing%]}, ${change}]" > "${SESSION_LOG_DIR}/changes.json"
    fi
}

#######################################
# Generate session summary
#######################################
generate_summary() {
    local end_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local status="${1:-completed}"

    cat > "${SESSION_LOG_DIR}/summary.md" << EOF
# Radish Session Summary

**Session ID:** ${SESSION_ID}
**Status:** ${status}
**Ended:** ${end_time}

## Configuration
- Agent: ${AGENT}
- Timeout: ${TIMEOUT}s
- Checkpoint Interval: ${CHECKPOINT_INTERVAL}s

## Changes
$(cat "${SESSION_LOG_DIR}/changes.json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for c in data:
    print(f\"- [{c['action']}] {c['file']} @ {c['timestamp']}\")
" 2>/dev/null || echo "See changes.json for details")

## Violations
$(cat "${SESSION_LOG_DIR}/violations.json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if not data:
    print('None detected')
else:
    for v in data:
        print(f\"- {v['type']}: {v['message']}\")
" 2>/dev/null || echo "See violations.json for details")

---
Generated by [Radish](https://github.com/longarcstudios/radish)
EOF

    log OK "Summary generated: ${SESSION_LOG_DIR}/summary.md"
}

#######################################
# Cleanup and exit
#######################################
cleanup() {
    local exit_code=$?
    local status="completed"

    if [[ ${exit_code} -ne 0 ]]; then
        status="failed"
    fi

    log INFO "Cleaning up session..."

    # Final checkpoint
    create_checkpoint "Final checkpoint"

    # Generate summary
    generate_summary "${status}"

    log INFO "Session ${SESSION_ID} ${status}"
    log INFO "Logs available at: ${SESSION_LOG_DIR}"
}

#######################################
# Run the autonomous session
#######################################
run_session() {
    local task="$1"

    log INFO "Starting autonomous session..."
    log INFO "Task: ${task}"
    log INFO "Agent: ${AGENT}"
    log INFO "Timeout: ${TIMEOUT}s"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log WARN "Dry run mode - no changes will be made"
        return 0
    fi

    # Create initial checkpoint
    create_checkpoint "Session start"

    # Set up periodic checkpoints
    (
        while true; do
            sleep "${CHECKPOINT_INTERVAL}"
            create_checkpoint "Periodic checkpoint"
            check_violations || {
                log ERROR "Violation detected! Stopping session."
                kill -TERM $$ 2>/dev/null
            }
        done
    ) &
    local checkpoint_pid=$!

    # Run the agent based on type
    case "${AGENT}" in
        claude)
            log INFO "Launching Claude Code..."
            echo "Task: ${task}" | tee -a "${SESSION_LOG_DIR}/commands.log"
            # In real usage, this would invoke claude with the task
            # For now, we just echo instructions
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  Radish guardrails active. Session: ${SESSION_ID}"
            echo "  Checkpoints every ${CHECKPOINT_INTERVAL}s | Timeout: ${TIMEOUT}s"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "Run your autonomous coding session now."
            echo "Press Ctrl+C to end the session."
            echo ""

            # Wait for user to end session or timeout
            sleep "${TIMEOUT}" || true
            ;;
        cursor)
            log INFO "Cursor integration coming soon"
            ;;
        aider)
            log INFO "Aider integration coming soon"
            ;;
        *)
            log ERROR "Unknown agent: ${AGENT}"
            exit 1
            ;;
    esac

    # Kill checkpoint process
    kill ${checkpoint_pid} 2>/dev/null || true
}

#######################################
# Main
#######################################
main() {
    # Parse arguments
    local task=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--agent)
                AGENT="$2"
                shift 2
                ;;
            --agent=*)
                AGENT="${1#*=}"
                shift
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --config=*)
                CONFIG_FILE="${1#*=}"
                shift
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --timeout=*)
                TIMEOUT="${1#*=}"
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --version)
                echo "Radish v${VERSION}"
                exit 0
                ;;
            -*)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                task="$1"
                shift
                ;;
        esac
    done

    if [[ -z "${task}" ]]; then
        echo "Error: Task description required"
        echo ""
        usage
        exit 1
    fi

    # Setup trap for cleanup
    trap cleanup EXIT

    # Parse config
    parse_config

    # Initialize session
    init_session "${task}"

    # Run session
    run_session "${task}"
}

main "$@"
