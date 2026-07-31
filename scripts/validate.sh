#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
require_cmd docker
load_env
require_env COMPOSE_PROJECT_NAME COUCHDB_ADMIN_USER COUCHDB_ADMIN_PASSWORD COUCHDB_DATABASE LIVESYNC_DOMAIN
compose ps --status running | grep -q "${COMPOSE_PROJECT_NAME}-couchdb" || die "CouchDB container is not running"
docker exec "${COMPOSE_PROJECT_NAME}-couchdb" curl -fsS -u "${COUCHDB_ADMIN_USER}:${COUCHDB_ADMIN_PASSWORD}" http://127.0.0.1:5984/_up >/dev/null
docker exec "${COMPOSE_PROJECT_NAME}-couchdb" curl -fsS -u "${COUCHDB_ADMIN_USER}:${COUCHDB_ADMIN_PASSWORD}" "http://127.0.0.1:5984/${COUCHDB_DATABASE}" >/dev/null
if curl -fsS --max-time 15 "https://${LIVESYNC_DOMAIN}/_up" >/dev/null 2>&1; then die "anonymous HTTPS access unexpectedly succeeded"; fi
info "CouchDB local health and authenticated database access passed"
