#!/usr/bin/env bash
# Create the Windows 10 VM (101) on the Proxmox host.
#
# Run ON the Proxmox host as root:
#     ISO=local:iso/Win10_22H2_EnglishInternational_x64.iso bash create.sh
#
# Prereq: the Windows ISO is in /var/lib/vz/template/iso/ (see README).
# Deliberately simple: SATA disk + e1000 NIC so Windows Setup needs NO drivers.
set -euo pipefail

VMID=101
NAME=windows
ISO="${ISO:-local:iso/Win10_22H2_EnglishInternational_x64v1.iso}"

if qm status "$VMID" >/dev/null 2>&1; then
    echo "VM $VMID already exists — aborting."
    exit 1
fi

qm create "$VMID" \
    --name "$NAME" \
    --ostype win10 \
    --machine q35 \
    --bios ovmf \
    --efidisk0 local-lvm:1,efitype=4m \
    --memory 4096 \
    --cores 2 \
    --cpu host \
    --sata0 local-lvm:40 \
    --net0 e1000,bridge=vmbr0 \
    --ide2 "${ISO},media=cdrom" \
    --boot order='ide2;sata0' \
    --vga std \
    --onboot 0 \
    --tags windows

echo
echo "Created VM $VMID ($NAME)."
echo "Next: start it and install Windows from the console — see the README."
