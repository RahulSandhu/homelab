#!/usr/bin/env bash
# Create the Overleaf VM (102) on the Proxmox host.
# Run ON the Proxmox host as root:  bash create.sh
# Mirrors VM 100 (docker-host): Debian 13 cloud image + cloud-init, virtio-scsi.
set -euo pipefail

VMID=102
NAME=overleaf
IMG=/var/lib/vz/template/iso/debian-13-genericcloud-amd64.qcow2
DISK=40G
IP=192.168.1.61/24
GW=192.168.1.1
CIUSER=rahul
SSH_PUBKEY=${SSH_PUBKEY:-/root/.ssh/authorized_keys}

if qm status "$VMID" >/dev/null 2>&1; then
    echo "VM $VMID already exists — aborting."
    exit 1
fi
[ -f "$IMG" ] || { echo "cloud image missing: $IMG"; exit 1; }
[ -f "$SSH_PUBKEY" ] || { echo "ssh pubkey file missing: $SSH_PUBKEY"; exit 1; }

qm create "$VMID" \
    --name "$NAME" \
    --ostype l26 \
    --cpu host \
    --cores 2 \
    --memory 4096 \
    --scsihw virtio-scsi-single \
    --net0 virtio,bridge=vmbr0 \
    --onboot 1 \
    --agent enabled=1 \
    --serial0 socket \
    --vga serial0 \
    --ide2 local-lvm:cloudinit \
    --ciuser "$CIUSER" \
    --sshkeys "$SSH_PUBKEY" \
    --ipconfig0 ip="$IP",gw="$GW" \
    --nameserver 192.168.1.1 \
    --ciupgrade 0

qm importdisk "$VMID" "$IMG" local-lvm
qm set "$VMID" \
    --scsi0 "local-lvm:vm-${VMID}-disk-0,discard=on,iothread=1,ssd=1" \
    --boot order=scsi0
qm resize "$VMID" scsi0 "$DISK"

echo
echo "Created VM $VMID ($NAME). Next: start it with: qm start $VMID"
