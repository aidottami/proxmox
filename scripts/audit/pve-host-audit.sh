#!/usr/bin/env bash
##############################################################################
#
# Script: pve-host-audit.sh
#
# Repository:
#   https://github.com/aidottami/proxmox
#
# Description:
#   Read-only audit of a Proxmox VE node.
#
# Usage:
#   pve-host-audit.sh
#
# Exit codes:
#   0 = success
#   1 = invalid input
#   2 = missing prerequisite
#   3 = Proxmox-related error
#   4 = runtime error
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

    for cmd in qm pveversion dpkg-query awk grep sed df hostname pvesm sort paste cut tr; do
        require_command "$cmd"
    done
}

get_installed_pve_kernels() {
    dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 2>/dev/null |
        awk '$1 == "ii" && $2 ~ /^(proxmox-kernel|pve-kernel)-[0-9].*(pve|signed)$/ {print $2}' |
        sort -V
}

get_installed_debian_kernels() {
    dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 2>/dev/null |
        awk '$1 == "ii" && $2 ~ /^linux-image-[0-9].*-amd64$/ {print $2}' |
        sort -V
}

get_rc_kernels() {
    dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 2>/dev/null |
        awk '$1 == "rc" && ($2 ~ /^(proxmox-kernel|pve-kernel|linux-image)-/) {print $2}' |
        sort -V
}

