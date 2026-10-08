#!/usr/bin/env bash
# Runs INSIDE the overleaf VM, as root. Installs the toolkit, builds the
# full-TeX-Live image, and starts the stack.
# Usage: sudo bash bootstrap.sh
set -euo pipefail

TK=/opt/overleaf-toolkit
SHARE=/srv/overleaf
OVERLEAF_VERSION=6.3.0
IMAGE=overleaf-texlive
SRC="$(cd "$(dirname "$0")" && pwd)"

install -d "$SHARE/sharelatex" "$SHARE/mongo" "$SHARE/redis" "$SHARE/backups"

if [ ! -d "$TK/.git" ]; then
  git clone https://github.com/overleaf/toolkit.git "$TK"
fi
git -C "$TK" rev-parse HEAD   # record this in README for reproducibility

install -d "$TK/config"
cp "$SRC/config/overleaf.rc" "$TK/config/overleaf.rc"
cp "$SRC/config/variables.env.example" "$TK/config/variables.env"
echo "$OVERLEAF_VERSION" > "$TK/config/version"

# bin/init normally generates this; we configure by hand, so create it if absent.
if ! grep -qE '^OVERLEAF_INVITE_TOKEN_SECRET=.+' "$TK/config/variables.env"; then
  echo "OVERLEAF_INVITE_TOKEN_SECRET=$(openssl rand -hex 32)" >> "$TK/config/variables.env"
fi

cp "$SRC/Dockerfile.texlive" "$TK/Dockerfile.texlive"
docker build -t "${IMAGE}:${OVERLEAF_VERSION}" -f "$TK/Dockerfile.texlive" "$TK"

cd "$TK"
bin/up -d

# --- backup timer ---
install -m 0755 "$SRC/overleaf-backup.sh" /usr/local/sbin/overleaf-backup.sh
cp "$SRC/overleaf-backup.service" "$SRC/overleaf-backup.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now overleaf-backup.timer

echo "Overleaf starting. HTTP check:  curl -sI http://127.0.0.1:80"
