#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
require_cmd docker
docker compose version >/dev/null
load_env
require_env COMPOSE_PROJECT_NAME LIVESYNC_DOMAIN COUCHDB_DATABASE COUCHDB_IMAGE COUCHDB_DATA_DIR BACKUP_DIR COUCHDB_ADMIN_USER COUCHDB_ADMIN_PASSWORD COUCHDB_SECRET
[ "${COUCHDB_ADMIN_PASSWORD}" != "replace-with-a-long-random-password" ] || die "replace the example CouchDB password"
[ "${COUCHDB_ADMIN_USER}" != "replace-with-a-dedicated-admin-user" ] || die "replace the example CouchDB username"
[ "${COUCHDB_SECRET}" != "replace-with-another-long-random-secret" ] || die "replace the example CouchDB secret"
[[ "$COUCHDB_DATABASE" =~ ^[a-z][a-z0-9_\$\(\)\+\-]*$ ]] || die "invalid CouchDB database name"
[[ "$LIVESYNC_DOMAIN" != *example.com ]] || die "replace the example domain"
[ "${EUID}" -eq 0 ] || die "run as root on the server"
free_kb=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
[ "${free_kb:-0}" -ge 1048576 ] || die "less than 1 GiB memory available"
df -Pk "$COUCHDB_DATA_DIR" 2>/dev/null | awk 'NR==2 {if ($4 < 5242880) exit 1}' || die "less than 5 GiB free on CouchDB filesystem"
for port in 80 443 5984 9000 9001; do
  if ss -H -ltn "sport = :${port}" | grep -q .; then info "port ${port} is occupied"; else info "port ${port} is free"; fi
done
if docker ps -a --format '{{.Names}}' | grep -qx "${COMPOSE_PROJECT_NAME}-couchdb"; then die "container name already exists: ${COMPOSE_PROJECT_NAME}-couchdb"; fi
docker network inspect obsidian-livesync-proxy >/dev/null 2>&1 || info "network obsidian-livesync-proxy will be created"
getent ahostsv4 "$LIVESYNC_DOMAIN" | awk '{print $1}' | sort -u
info "preflight passed; no deployment performed"
