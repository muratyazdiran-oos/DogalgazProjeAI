#!/usr/bin/env sh
set -eu
: "${DATABASE_URL:?DATABASE_URL gerekli}"
OUT="${1:-./backups}"
mkdir -p "$OUT"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
pg_dump --format=custom --no-owner --no-privileges "$DATABASE_URL" > "$OUT/dogalgaz-$STAMP.dump"
find "$OUT" -type f -name 'dogalgaz-*.dump' -mtime +14 -delete
echo "$OUT/dogalgaz-$STAMP.dump"
