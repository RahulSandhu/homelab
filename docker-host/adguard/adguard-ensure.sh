#!/bin/sh
# adguard-ensure — re-publish AdGuard's DNS port on the tailnet IP after boot.
#
# Why this exists:
#   AdGuard's DNS is published on the VM's *tailnet* IP (100.74.164.49:53) so it
#   has NO LAN door. On a cold boot, Docker (restart: unless-stopped) can start
#   the container BEFORE Tailscale has assigned that IP. Docker then cannot
#   program the published port: 100.74.164.49:53 ends up with no listener, and
#   every tailnet device loses DNS — `tailscale status` reports
#   "Tailscale can't reach the configured DNS servers".
#
#   This script waits for the tailnet IP, then recreates the container ONLY if
#   the DNS port is not already published. It is idempotent: when the race did
#   not happen it does nothing. Driven by adguard-ensure.timer.
set -eu

TAILNET_IP=100.74.164.49
IFACE=tailscale0
STACK_DIR=/opt/adguard
WAIT_SECONDS=120

have_ip() {
    ip -4 addr show "$IFACE" 2>/dev/null | grep -Fq "inet $TAILNET_IP/"
}

port_published() {
    # docker-proxy listens on the IP for both protocols; require both.
    ss -lun 2>/dev/null | grep -Fq "$TAILNET_IP:53" &&
        ss -ltn 2>/dev/null | grep -Fq "$TAILNET_IP:53"
}

# 1. Tailscale can lag Docker by ~90 s on a cold boot — wait for the IP.
i=0
while [ "$i" -lt "$WAIT_SECONDS" ] && ! have_ip; do
    i=$((i + 1))
    sleep 1
done

if ! have_ip; then
    # No tailnet IP yet (e.g. no internet). Nothing to fix; the timer retries.
    echo "adguard-ensure: $TAILNET_IP not up on $IFACE yet; leaving it for now"
    exit 0
fi

# 2. Already published? Nothing to do.
if port_published; then
    echo "adguard-ensure: $TAILNET_IP:53 is published; nothing to do"
    exit 0
fi

# 3. Missing -> recreate the container now that the IP exists.
echo "adguard-ensure: $TAILNET_IP:53 is NOT published; recreating adguard"
cd "$STACK_DIR"
docker compose up -d --force-recreate adguard
