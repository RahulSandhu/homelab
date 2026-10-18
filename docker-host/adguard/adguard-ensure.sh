#!/bin/sh
# Re-publish AdGuard DNS on the tailnet IP after boot.
# Docker can start before Tailscale; the timer retries.
set -eu

TAILNET_IP=100.74.164.49
IFACE=tailscale0
STACK_DIR=/opt/adguard
WAIT_SECONDS=120

have_ip() {
    ip -4 addr show "$IFACE" 2>/dev/null | grep -Fq "inet $TAILNET_IP/"
}

port_published() {
    ss -lun 2>/dev/null | grep -Fq "$TAILNET_IP:53" &&
        ss -ltn 2>/dev/null | grep -Fq "$TAILNET_IP:53"
}

# Wait for the tailnet IP.
i=0
while [ "$i" -lt "$WAIT_SECONDS" ] && ! have_ip; do
    i=$((i + 1))
    sleep 1
done

if ! have_ip; then
    echo "adguard-ensure: $TAILNET_IP not up; leaving it for now"
    exit 0
fi

if port_published; then
    echo "adguard-ensure: $TAILNET_IP:53 is published"
    exit 0
fi

echo "adguard-ensure: recreating adguard"
cd "$STACK_DIR"
docker compose up -d --force-recreate adguard
