# Music share (Samba)

Exports `/srv/music` on the `docker-host` VM over SMB, so the laptop can mount it
at `~/music` **on demand** — a manual mount, there is no automount.

Kept in the repo so the share can be rebuilt; deployed to `/etc/samba/smb.conf`.

## Access

- **Path on the server:** `/srv/music` (a dedicated 50 GB ext4 virtual disk)
- **Share name:** `music` → `//docker-host/music`
- **User:** `rahul` (SMB password, created with `smbpasswd -a rahul` — separate
  from the Linux password)
- **Allowed from:** `192.168.1.0/24` (LAN) and `100.64.0.0/10` (tailnet) only

## Deploy

```sh
sudo apt-get install -y samba
sudo cp smb.conf /etc/samba/smb.conf
sudo testparm -s
printf '%s\n%s\n' "$SMB_PASSWORD" "$SMB_PASSWORD" | sudo smbpasswd -s -a rahul
sudo systemctl restart smbd && sudo systemctl enable smbd
```

## Mount on the laptop (manual)

`~/.smbcredentials` (chmod 600) holds the SMB password.

```sh
# MOUNT  (over the tailnet; use 192.168.1.60 for the LAN)
sudo mount -t cifs //docker-host/music /home/rahul/music \
  -o credentials=/home/rahul/.smbcredentials,uid=1000,gid=1000,file_mode=0644,dir_mode=0755,soft,echo_interval=5

# UNMOUNT
sudo umount /home/rahul/music
```

> **Why not automount?** systemd's mount start-limit trips after repeated failures
> while offline and leaves `~/music` empty until a manual reset. Manual mounting
> has no such state.

## Notes

- `force user = rahul` keeps every file owned by `rahul`, so Navidrome (which
  runs in a container reading `/srv/music`) can read them.
- Off-LAN traffic is encrypted by WireGuard; the share never touches the public
  internet.
