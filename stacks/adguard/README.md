# AdGuard Home — tailnet-only DNS

Ad/tracker blocking for the **owner's tailnet devices only** (laptop + phone), at
home and anywhere.

- **DNS:** `100.74.164.49:53` (tcp + udp) — bound to the **tailnet IP only**, so
  there is **no LAN door**. Nothing on the home network can reach it.
- **Admin UI:** `https://docker-host.tail91459b.ts.net:8443` — published by
  `tailscale serve --https=8443` → `127.0.0.1:3000`. (AdGuard's UI doesn't support
  subpaths, so it gets its own port instead of a Caddy path. 443 stays Caddy's.)
- **No router changes and no DHCP changes.** The family's internet is untouched and
  keeps using the ISP's DNS.

`Tailscale serve` only allows ports 443 / 8443 / 10000 — 8443 is ours.

## Why not whole-home?

The Livebox's DNS page is operator-locked (*"no se pueden modificar en el
router"*), so LAN-wide filtering would require the homelab to take over DHCP.
That was explicitly rejected — it would put the family's internet behind this box.

## Deploy

```sh
sudo mkdir -p /opt/adguard/work /opt/adguard/conf
scp -r compose.yaml rahul@docker-host:/tmp/
ssh rahul@docker-host 'sudo cp /tmp/compose.yaml /opt/adguard/ && cd /opt/adguard && sudo docker compose up -d'
```

First run serves the **install wizard** on `:3000` → reach it at
`https://docker-host.tail91459b.ts.net:8443`. **Keep the web interface on port
3000** (the port mapping depends on it), and set your admin user/password.

## Tailnet wiring

In the Tailscale admin console → **DNS** → *Nameservers*:

- add **Global nameserver** `100.74.164.49`
- enable **Override local DNS**

MagicDNS then keeps resolving `*.ts.net`, while everything else is resolved (and
filtered) by AdGuard. Traffic remains WireGuard-encrypted; only AdGuard's
**upstream** leaves as DoH/DoT, which is set in the UI (e.g. Quad9/Cloudflare).

## Operate

```sh
docker compose ps
docker compose logs -f
docker compose restart
```

## Cold-boot race — automatic recovery

**Symptom:** after a power cut / cold boot, `tailscale status` everywhere reports
*"Tailscale can't reach the configured DNS servers"* and nothing resolves. A
manual `host example.com 100.74.164.49` fails with **connection refused**.

**Cause:** DNS is published on the VM's *tailnet* IP (`100.74.164.49:53`), but on
a cold boot Docker (`restart: unless-stopped`) can start the container **before**
Tailscale has assigned that IP (we measured Tailscale taking ~95 s). Docker then
cannot program the port, so `100.74.164.49:53` has no listener. The container
looks fine (`Up`), which makes it confusing.

**Manual fix** (once the tailnet IP is up):

```sh
cd /opt/adguard && sudo docker compose up -d --force-recreate adguard
docker port adguard            # expect 53/tcp + 53/udp -> 100.74.164.49:53
host example.com 100.74.164.49 # expect an address
```

**Automatic fix** — `adguard-ensure.timer` waits for the tailnet IP and, only if
the DNS port is not published, recreates the container. It no-ops when the race
didn't happen.

```sh
sudo install -m 755 adguard-ensure.sh /usr/local/bin/adguard-ensure
sudo install -m 644 adguard-ensure.service adguard-ensure.timer /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now adguard-ensure.timer
```

**Verify:** `systemctl list-timers adguard-ensure.timer`, or run it by hand
(`sudo systemctl start adguard-ensure` then `journalctl -u adguard-ensure`).

## Notes

- **Renaming the admin user** (there's no UI for it): edit `conf/AdGuardHome.yaml`,
  change the name under `users:`, and restart — the password hash is untouched, so
  the password stays the same:
  ```sh
  sudo sed -i -E 's/^([[:space:]]*-[[:space:]]*name:[[:space:]]*)root([[:space:]]*)$/\1admin\2/' \
    /opt/adguard/conf/AdGuardHome.yaml
  cd /opt/adguard && sudo docker compose restart
  ```
- If the homelab is down, **your** devices lose DNS until it's back (the family's
  are unaffected).
- Android's **Private DNS** or a browser's forced DoH will bypass AdGuard — turn
  those off on your devices for full coverage.
- The published address hardcodes the VM's tailnet IP (`100.74.164.49`); if the
  tailnet ever re-addresses it, update `compose.yaml`.
