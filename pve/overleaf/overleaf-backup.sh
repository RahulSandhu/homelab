#!/usr/bin/env bash
# Back up Overleaf: mongo dump + project data tarball, pruned to 7 days.
set -euo pipefail

TK=/opt/overleaf-toolkit
SRC=/srv/overleaf
DEST="$SRC/backups"
STAMP="$(date +%F-%H%M%S)"
RETAIN_DAYS=7

mkdir -p "$DEST"
cd "$TK"
bin/docker-compose exec -T mongo mongodump --archive --gzip --db sharelatex \
  > "$DEST/mongo-$STAMP.archive.gz"
tar -C "$SRC" -czf "$DEST/data-$STAMP.tgz" sharelatex

find "$DEST" -type f -name '*.gz'  -mtime +"$RETAIN_DAYS" -delete
find "$DEST" -type f -name '*.tgz' -mtime +"$RETAIN_DAYS" -delete
echo "Backup complete: $DEST/mongo-$STAMP.archive.gz $DEST/data-$STAMP.tgz"
