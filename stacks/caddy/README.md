# Caddy — reverse proxy

The single entrypoint for `docker-host`'s web services. `tailscale serve :443`
forwards here (plain HTTP), and Caddy routes by **path**:

```
/            → homepage:3000     (catch-all — the dashboard)
/navidrome   → navidrome:4533    (path kept — Navidrome uses ND_BASEURL)
/pairdrop    → pairdrop:3000     (path stripped — PairDrop uses relative paths)
/files       → filebrowser:80    (path kept — FileBrowser Quantum baseURL)
/metube      → metube:8081       (path kept — MeTube applies URL_PREFIX)
```

`/pairdrop` (no slash) is 302-redirected to `/pairdrop/`, because PairDrop's
relative assets only resolve correctly with the trailing slash.

`auto_https off` because Tailscale already provides TLS.

Listens `:8080` in-container, published on **`127.0.0.1:8090`** (localhost only —
no LAN door). Joins the external `proxy` Docker network.

## Deploy

```sh
scp -r . rahul@docker-host:/tmp/caddy && ssh rahul@docker-host \
  'sudo mkdir -p /opt/caddy && sudo cp -r /tmp/caddy/* /opt/caddy/ && cd /opt/caddy && docker compose up -d'
```

## After editing the Caddyfile

```sh
docker compose restart caddy      # Caddy reloads on start
```
