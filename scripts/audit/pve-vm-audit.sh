#!/usr/bin/env bash
##############################################################################
#
# Script: pve-vm-audit.sh
#
# Repository:
#   https://github.com/aidottami/proxmox
#
# Description:
#   Read-only audit of Proxmox VE virtual machine configuration.
#
# Usage:
#   pve-vm-audit.sh
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
            -h|--help)
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
    for cmd in qm awk grep sed sort paste cut; do
        require_command "$cmd"
    done
}

print_table_header() {
    printf '%-6s %-28s %-18s %-10s %-10s %-12s %-10s\n' \
        "VMID" "NAME" "DISKS" "MACHINE" "BIOS" "NET" "AGENT"
    printf '%-6s %-28s %-18s %-10s %-10s %-12s %-10s\n' \
        "-----" "----------------------------" "------------------" \
        "----------" "----------" "------------" "----------"
}

main() {
    local vmid config name disks machine bios net agent
    local total=0 legacy=0 virtio_block=0 mixed=0 scsi=0 no_disk=0
    local q35=0 i440fx=0 ovmf=0 seabios=0 virtio_net=0 non_virtio_net=0
    local agent_on=0 agent_off=0
    local -a vmids disk_lines nets

    parse_args "$@"
    require_root
    require_dependencies

    print_title "PVE VM AUDIT"
    print_table_header

    mapfile -t vmids < <(qm list | awk 'NR > 1 {print $1}' | sort -n)

    for vmid in "${vmids[@]}"; do
        config=$(qm config "$vmid")
        name=$(awk -F': ' '/^name:/ {print $2; exit}' <<< "$config")
        [[ -z "$name" ]] && name="-"

        mapfile -t disk_lines < <(
            grep -E '^(ide|sata|scsi|virtio)[0-9]+:' <<< "$config" |
                grep -vE 'media=cdrom|cloudinit' || true
        )

        disks=$(
            printf '%s\n' "${disk_lines[@]}" |
                cut -d: -f1 |
                sed '/^$/d' |
                paste -sd ',' -
        )
        [[ -z "$disks" ]] && disks="-"

        has_ide=0
        has_sata=0
        has_scsi=0
        has_virtio=0

        printf '%s\n' "${disk_lines[@]}" | grep -qE '^ide[0-9]+:' && has_ide=1 || true
        printf '%s\n' "${disk_lines[@]}" | grep -qE '^sata[0-9]+:' && has_sata=1 || true
        printf '%s\n' "${disk_lines[@]}" | grep -qE '^scsi[0-9]+:' && has_scsi=1 || true
        printf '%s\n' "${disk_lines[@]}" | grep -qE '^virtio[0-9]+:' && has_virtio=1 || true

        if ((has_ide || has_sata)); then
            ((legacy+=1))
        elif ((has_scsi && has_virtio)); then
            ((mixed+=1))
        elif ((has_virtio)); then
            ((virtio_block+=1))
        elif ((has_scsi)); then
            ((scsi+=1))
        else
            ((no_disk+=1))
        fi

        machine=$(awk -F': ' '/^machine:/ {print $2; exit}' <<< "$config")
        if grep -qi q35 <<< "$machine"; then
            ((q35+=1))
            machine="q35"
        else
            ((i440fx+=1))
            machine="i440fx"
        fi

        bios=$(awk -F': ' '/^bios:/ {print $2; exit}' <<< "$config")
        [[ -z "$bios" ]] && bios="seabios"
        if [[ "$bios" == "ovmf" ]]; then
            ((ovmf+=1))
        else
            ((seabios+=1))
        fi

        mapfile -t nets < <(grep -E '^net[0-9]+:' <<< "$config" || true)
        if ((${#nets[@]} == 0)); then
            net="none"
            ((non_virtio_net+=1))
        elif printf '%s\n' "${nets[@]}" | grep -qvE '^net[0-9]+: virtio='; then
            net="non-virtio"
            ((non_virtio_net+=1))
        else
            net="virtio"
            ((virtio_net+=1))
        fi

        agent=$(awk -F': ' '/^agent:/ {print $2; exit}' <<< "$config")
        if [[ "$agent" =~ ^1([,]|$) ]]; then
            agent="enabled"
            ((agent_on+=1))
        else
            agent="disabled"
            ((agent_off+=1))
        fi

        printf '%-6s %-28s %-18s %-10s %-10s %-12s %-10s\n' \
            "$vmid" "$name" "$disks" "$machine" "$bios" "$net" "$agent"

        ((total+=1))
    done

    print_section "SUMMARY"
    print_value "Total VMs" "$total"
    print_value "SCSI only" "$scsi"
    print_value "VirtIO Block only" "$virtio_block"
    print_value "SCSI + VirtIO Block" "$mixed"
    print_value "IDE/SATA present" "$legacy"
    print_value "No disk detected" "$no_disk"
    print_value "Q35" "$q35"
    print_value "i440FX/default" "$i440fx"
    print_value "OVMF" "$ovmf"
    print_value "SeaBIOS" "$seabios"
    print_value "VirtIO NIC" "$virtio_net"
    print_value "Non-VirtIO NIC" "$non_virtio_net"
    print_value "QEMU Agent enabled" "$agent_on"
    print_value "QEMU Agent disabled" "$agent_off"

    printf '\nAudit completed. No changes were made.\n'
}

main "$@"
