#!/usr/bin/env bash
set -u
set -o pipefail

# pve-host-audit.sh
# Read-only audit for a Proxmox VE host.
# Project: https://github.com/aidottami/proxmox
# Run as root from any directory:
#   bash pve-host-audit.sh
#
# Optional:
#   NO_COLOR=1 bash pve-host-audit.sh

if [[ "${EUID}" -ne 0 ]]; then
    echo "Errore: eseguire come root." >&2
    exit 1
fi

for cmd in qm pveversion dpkg awk grep sed df lsblk; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Errore: comando richiesto non trovato: $cmd" >&2
        exit 1
    fi
done

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RED=$'\033[31m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    BLUE=$'\033[34m'
    BOLD=$'\033[1m'
    RESET=$'\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    BOLD=""
    RESET=""
fi

ok()   { printf "%s✔%s" "$GREEN" "$RESET"; }
warn() { printf "%s⚠%s" "$YELLOW" "$RESET"; }
bad()  { printf "%s✘%s" "$RED" "$RESET"; }

section() {
    printf "\n%s%s%s\n" "$BOLD" "$1" "$RESET"
    printf '%*s\n' "${#1}" '' | tr ' ' '-'
}

value_line() {
    printf "%-24s %s\n" "$1" "$2"
}

join_csv() {
    local IFS=,
    echo "$*"
}

hostname_value=$(hostname -f 2>/dev/null || hostname)
pve_version=$(pveversion 2>/dev/null | head -n1)
running_kernel=$(uname -r)
boot_usage=$(df -P /boot 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}')
boot_size=$(df -hP /boot 2>/dev/null | awk 'NR==2 {print $2}')
boot_used=$(df -hP /boot 2>/dev/null | awk 'NR==2 {print $3}')
boot_avail=$(df -hP /boot 2>/dev/null | awk 'NR==2 {print $4}')

mapfile -t pve_kernels < <(
    dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 2>/dev/null |
    awk '$1 == "ii" && $2 ~ /^(proxmox-kernel|pve-kernel)-[0-9].*(pve|signed)$/ {print $2}' |
    sort -V
)

mapfile -t debian_kernels < <(
    dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 2>/dev/null |
    awk '$1 == "ii" && $2 ~ /^linux-image-[0-9].*-amd64$/ {print $2}' |
    sort -V
)

mapfile -t rc_kernels < <(
    dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 2>/dev/null |
    awk '$1 == "rc" && ($2 ~ /^(proxmox-kernel|pve-kernel|linux-image)-/) {print $2}' |
    sort -V
)

vm_total=0
vm_scsi=0
vm_virtio_block=0
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

    if (( has_sata || has_ide )); then
        ((vm_legacy_disk+=1))
        legacy_disk_rows+=("$vmid|$name|$disks")
    elif (( has_virtio )); then
        ((vm_virtio_block+=1))
        virtio_block_rows+=("$vmid|$name|$disks")
    elif (( has_scsi )); then
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
        non_virtio_net_rows+=("$vmid|$name|nessuna NIC")
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

zfs_status="non rilevato"
zfs_problem=0
if command -v zpool >/dev/null 2>&1; then
    if zpool list -H >/dev/null 2>&1; then
        if zpool status -x 2>/dev/null | grep -q 'all pools are healthy'; then
            zfs_status="OK"
        else
            zfs_status="ATTENZIONE"
            zfs_problem=1
        fi
    fi
fi

storage_usage=$(pvesm status 2>/dev/null || true)
storage_problem=0
if [[ -n "$storage_usage" ]]; then
    while read -r storage type status total used avail pct; do
        [[ "$storage" == "Name" || -z "$storage" ]] && continue
        pct_num=${pct%\%}
        if [[ "$pct_num" =~ ^[0-9]+$ ]] && (( pct_num >= 90 )); then
            storage_problem=1
        fi
    done <<< "$storage_usage"
fi

score=100
(( boot_usage >= 85 )) && ((score-=15))
(( boot_usage >= 70 && boot_usage < 85 )) && ((score-=5))
(( vm_legacy_disk > 0 )) && ((score-=vm_legacy_disk*3))
(( vm_i440fx > 0 )) && ((score-=vm_i440fx))
(( vm_seabios > 0 )) && ((score-=vm_seabios))
(( vm_non_virtio_net > 0 )) && ((score-=vm_non_virtio_net*2))
(( vm_agent_disabled > 0 )) && ((score-=vm_agent_disabled))
(( zfs_problem > 0 )) && ((score-=15))
(( storage_problem > 0 )) && ((score-=10))
(( score < 0 )) && score=0

printf "%s============================================================%s\n" "$BLUE" "$RESET"
printf "%s%sPVE HOST AUDIT%s\n" "$BOLD" "$BLUE" "$RESET"
printf "%s============================================================%s\n" "$BLUE" "$RESET"

section "HOST"
value_line "Hostname" "$hostname_value"
value_line "PVE version" "$pve_version"
value_line "Kernel in uso" "$running_kernel"

section "BOOT"
if (( boot_usage < 70 )); then
    boot_mark=$(ok)
elif (( boot_usage < 85 )); then
    boot_mark=$(warn)
else
    boot_mark=$(bad)
fi
value_line "/boot" "${boot_usage}% usato (${boot_used}/${boot_size}, liberi ${boot_avail}) ${boot_mark}"
value_line "Kernel PVE installati" "${#pve_kernels[@]}"
value_line "Kernel Debian installati" "${#debian_kernels[@]}"
value_line "Pacchetti kernel rc" "${#rc_kernels[@]}"

if ((${#pve_kernels[@]} > 0)); then
    printf "  PVE: %s\n" "$(join_csv "${pve_kernels[@]}")"
fi
if ((${#debian_kernels[@]} > 0)); then
    printf "  Debian: %s\n" "$(join_csv "${debian_kernels[@]}")"
fi
if ((${#rc_kernels[@]} > 0)); then
    printf "  rc: %s\n" "$(join_csv "${rc_kernels[@]}")"
fi

section "VM"
value_line "Totale VM" "$vm_total"
value_line "Dischi SCSI" "$vm_scsi $(ok)"
value_line "VirtIO Block" "$vm_virtio_block $(warn)"
value_line "IDE/SATA" "$vm_legacy_disk $(bad)"
value_line "Senza disco rilevato" "$vm_no_disk"
value_line "Q35" "$vm_q35"
value_line "i440FX/default" "$vm_i440fx"
value_line "OVMF" "$vm_ovmf"
value_line "SeaBIOS" "$vm_seabios"
value_line "VirtIO NIC" "$vm_virtio_net"
value_line "NIC non VirtIO" "$vm_non_virtio_net"
value_line "QEMU Agent abilitato" "$vm_agent_enabled"
value_line "QEMU Agent disabilitato" "$vm_agent_disabled"

print_rows() {
    local title=$1
    shift
    local rows=("$@")
    ((${#rows[@]} == 0)) && return 0
    printf "\n%s:\n" "$title"
    printf "%-6s %-30s %s\n" "VMID" "NAME" "DETTAGLIO"
    printf "%-6s %-30s %s\n" "-----" "------------------------------" "------------------------"
    local row vmid name detail
    for row in "${rows[@]}"; do
        IFS='|' read -r vmid name detail <<< "$row"
        printf "%-6s %-30s %s\n" "$vmid" "$name" "${detail:-}"
    done
}

print_rows "VM con dischi IDE/SATA" "${legacy_disk_rows[@]}"
print_rows "VM con VirtIO Block" "${virtio_block_rows[@]}"
print_rows "VM i440FX/default" "${legacy_machine_rows[@]}"
print_rows "VM SeaBIOS" "${legacy_bios_rows[@]}"
print_rows "VM con NIC non VirtIO" "${non_virtio_net_rows[@]}"
print_rows "VM senza QEMU Agent" "${agent_disabled_rows[@]}"

section "STORAGE"
value_line "ZFS" "$zfs_status"
if [[ -n "$storage_usage" ]]; then
    printf "\n%s\n" "$storage_usage"
else
    echo "pvesm status non disponibile."
fi

section "SCORE"
if (( score >= 90 )); then
    score_mark=$(ok)
elif (( score >= 75 )); then
    score_mark=$(warn)
else
    score_mark=$(bad)
fi
value_line "Overall" "${score}/100 ${score_mark}"

printf "\nAudit completato. Nessuna modifica è stata eseguita.\n"
