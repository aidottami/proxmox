#!/usr/bin/env bash
##############################################################################
#
# Script: pve-network-audit.sh
#
# Repository:
#   https://github.com/aidottami/proxmox
#
# Description:
#   Read-only audit of Proxmox host and VM network configuration.
#
# Usage:
#   pve-network-audit.sh
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
    for cmd in ip qm awk grep sed sort; do
        require_command "$cmd"
    done
}

main() {
    local vmid config name model bridge firewall queues
    local vm_total=0 virtio_count=0 non_virtio_count=0 no_nic_count=0
    local -a vmids net_lines

    parse_args "$@"
    require_root
    require_dependencies

    print_title "PVE NETWORK AUDIT"

    print_section "HOST LINKS"
    ip -brief link

    print_section "HOST ADDRESSES"
    ip -brief address

    print_section "ROUTES"
    ip route

    print_section "VM NETWORK ADAPTERS"
    printf '%-6s %-28s %-12s %-18s %-10s %-8s\n' \
        "VMID" "NAME" "MODEL" "BRIDGE" "FIREWALL" "QUEUES"
    printf '%-6s %-28s %-12s %-18s %-10s %-8s\n' \
        "-----" "----------------------------" "------------" \
        "------------------" "----------" "--------"

    mapfile -t vmids < <(qm list | awk 'NR > 1 {print $1}' | sort -n)

    for vmid in "${vmids[@]}"; do
        config=$(qm config "$vmid")
        name=$(awk -F': ' '/^name:/ {print $2; exit}' <<<"$config")
        [[ -z "$name" ]] && name="-"

        mapfile -t net_lines < <(grep -E '^net[0-9]+:' <<<"$config" || true)

        if ((${#net_lines[@]} == 0)); then
            printf '%-6s %-28s %-12s %-18s %-10s %-8s\n' \
                "$vmid" "$name" "none" "-" "-" "-"
            ((no_nic_count += 1))
            ((vm_total += 1))
            continue
        fi

        for line in "${net_lines[@]}"; do
            model=$(sed -E 's/^net[0-9]+: ([^=,]+).*/\1/' <<<"$line")
            bridge=$(sed -nE 's/.*bridge=([^,]+).*/\1/p' <<<"$line")
            firewall=$(sed -nE 's/.*firewall=([^,]+).*/\1/p' <<<"$line")
            queues=$(sed -nE 's/.*queues=([^,]+).*/\1/p' <<<"$line")

            [[ -z "$bridge" ]] && bridge="-"
            [[ -z "$firewall" ]] && firewall="0"
            [[ -z "$queues" ]] && queues="1"

            if [[ "$model" == "virtio" ]]; then
                ((virtio_count += 1))
            else
                ((non_virtio_count += 1))
            fi

            printf '%-6s %-28s %-12s %-18s %-10s %-8s\n' \
                "$vmid" "$name" "$model" "$bridge" "$firewall" "$queues"
        done

        ((vm_total += 1))
    done

    print_section "SUMMARY"
    print_value "Total VMs" "$vm_total"
    print_value "VirtIO adapters" "$virtio_count"
    print_value "Non-VirtIO adapters" "$non_virtio_count"
    print_value "VMs without NIC" "$no_nic_count"

    printf '\nAudit completed. No changes were made.\n'
}

main "$@"
