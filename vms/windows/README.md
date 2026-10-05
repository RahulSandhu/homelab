# Windows 10 VM

An on-demand Windows 10 VM on Proxmox. **Off by default** — start it when you
need it, shut it down when you're done. Zero RAM while stopped.

Kept in the repo so it can be rebuilt; created by `create.sh` (which runs `qm`).

## Why SATA + e1000

Windows Setup sees the disk and network with **no driver loading** — the simplest
path that just works. (virtio is faster but needs the `virtio-win` ISO and a
mid-install "Load driver" step; not worth the friction for occasional use.)

## Prereqs

The Windows ISO on the Proxmox host:

```sh
scp ~/downloads/Win10_22H2_EnglishInternational_x64v1.iso \
    root@192.168.1.50:/var/lib/vz/template/iso/
```

## Create the VM

```sh
ssh root@192.168.1.50 \
  'ISO=local:iso/Win10_22H2_EnglishInternational_x64v1.iso bash -s' < create.sh
```

Then **start it** and open the console:

```sh
ssh root@192.168.1.50 'qm start 101'
```

Proxmox UI → `windows` → **Console** (works from anywhere via
`https://pve.tail91459b.ts.net:8006`).

## Install Windows (in the console)

1. Boot from the CD. Choose **Windows 10 Pro** (Home has **no RDP server**).
2. "I don't have a product key" → install (unactivated is fine).
3. The 40 GB disk appears immediately (SATA) — no drivers needed.
4. After Windows boots, **set the boot order to the disk** so it stops booting the CD:
   ```sh
   ssh root@192.168.1.50 'qm set 101 --boot order=sata0'
   ```

## Access

**Default — the Proxmox Console (no setup inside Windows).** Proxmox UI →
`windows` → **Console**. It's served by `pve`, so it works from anywhere over the
tailnet. A bit laggy; no clipboard/audio.

**Optional — RDP (smoother session).** Requires Windows **10 Pro** + Tailscale
installed inside Windows.

1. Settings → System → **Remote Desktop → On**.
2. Install **Tailscale** in Windows, sign in → the VM joins the tailnet as
   **`windows`**.
3. From the laptop: **Remmina → `windows`** (anywhere), or the VM's LAN IP at home.

## Run it on demand

```sh
ssh root@pve 'qm start 101'       # turn on   (then RDP)
ssh root@pve 'qm shutdown 101'    # turn off  (releases RAM)
```
