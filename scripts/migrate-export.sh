#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
load_env
require_env COMPOSE_PROJECT_NAME COUCHDB_ADMIN_USER COUCHDB_ADMIN_PASSWORD COUCHDB_DATABASE
out="${1:-${ROOT_DIR}/exports/${COUCHDB_DATABASE}-$(date -u +%Y%m%dT%H%M%SZ).json}"
mkdir -p "$(dirname "$out")"
docker exec "${COMPOSE_PROJECT_NAME}-couchdb" curl -fsS -u "${COUCHDB_ADMIN_USER}:${COUCHDB_ADMIN_PASSWORD}" "http://127.0.0.1:5984/${COUCHDB_DATABASE}/_all_docs?include_docs=true" > "$out"
chmod 600 "$out"
printf 'logical export written to %s\n' "$out"
