#!/usr/bin/env bash
# Run inside the overleaf VM as root.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl gnupg git qemu-guest-agent
systemctl enable --now qemu-guest-agent

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

curl -fsSL https://tailscale.com/install.sh | sh
if [ -n "${TS_AUTHKEY:-}" ]; then
  tailscale up --authkey "$TS_AUTHKEY" --hostname overleaf
else
  echo "No TS_AUTHKEY set. Run: tailscale up --hostname overleaf   (then authenticate in a browser)"
fi

install -d /srv/overleaf/sharelatex /srv/overleaf/mongo /srv/overleaf/redis /srv/overleaf/backups

echo "Host prep done. docker: $(docker --version)"
