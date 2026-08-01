#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
load_env
require_env COMPOSE_PROJECT_NAME COUCHDB_DATABASE COUCHDB_ADMIN_USER COUCHDB_ADMIN_PASSWORD BACKUP_DIR
DENO_IMAGE="${DENO_IMAGE:-denoland/deno:2.4.5}"
docker pull "$DENO_IMAGE" >/dev/null
umask 077
env_file="$(mktemp)"
log_file="$(mktemp)"
trap 'rm -f "$env_file" "$log_file"' EXIT
cat > "$env_file" <<EOF
hostname=http://127.0.0.1:5984
username=$COUCHDB_ADMIN_USER
password=$COUCHDB_ADMIN_PASSWORD
database=$COUCHDB_DATABASE
origins=app://obsidian.md,capacitor://localhost,http://localhost
EOF
chmod 600 "$env_file"
docker run --rm \
  --network "container:${COMPOSE_PROJECT_NAME}-couchdb" \
  --env-file "$env_file" \
  -v "${ROOT_DIR}:/workspace:ro" \
  "$DENO_IMAGE" \
  run --config=/workspace/vendor/livesync/flyio/deno.jsonc \
  --frozen --lock=/workspace/vendor/livesync/flyio/deno.lock \
  --allow-env --allow-net /workspace/vendor/livesync/couchdb/provision.ts >"$log_file" 2>&1
sed -E 's/(password|secret|authorization|token)[^[:space:]]*/\1=REDACTED/Ig' "$log_file"
info "official LiveSync CouchDB provisioning passed"
