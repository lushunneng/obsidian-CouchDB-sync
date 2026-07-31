#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
require_cmd tar
load_env
require_env COUCHDB_DATA_DIR BACKUP_DIR
[ -d "$COUCHDB_DATA_DIR" ] || die "CouchDB data directory does not exist"
mkdir -p "$BACKUP_DIR"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive="${BACKUP_DIR}/couchdb-${stamp}.tar.gz"
tar --exclude='*.log' -C "$COUCHDB_DATA_DIR" -czf "$archive" .
gzip -t "$archive"
sha256sum "$archive" > "${archive}.sha256"
chmod 600 "$archive" "$archive.sha256"
printf 'backup=%s size=%s\n' "$archive" "$(stat -c %s "$archive")"
