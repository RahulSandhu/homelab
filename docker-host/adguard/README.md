# AdGuard Home

Tailnet-only DNS ad-blocking; the home LAN and family devices are untouched.

- **Served at:** DNS on `100.74.164.49:53`, admin UI on
  `https://docker-host.tail91459b.ts.net:8443` — tailnet-only.
- **Deploy:** `docker compose up -d`.

## Notes

- `adguard-ensure.{sh,service,timer}` re-publish the DNS port when the
  container starts before Tailscale is up (cold-boot race).
