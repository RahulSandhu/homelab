# Vaultwarden stack

A single-service Docker Compose stack for [Vaultwarden](https://github.com/dani-garcia/vaultwarden),
the lightweight Bitwarden-compatible server.

It is **not** internet-facing. Clients reach it only through the Tailscale
tailnet, with TLS terminated by `tailscale serve` on the Proxmox host.

## Files

| File                | Purpose                                            |
| ------------------- | -------------------------------------------------- |
| `compose.yaml`      | The service definition (image pinned to `1.37.3`). |
| `.env.example`      | Template — copy to `.env` and fill in.             |
| `data/`             | Runtime state (git-ignored, created on first run). |

## Deploy

Run these on the Debian VM `docker-host`:

```sh
sudo mkdir -p /opt/vaultwarden && sudo chown "$USER" /opt/vaultwarden
cp compose.yaml .env.example /opt/vaultwarden/
cd /opt/vaultwarden
mv .env.example .env

# Generate the admin token hash and paste it into .env as ADMIN_TOKEN.
# This needs a real terminal (`-it`); without a TTY it panics.
docker run --rm -it vaultwarden/server:1.37.3 /vaultwarden hash

${EDITOR:-vi} .env        # set DOMAIN, TZ, ADMIN_TOKEN
docker compose up -d
docker compose logs -f
```

> **Gotcha:** escape `$` as `$$` in `.env` — Compose interpolates it, so the
> token must look like `ADMIN_TOKEN=$$argon2id$$v=19$$…`, otherwise Vaultwarden
> silently uses it as a plain-text token.

Then follow `docs/setup.md` to create your account, close signups, and wire up
`tailscale serve`.

## Operate

```sh
docker compose ps                 # status
docker compose logs -f            # follow logs
docker compose pull && docker compose up -d   # update (snapshot the VM first)
```

## Back up the vault itself

The homelab itself isn't backed up — it *is* the laptop's backup destination
(`/srv/backup`). The one thing here worth protecting is Vaultwarden's data:

- Take a Proxmox snapshot before every update: `qm snapshot <vmid> pre-update`.
- Periodically export the vault from the Bitwarden client (or the `/admin`
  panel) onto your laptop, and keep that copy somewhere safe.
