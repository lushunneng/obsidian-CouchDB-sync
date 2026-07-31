#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
require_cmd docker
load_env
require_env COMPOSE_PROJECT_NAME LIVESYNC_DOMAIN COUCHDB_DATABASE COUCHDB_IMAGE COUCHDB_DATA_DIR COUCHDB_HEALTHCHECK_FILE BACKUP_DIR COUCHDB_ADMIN_USER COUCHDB_ADMIN_PASSWORD COUCHDB_SECRET
if [ "${1:-}" = "--dry-run" ]; then "${ROOT_DIR}/scripts/preflight.sh" --dry-run; exit 0; fi
"${ROOT_DIR}/scripts/preflight.sh"
mkdir -p "$COUCHDB_DATA_DIR" "$BACKUP_DIR" "$(dirname "$COUCHDB_HEALTHCHECK_FILE")"
chmod 700 "$COUCHDB_DATA_DIR" "$BACKUP_DIR" "$(dirname "$COUCHDB_HEALTHCHECK_FILE")"
chown 5984:5984 "$COUCHDB_DATA_DIR"
umask 077
printf 'machine 127.0.0.1 login %s password %s\n' "$COUCHDB_ADMIN_USER" "$COUCHDB_ADMIN_PASSWORD" > "$COUCHDB_HEALTHCHECK_FILE"
chmod 600 "$COUCHDB_HEALTHCHECK_FILE"
docker network inspect obsidian-livesync-proxy >/dev/null 2>&1 || docker network create obsidian-livesync-proxy >/dev/null
docker pull "$COUCHDB_IMAGE" >/dev/null
compose config >/dev/null
compose up -d --no-build
for attempt in $(seq 1 30); do
  status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${COMPOSE_PROJECT_NAME}-couchdb" 2>/dev/null || true)"
  [ "$status" = healthy ] && break
  [ "$status" = unhealthy ] && { compose logs --tail=80 couchdb; die "CouchDB healthcheck failed"; }
  sleep 2
done
[ "$(docker inspect -f '{{.State.Health.Status}}' "${COMPOSE_PROJECT_NAME}-couchdb")" = healthy ] || die "CouchDB did not become healthy"
compose ps
printf 'image_id='; docker image inspect "$COUCHDB_IMAGE" -f '{{.Id}}'
printf 'image_digest='; docker image inspect "$COUCHDB_IMAGE" -f '{{index .RepoDigests 0}}' 2>/dev/null || true
info "CouchDB deployed; proxy integration is a separate step"
