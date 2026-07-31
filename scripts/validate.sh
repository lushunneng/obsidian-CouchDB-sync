#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
require_cmd docker
load_env
require_env COMPOSE_PROJECT_NAME COUCHDB_ADMIN_USER COUCHDB_ADMIN_PASSWORD COUCHDB_DATABASE LIVESYNC_DOMAIN
compose ps --status running | grep -q "${COMPOSE_PROJECT_NAME}-couchdb" || die "CouchDB container is not running"
docker exec "${COMPOSE_PROJECT_NAME}-couchdb" curl -fsS -u "${COUCHDB_ADMIN_USER}:${COUCHDB_ADMIN_PASSWORD}" http://127.0.0.1:5984/_up >/dev/null
docker exec "${COMPOSE_PROJECT_NAME}-couchdb" curl -fsS -u "${COUCHDB_ADMIN_USER}:${COUCHDB_ADMIN_PASSWORD}" "http://127.0.0.1:5984/${COUCHDB_DATABASE}" >/dev/null
anonymous_code="$(curl -kLsS --max-time 15 -o /dev/null -w '%{http_code}' "https://${LIVESYNC_DOMAIN}/")"
case "$anonymous_code" in 401|403) ;; *) die "unexpected anonymous HTTPS status: $anonymous_code" ;; esac
netrc_file="$(mktemp)"
trap 'rm -f "$netrc_file"' EXIT
chmod 600 "$netrc_file"
printf 'machine %s login %s password %s\n' "$LIVESYNC_DOMAIN" "$COUCHDB_ADMIN_USER" "$COUCHDB_ADMIN_PASSWORD" > "$netrc_file"
curl --fail --silent --show-error --netrc-file "$netrc_file" "https://${LIVESYNC_DOMAIN}/_up" >/dev/null
if ss -H -ltn 'sport = :5984' | grep -q .; then die 'CouchDB is bound to a host port'; fi
info "CouchDB local health, HTTPS authentication, database access, and private port passed"
