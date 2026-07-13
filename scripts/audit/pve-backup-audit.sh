#!/usr/bin/env bash
##############################################################################
#
# Script: pve-backup-audit.sh
#
# Repository:
#   https://github.com/aidottami/proxmox
#
# Description:
#   Read-only audit of Proxmox backup jobs and recent vzdump activity.
#
# Usage:
#   pve-backup-audit.sh
#
##############################################################################

set -Eeuo pipefail

SCRIPT_NAME=$(basename "$0")
readonly SCRIPT_NAME

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR

REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
readonly REPO_ROOT

source "$REPO_ROOT/scripts/lib/colors.sh"
source "$REPO_ROOT/scripts/lib/common.sh"
source "$REPO_ROOT/scripts/lib/logging.sh"
source "$REPO_ROOT/scripts/lib/output.sh"
source "$REPO_ROOT/scripts/lib/validation.sh"

usage() {
    cat <<USAGE
Usage:
  $SCRIPT_NAME

Environment:
  NO_COLOR=1    Disable ANSI colors
  DEBUG=1       Enable debug messages
USAGE
}

parse_args() {
    while (($# > 0)); do
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage >&2
                exit 1
                ;;
        esac
    done
}

require_dependencies() {
    local cmd
    for cmd in pvesh journalctl awk grep date; do
        require_command "$cmd"
    done
}

main() {
    local jobs recent_failures recent_successes

    parse_args "$@"
    require_root
    require_dependencies

    print_title "PVE BACKUP AUDIT"

    print_section "BACKUP JOBS"
    if jobs=$(pvesh get /cluster/backup --output-format yaml 2>/dev/null); then
        if [[ -n "$jobs" ]]; then
            printf '%s\n' "$jobs"
        else
            printf 'No scheduled backup jobs found.\n'
        fi
    else
        printf 'Unable to query scheduled backup jobs.\n'
    fi

    print_section "RECENT VZDUMP ACTIVITY"
    journalctl --since '7 days ago' --no-pager \
        -u 'vzdump*' 2>/dev/null |
        tail -n 100 || true

    recent_failures=$(
        journalctl --since '7 days ago' --no-pager 2>/dev/null |
            grep -Eic 'vzdump.*(fail|error)|backup.*(fail|error)'
    )

    recent_successes=$(
        journalctl --since '7 days ago' --no-pager 2>/dev/null |
            grep -Eic 'vzdump.*(success|finished)|backup.*(success|finished)'
    )

    print_section "SUMMARY"
    print_value "Recent success markers" "$recent_successes"
    print_value "Recent failure markers" "$recent_failures"

    printf '\nAudit completed. No changes were made.\n'
}

main "$@"
