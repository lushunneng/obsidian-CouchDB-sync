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
compose stop couchdb
restart_needed=1
trap 'if [ "$restart_needed" -eq 1 ]; then compose start couchdb >/dev/null || true; fi' EXIT
tar --exclude='*.log' -C "$COUCHDB_DATA_DIR" -czf "$archive" .
gzip -t "$archive"
sha256sum "$archive" > "${archive}.sha256"
chmod 600 "$archive" "$archive.sha256"
compose start couchdb
for attempt in $(seq 1 30); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' "${COMPOSE_PROJECT_NAME}-couchdb" 2>/dev/null || true)" = healthy ] && break
  sleep 2
done
[ "$(docker inspect -f '{{.State.Health.Status}}' "${COMPOSE_PROJECT_NAME}-couchdb")" = healthy ] || die "CouchDB failed to recover after backup"
restart_needed=0
printf 'backup=%s size=%s\n' "$archive" "$(stat -c %s "$archive")"
