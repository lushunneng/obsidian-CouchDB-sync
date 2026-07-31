#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
require_cmd docker
load_env
require_env COMPOSE_PROJECT_NAME LIVESYNC_DOMAIN COUCHDB_DATABASE COUCHDB_IMAGE COUCHDB_DATA_DIR BACKUP_DIR COUCHDB_ADMIN_USER COUCHDB_ADMIN_PASSWORD COUCHDB_SECRET
"${ROOT_DIR}/scripts/preflight.sh"
mkdir -p "$COUCHDB_DATA_DIR" "$BACKUP_DIR"
chmod 700 "$COUCHDB_DATA_DIR" "$BACKUP_DIR"
docker network inspect obsidian-livesync-proxy >/dev/null 2>&1 || docker network create obsidian-livesync-proxy >/dev/null
compose config >/dev/null
compose up -d --no-build
compose ps
info "CouchDB deployed; proxy integration is a separate step"
