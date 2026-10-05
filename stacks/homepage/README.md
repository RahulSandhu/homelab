# Homepage — dashboard

A landing page listing every service, served at the **root** of
`https://docker-host.tail91459b.ts.net/` (via Caddy, tailnet-only).

Config lives in `config/` (mounted into the container):

| File | Purpose |
| --- | --- |
| `settings.yaml` | title, theme, layout |
| `services.yaml` | the tiles (the links) |
| `widgets.yaml` | top-right widgets (resources, date) |
| `bookmarks.yaml` | bottom reference links (Tailscale admin console) |

`HOMEPAGE_ALLOWED_HOSTS` **must** include the hostname you reach it on, or
Homepage refuses the request.

## Deploy / update

```sh
scp -r . rahul@docker-host:/tmp/homepage && ssh rahul@docker-host \
  'sudo mkdir -p /opt/homepage && sudo cp -r /tmp/homepage/* /opt/homepage/ && cd /opt/homepage && docker compose up -d'
```

## Adding a tile

Append to `config/services.yaml`, then `docker compose restart homepage`.
Icons come from <https://github.com/homarr-labs/dashboard-icons>.
