# Convert a Windows VM from IDE or SATA to VirtIO SCSI Single

This procedure converts an existing Windows VM disk from IDE or SATA to VirtIO SCSI Single without copying or reformatting the virtual disk.

The storage volume remains the same. Only the virtual controller and disk attachment are changed.

## Scope

Use this procedure for Windows VMs imported from Hyper-V, VMware, older Proxmox installations or physical-to-virtual migrations.

Do not use the commands blindly. Always inspect the actual VM configuration first.

## 1. Record the current configuration

Run on the Proxmox node:

```bash
qm config VMID
```

Save a copy:

```bash
qm config VMID > /root/qm-VMID-before-scsi.txt
```

Identify:

- the boot disk;
- its current bus, such as `ide1` or `sata0`;
- the storage volume reference;
- the current boot order;
- whether other disks or CD-ROM devices are present.

Example:

```text
boot: order=ide1
ide0: local-zfs:vm-307-disk-0,size=32G
ide1: STORAGE:vm-307-disk-0,cache=none,size=156252M
ide2: STORAGE:vm-307-disk-1,cache=none,size=150G
```

In this example, the boot disk is `ide1`, not `ide0`.

## 2. Verify or install VirtIO drivers in Windows

Attach the current VirtIO driver ISO if necessary.

Inside Windows, open an elevated Command Prompt and verify the SCSI driver:

```cmd
sc qc vioscsi
```

Enable it for boot:

```cmd
sc config vioscsi start= boot
```

For VirtIO SCSI and VirtIO SCSI Single, the required driver is:

```text
vioscsi
```

`viostor` is used by VirtIO Block and is not required for VirtIO SCSI.

Shut Windows down cleanly after enabling the driver.

## 3. Create a backup or snapshot

For production workloads, create a verified backup before changing the disk bus.

A snapshot is useful for quick rollback, but it is not a substitute for a backup when the underlying storage or VM configuration is at risk.

## 4. Change the controller

Set VirtIO SCSI Single:

```bash
qm set VMID --scsihw virtio-scsi-single
```

## 5. Reattach the existing disk as SCSI

Preserve the exact storage volume reference from `qm config`.

Example source:

```text
ide1: STORAGE:vm-307-disk-0,cache=none,size=156252M
```

Attach it as:

```bash
qm set VMID   --scsi0 STORAGE:vm-307-disk-0,cache=none,discard=on,iothread=1,ssd=1
```

Do not guess the storage name or volume identifier.

## 6. Update the boot order

```bash
qm set VMID --boot order=scsi0
```

## 7. Remove the old attachment

Only after the same volume is correctly attached as `scsi0`:

```bash
qm set VMID --delete ide1
```

For SATA:

```bash
qm set VMID --delete sata0
```

This removes the VM configuration entry. It must not delete the underlying volume when the same volume is already attached elsewhere.

Verify immediately:

```bash
qm config VMID
```

## 8. Start and validate

Start the VM:

```bash
qm start VMID
```

Validate:

- Windows boots normally;
- the system disk is visible;
- Event Viewer does not show storage-driver errors;
- applications and services start;
- additional disks are present;
- backup software still recognizes the VM.

Reboot Windows once more to confirm a clean second boot.

## Multiple disks

Preserve the logical order, but make the boot disk `scsi0`.

Example:

```text
ide1 boot disk  -> scsi0
ide2 data disk  -> scsi1
ide0 extra disk -> scsi2
```

Never assume that `ide0` is the boot disk. Read the `boot:` line first.

## Conservative method

For critical VMs, add a temporary small SCSI disk first:

```bash
qm set VMID --scsihw virtio-scsi-single
qm set VMID --scsi3 STORAGE:1,discard=on,iothread=1
```

Boot Windows, confirm that the new disk/controller is detected, then shut down and convert the boot disk.

## Rollback

If Windows fails to boot:

1. stop the VM;
2. remove the new `scsiX` attachment;
3. reattach the same storage volume to its original IDE or SATA slot;
4. restore the previous boot order;
5. start the VM.

Example:

```bash
qm stop VMID
qm set VMID --delete scsi0
qm set VMID --ide1 STORAGE:vm-VMID-disk-0,cache=none
qm set VMID --boot order=ide1
qm start VMID
```

Use the exact original values saved before the migration.

## Firmware is a separate migration

Changing the disk controller is independent from changing:

- SeaBIOS to OVMF;
- MBR to GPT;
- i440FX to Q35.

Do not change all of them at once on an imported production VM.

A SeaBIOS/MBR Windows installation normally cannot boot directly with OVMF. Convert MBR to GPT first when a firmware migration is required.