print_rows() {
    local title=$1
    shift
    local rows=("$@")
    local row vmid name detail

    ((${#rows[@]} == 0)) && return 0

    printf '\n%s:\n' "$title"
    printf '%-6s %-30s %s\n' "VMID" "NAME" "DETAIL"
    printf '%-6s %-30s %s\n' "-----" "------------------------------" "------------------------"

    for row in "${rows[@]}"; do
        IFS='|' read -r vmid name detail <<< "$row"
        printf '%-6s %-30s %s\n' "$vmid" "$name" "${detail:-}"
    done
}

audit_vms() {
    local vmid config name disk_lines disks
    local has_scsi has_virtio has_sata has_ide
    local machine bios agent models
    local -a nets

    vm_total=0
    vm_scsi=0
    vm_virtio_block=0
    vm_mixed_scsi_virtio=0
    vm_legacy_disk=0
    vm_no_disk=0
    vm_q35=0
    vm_i440fx=0
    vm_ovmf=0
    vm_seabios=0
    vm_virtio_net=0
    vm_non_virtio_net=0
    vm_agent_enabled=0
    vm_agent_disabled=0

    legacy_disk_rows=()
    virtio_block_rows=()
    mixed_disk_rows=()
    legacy_machine_rows=()
    legacy_bios_rows=()
    non_virtio_net_rows=()
    agent_disabled_rows=()

    mapfile -t vmids < <(qm list 2>/dev/null | awk 'NR > 1 {print $1}' | sort -n)

    for vmid in "${vmids[@]}"; do
        [[ -z "$vmid" ]] && continue
        ((vm_total+=1))

        config=$(qm config "$vmid" 2>/dev/null || true)
        name=$(awk -F': ' '/^name:/ {print $2; exit}' <<< "$config")
        [[ -z "$name" ]] && name="-"

        disk_lines=$(
            grep -E '^(ide|sata|scsi|virtio)[0-9]+:' <<< "$config" |
                grep -vE 'media=cdrom|cloudinit' || true
        )

        disks=$(
            cut -d: -f1 <<< "$disk_lines" |
                sed '/^$/d' |
                paste -sd ',' -
        )
        [[ -z "$disks" ]] && disks="-"

        has_scsi=0
        has_virtio=0
        has_sata=0
        has_ide=0

        grep -qE '^scsi[0-9]+:' <<< "$disk_lines" && has_scsi=1
        grep -qE '^virtio[0-9]+:' <<< "$disk_lines" && has_virtio=1
        grep -qE '^sata[0-9]+:' <<< "$disk_lines" && has_sata=1
        grep -qE '^ide[0-9]+:' <<< "$disk_lines" && has_ide=1

        if ((has_sata || has_ide)); then
            ((vm_legacy_disk+=1))
            legacy_disk_rows+=("$vmid|$name|$disks")
        elif ((has_scsi && has_virtio)); then
            ((vm_mixed_scsi_virtio+=1))
            mixed_disk_rows+=("$vmid|$name|$disks")
        elif ((has_virtio)); then
            ((vm_virtio_block+=1))
            virtio_block_rows+=("$vmid|$name|$disks")
        elif ((has_scsi)); then
            ((vm_scsi+=1))
        else
            ((vm_no_disk+=1))
        fi

        machine=$(awk -F': ' '/^machine:/ {print $2; exit}' <<< "$config")
        if grep -qi 'q35' <<< "$machine"; then
            ((vm_q35+=1))
        else
            ((vm_i440fx+=1))
            legacy_machine_rows+=("$vmid|$name|${machine:-default/i440fx}")
        fi

        bios=$(awk -F': ' '/^bios:/ {print $2; exit}' <<< "$config")
        [[ -z "$bios" ]] && bios="seabios"

        if [[ "$bios" == "ovmf" ]]; then
            ((vm_ovmf+=1))
        else
            ((vm_seabios+=1))
            legacy_bios_rows+=("$vmid|$name|$bios")
        fi

        mapfile -t nets < <(grep -E '^net[0-9]+:' <<< "$config" || true)

        if ((${#nets[@]} == 0)); then
            ((vm_non_virtio_net+=1))
            non_virtio_net_rows+=("$vmid|$name|no NIC")
        elif printf '%s\n' "${nets[@]}" | grep -qvE '^net[0-9]+: virtio='; then
            ((vm_non_virtio_net+=1))
            models=$(
                printf '%s\n' "${nets[@]}" |
                    sed -E 's/^net[0-9]+: ([^=,]+).*/\1/' |
                    paste -sd ',' -
            )
            non_virtio_net_rows+=("$vmid|$name|$models")
        else
            ((vm_virtio_net+=1))
        fi

        agent=$(awk -F': ' '/^agent:/ {print $2; exit}' <<< "$config")
        if [[ "$agent" =~ ^1([,]|$) ]]; then
            ((vm_agent_enabled+=1))
        else
            ((vm_agent_disabled+=1))
            agent_disabled_rows+=("$vmid|$name")
        fi
    done
}

audit_storage() {
    zfs_status="not detected"
    zfs_problem=0
    storage_problem=0
    storage_usage=$(pvesm status 2>/dev/null || true)

    if command -v zpool >/dev/null 2>&1 && zpool list -H >/dev/null 2>&1; then
        if zpool status -x 2>/dev/null | grep -q 'all pools are healthy'; then
            zfs_status="OK"
        else
            zfs_status="WARNING"
            zfs_problem=1
        fi
    fi

    if [[ -n "$storage_usage" ]]; then
        while read -r storage _type _status _total _used _avail pct; do
            [[ "$storage" == "Name" || -z "$storage" ]] && continue
            pct_num=${pct%\%}
            if [[ "$pct_num" =~ ^[0-9]+$ ]] && ((pct_num >= 90)); then
                storage_problem=1
            fi
        done <<< "$storage_usage"
    fi
}

calculate_score() {
    score=100

    if ((boot_usage >= 85)); then
        ((score-=20))
    elif ((boot_usage >= 70)); then
        ((score-=8))
    fi

    legacy_penalty=$((vm_legacy_disk * 3))
    ((legacy_penalty > 15)) && legacy_penalty=15
    ((score-=legacy_penalty))

    net_penalty=$((vm_non_virtio_net * 2))
    ((net_penalty > 10)) && net_penalty=10
    ((score-=net_penalty))

    agent_penalty=$vm_agent_disabled
    ((agent_penalty > 5)) && agent_penalty=5
    ((score-=agent_penalty))

    ((zfs_problem > 0)) && ((score-=25))
    ((storage_problem > 0)) && ((score-=15))
    ((score < 0)) && score=0
}

print_report() {
    local hostname_value pve_version running_kernel
    local boot_size boot_used boot_avail boot_mark score_mark

    hostname_value=$(hostname -f 2>/dev/null || hostname)
    pve_version=$(pveversion 2>/dev/null | head -n1)
    running_kernel=$(uname -r)

    boot_usage=$(df -P /boot 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}')
    boot_size=$(df -hP /boot 2>/dev/null | awk 'NR==2 {print $2}')
    boot_used=$(df -hP /boot 2>/dev/null | awk 'NR==2 {print $3}')
    boot_avail=$(df -hP /boot 2>/dev/null | awk 'NR==2 {print $4}')

    mapfile -t pve_kernels < <(get_installed_pve_kernels)
    mapfile -t debian_kernels < <(get_installed_debian_kernels)
    mapfile -t rc_kernels < <(get_rc_kernels)

    audit_vms
    audit_storage
    calculate_score

    print_title "PVE HOST AUDIT"

    print_section "HOST"
    print_value "Hostname" "$hostname_value"
    print_value "PVE version" "$pve_version"
    print_value "Running kernel" "$running_kernel"

    print_section "BOOT"
    if ((boot_usage < 70)); then
        boot_mark=$(status_ok)
    elif ((boot_usage < 85)); then
        boot_mark=$(status_warning)
    else
        boot_mark=$(status_error)
    fi

    print_value "/boot" "${boot_usage}% used (${boot_used}/${boot_size}, free ${boot_avail}) ${boot_mark}"
    print_value "Installed PVE kernels" "${#pve_kernels[@]}"
    print_value "Installed Debian kernels" "${#debian_kernels[@]}"
    print_value "Kernel packages rc" "${#rc_kernels[@]}"

    ((${#pve_kernels[@]} > 0)) && printf '  PVE: %s\n' "$(join_by ',' "${pve_kernels[@]}")"
    ((${#debian_kernels[@]} > 0)) && printf '  Debian: %s\n' "$(join_by ',' "${debian_kernels[@]}")"
    ((${#rc_kernels[@]} > 0)) && printf '  rc: %s\n' "$(join_by ',' "${rc_kernels[@]}")"

    print_section "VM"
    print_value "Total VMs" "$vm_total"
    print_value "SCSI disks" "$vm_scsi $(status_ok)"
    print_value "VirtIO Block" "$vm_virtio_block"
    print_value "SCSI + VirtIO Block" "$vm_mixed_scsi_virtio $(status_warning)"
    print_value "IDE/SATA" "$vm_legacy_disk $(status_error)"
    print_value "No disk detected" "$vm_no_disk"
    print_value "Q35" "$vm_q35"
    print_value "i440FX/default" "$vm_i440fx"
    print_value "OVMF" "$vm_ovmf"
    print_value "SeaBIOS" "$vm_seabios"
    print_value "VirtIO NIC" "$vm_virtio_net"
    print_value "Non-VirtIO NIC" "$vm_non_virtio_net"
    print_value "QEMU Agent enabled" "$vm_agent_enabled"
    print_value "QEMU Agent disabled" "$vm_agent_disabled"

    print_rows "VMs with IDE/SATA disks" "${legacy_disk_rows[@]}"
    print_rows "VMs with VirtIO Block" "${virtio_block_rows[@]}"
    print_rows "VMs with SCSI + VirtIO Block" "${mixed_disk_rows[@]}"
    print_rows "VMs using i440FX/default" "${legacy_machine_rows[@]}"
    print_rows "VMs using SeaBIOS" "${legacy_bios_rows[@]}"
    print_rows "VMs with non-VirtIO NIC" "${non_virtio_net_rows[@]}"
    print_rows "VMs without QEMU Agent" "${agent_disabled_rows[@]}"

    print_section "STORAGE"
    print_value "ZFS" "$zfs_status"
    if [[ -n "$storage_usage" ]]; then
        printf '\n%s\n' "$storage_usage"
    else
        printf 'pvesm status unavailable.\n'
    fi

    print_section "SCORE"
    printf 'Note: SeaBIOS, i440FX, VirtIO Block and rc packages are informational and do not reduce the score.\n'

    if ((score >= 90)); then
        score_mark=$(status_ok)
    elif ((score >= 75)); then
        score_mark=$(status_warning)
    else
        score_mark=$(status_error)
    fi

    print_value "Overall" "${score}/100 ${score_mark}"
    printf '\nAudit completed. No changes were made.\n'
}

main() {
    parse_args "$@"
    require_root
    require_dependencies
    print_report
}

main "$@"
