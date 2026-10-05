#!/usr/bin/env bash
# refresh-cookies.sh — export your Firefox cookies and push the MEDIA-SITE subset
# to MeTube on the VM, so age-restricted / login-only downloads work.
#
# Run this on the LAPTOP (it needs Firefox and the yt-downloader project's yt-dlp):
#
#   stacks/metube/refresh-cookies.sh
#
# Why a separate export: ~/desktop/projects/yt-downloader reads the Firefox profile
# directly via yt-dlp's cookiesfrombrowser (no file). MeTube wants a Netscape
# cookies.txt in its state dir, so we export one here — filtered, because the raw
# jar also carries cookies for your router, this VM, pcloud, Gmail/Drive, etc.
#
# Env overrides: PROJECT, YTDLP, PROFILE, SERVER, DEST, SEED_URL, KEEP_DOMAINS, KEEP_EXACT
set -euo pipefail

PROJECT="${PROJECT:-$HOME/desktop/projects/yt-downloader}"
YTDLP="${YTDLP:-$PROJECT/.venv/bin/yt-dlp}"
SERVER="${SERVER:-rahul@192.168.1.60}"
DEST="${DEST:-/srv/metube/downloads/.metube/cookies.txt}"
# A throwaway public video: yt-dlp only reads it to emit the jar (nothing is downloaded).
SEED_URL="${SEED_URL:-https://www.youtube.com/watch?v=aqz-KE-bpKQ}"

# Media / login sites to keep.
KEEP_DOMAINS="${KEEP_DOMAINS:-instagram.com facebook.com fbcdn.net twitter.com x.com tiktok.com reddit.com twitch.tv vimeo.com dailymotion.com soundcloud.com bandcamp.com pinterest.com snapchat.com tumblr.com imgur.com bilibili.com rumble.com odysee.com kick.com youtube.com googlevideo.com youtube-nocookie.com}"
# Exact hosts (Google's auth cookies live here; its other subdomains are blocked below).
KEEP_EXACT="${KEEP_EXACT:-google.com www.google.com accounts.google.com youtube.com www.youtube.com m.youtube.com youtu.be}"
# Sensitive Google subdomains that must never reach the server.
DENY_PREFIX="${DENY_PREFIX:-payments passwords mail drive console cloud docs studio meet chat one ogs scholar news myaccount workspace}"

PROFILE="${PROFILE:-$(sed -n 's/^YT_DOWNLOADER_COOKIES_PROFILE=//p' "$PROJECT/.env" 2>/dev/null | sed "s|^~|$HOME|")}"
[ -n "$PROFILE" ] || { echo "ERROR: no Firefox profile (set PROFILE, or YT_DOWNLOADER_COOKIES_PROFILE in $PROJECT/.env)" >&2; exit 1; }
[ -x "$YTDLP" ]  || { echo "ERROR: yt-dlp not found at $YTDLP (set YTDLP)" >&2; exit 1; }
[ -d "$PROFILE" ] || { echo "ERROR: Firefox profile not found: $PROFILE" >&2; exit 1; }

tmpdir=$(mktemp -d /tmp/metube-cookies.XXXXXX)
raw="$tmpdir/raw.txt"
out="$tmpdir/media.txt"
trap 'rm -rf "$tmpdir"' EXIT

echo "→ exporting Firefox cookies ($PROFILE) ..."
"$YTDLP" --cookies-from-browser "firefox:$PROFILE" --cookies "$raw" \
    --simulate --skip-download --no-warnings "$SEED_URL" >/dev/null

echo "→ filtering to media sites ..."
awk -F'\t' -v sufs="$KEEP_DOMAINS" -v exs="$KEEP_EXACT" -v deny="$DENY_PREFIX" '
BEGIN{ n=split(sufs,s," "); m=split(exs,e," "); d2=split(deny,dp," ") }
/^#/ { print; next }
{
  d=$1; sub(/^\./,"",d);
  for(k=1;k<=m;k++) if(d==e[k]) { print; next }
  for(k=1;k<=n;k++) if(d==s[k] || d ~ ("\\." s[k] "$")) {
    for(j=1;j<=d2;j++) if(d ~ ("^" dp[j] "\\.")) next
    print; next
  }
}' "$raw" > "$out"

count=$(awk -F'\t' '!/^#/ && NF>6 {c++} END{print c+0}' "$out")
[ "$count" -gt 0 ] || { echo "ERROR: filtered jar is empty — check KEEP_DOMAINS" >&2; exit 1; }

echo "→ $count cookies → $SERVER:$DEST"
scp -q "$out" "$SERVER:/tmp/metube-cookies.txt"
ssh -o BatchMode=yes "$SERVER" "
  set -e
  sudo install -o 1000 -g 1000 -m 600 /tmp/metube-cookies.txt '$DEST'
  rm -f /tmp/metube-cookies.txt
  sudo docker restart metube >/dev/null
  sudo docker exec -u 1000 metube head -1 /downloads/.metube/cookies.txt >/dev/null
"
echo "→ done — MeTube restarted with the fresh jar"
