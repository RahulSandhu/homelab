# AdGuard Home

Tailnet-only DNS ad-blocking. DNS on `100.74.164.49:53`, admin UI on `:8443`.
The home LAN and family devices are untouched.

Deploy: `docker compose up -d`. `adguard-ensure.{sh,service,timer}` re-publishes
the DNS port when the container starts before Tailscale is up (cold-boot race).
