#!/usr/bin/env bash
##############################################################################
#
# Script: pve-storage-audit.sh
#
# Repository:
#   https://github.com/aidottami/proxmox
#
# Description:
#   Read-only audit of Proxmox storage, ZFS and filesystem usage.
#
# Usage:
#   pve-storage-audit.sh
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
    for cmd in pvesm df awk grep; do
        require_command "$cmd"
    done
}

main() {
    local storage_output filesystem_output
    local name status pct pct_num
    local warning_count=0 error_count=0

    parse_args "$@"
    require_root
    require_dependencies

    print_title "PVE STORAGE AUDIT"

    print_section "PROXMOX STORAGE"
    storage_output=$(pvesm status)
    printf '%s\n' "$storage_output"

    while read -r name _type status _total _used _avail pct; do
        [[ "$name" == "Name" || -z "$name" ]] && continue
        pct_num=${pct%\%}

        if [[ "$status" != "active" ]]; then
            ((error_count += 1))
        elif [[ "$pct_num" =~ ^[0-9]+$ ]] && ((pct_num >= 90)); then
            ((error_count += 1))
        elif [[ "$pct_num" =~ ^[0-9]+$ ]] && ((pct_num >= 80)); then
            ((warning_count += 1))
        fi
    done <<<"$storage_output"

    print_section "FILESYSTEMS"
    filesystem_output=$(df -hPT -x tmpfs -x devtmpfs -x efivarfs -x fuse)
    printf '%s\n' "$filesystem_output"

    print_section "ZFS"
    if command -v zpool >/dev/null 2>&1 && zpool list -H >/dev/null 2>&1; then
        zpool status -x
        if ! zpool status -x | grep -q 'all pools are healthy'; then
            ((error_count += 1))
        fi
    else
        printf 'ZFS not detected.\n'
    fi

    print_section "SUMMARY"
    print_value "Warnings" "$warning_count"
    print_value "Errors" "$error_count"

    printf '\nAudit completed. No changes were made.\n'
}

main "$@"
