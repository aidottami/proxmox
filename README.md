# Proxmox Toolbox

A curated toolbox for Proxmox VE administration, auditing, migration, storage, networking and operational standardization.

## Philosophy

**Audit first. Automation second. Standardization always.**

The repository separates read-only inspection tools from scripts that modify systems. Every operational change should be preceded by a clear inventory, a dry run where possible, and an explicit rollback path.

## Current features

- Proxmox host audit
- VM disk-bus inventory
- Kernel and `/boot` inspection
- Detection of legacy VM configurations
- Documentation for IDE/SATA to VirtIO SCSI migration
- Repository structure for future Bash, Ansible and template tooling

## Repository layout

```text
.
├── ansible/            # Inventories, playbooks and roles
├── assets/             # Diagrams, images, Draw.io sources and logos
├── docs/
│   ├── architecture/
│   ├── benchmarks/
│   ├── best-practices/
│   ├── howto/
│   ├── notes/
│   └── troubleshooting/
├── examples/
├── hooks/
├── scripts/
│   ├── audit/          # Read-only tools
│   ├── backup/
│   ├── bin/            # Repository utilities
│   ├── fail2ban/
│   ├── kernel/
│   ├── lib/            # Shared Bash libraries
│   ├── maintenance/
│   ├── migration/
│   ├── network/
│   ├── proxmox/
│   ├── ssh/
│   ├── storage/
│   ├── tests/
│   ├── vm/
│   └── wireguard/
└── templates/
    ├── cloud-init/
    ├── hooks/
    ├── snippets/
    └── vm/
```

## Quick start

Clone the repository on a Proxmox node or on an administration workstation:

```bash
git clone https://github.com/aidottami/proxmox.git
cd proxmox
```

Run the host audit directly:

```bash
sudo bash scripts/audit/pve-host-audit.sh
```

Install it globally on a Proxmox node:

```bash
sudo install -m 0755   scripts/audit/pve-host-audit.sh   /usr/local/sbin/pve-host-audit
```

Then run:

```bash
sudo pve-host-audit
```

Disable ANSI colors when redirecting output:

```bash
sudo NO_COLOR=1 pve-host-audit > host-audit.txt
```

## Safety model

Scripts under `scripts/audit/` must never modify the host or VM configuration.

Scripts that perform changes should:

- support a report or dry-run mode where practical;
- validate prerequisites;
- display the exact intended changes;
- require explicit confirmation or an `--apply` option;
- document rollback procedures.

## VM standard

The target configuration for newly created or normalized Windows VMs is:

```text
Machine:        q35
Firmware:       OVMF
Disk controller: VirtIO SCSI Single
Network:        VirtIO
Cache:          none
IO thread:      enabled
Discard:        enabled
SSD emulation:  enabled where appropriate
QEMU Agent:     enabled
```

Existing VirtIO Block VMs are considered acceptable and are not an urgent conversion target.

## Documentation

- [Convert Windows disks from IDE/SATA to VirtIO SCSI Single](docs/howto/windows-ide-sata-to-scsi.md)

## Requirements

The host audit currently expects:

- Proxmox VE
- Bash
- `qm`
- `pveversion`
- `pvesm`
- standard Debian utilities
- optional `zpool` for ZFS health checks

## Status

The project is under active development. Scripts should be reviewed and tested before use on production systems.

## Version

Current version: `0.1.0`
