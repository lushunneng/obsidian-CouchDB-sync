#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
load_env
require_env LIVESYNC_DOMAIN BACKUP_DIR COUCHDB_ADMIN_USER COUCHDB_ADMIN_PASSWORD COMPOSE_PROJECT_NAME
CADDY_IMAGE="caddy:2.11.4-alpine@sha256:5f5c8640aae01df9654968d946d8f1a56c497f1dd5c5cda4cf95ab7c14d58648"
MINIO_PROJECT_DIR="${MINIO_PROJECT_DIR:-/opt/obsidian-minio-sync}"
MINIO_COMPOSE_FILE="${MINIO_PROJECT_DIR}/docker-compose.yml"
CADDYFILE="${MINIO_PROJECT_DIR}/caddy/Caddyfile"
[ -f "$MINIO_COMPOSE_FILE" ] || die "missing existing MinIO Compose file"
[ -f "$CADDYFILE" ] || die "missing existing Caddyfile"
docker network inspect obsidian-livesync-proxy >/dev/null 2>&1 || die "missing obsidian-livesync-proxy network"
[ "$(docker inspect -f '{{.State.Health.Status}}' "${COMPOSE_PROJECT_NAME}-couchdb")" = healthy ] || die "CouchDB is not healthy"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="${BACKUP_DIR}/proxy-${stamp}"
mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
cp --preserve=mode,ownership,timestamps "$MINIO_COMPOSE_FILE" "$backup_dir/docker-compose.yml"
cp --preserve=mode,ownership,timestamps "$CADDYFILE" "$backup_dir/Caddyfile"
sha256sum "$backup_dir"/* > "$backup_dir/manifest.sha256"
compose_minio() { COMPOSE_PROJECT_NAME=obsidian-minio docker compose --env-file "${MINIO_PROJECT_DIR}/.env" -f "$MINIO_COMPOSE_FILE" "$@"; }
rollback() {
  cp --preserve=mode,ownership,timestamps "$backup_dir/docker-compose.yml" "$MINIO_COMPOSE_FILE"
  cp --preserve=mode,ownership,timestamps "$backup_dir/Caddyfile" "$CADDYFILE"
  compose_minio up -d --no-deps --no-build caddy >/dev/null 2>&1 || true
}
python3 - "$MINIO_COMPOSE_FILE" "$CADDYFILE" "$ROOT_DIR/config/proxy/caddy-livesync.Caddyfile" "$LIVESYNC_DOMAIN" "$CADDY_IMAGE" <<'PY'
from pathlib import Path
import re
import sys

compose_path = Path(sys.argv[1])
caddy_path = Path(sys.argv[2])
fragment_path = Path(sys.argv[3])
domain = sys.argv[4]
caddy_image = sys.argv[5]
compose = compose_path.read_text()
match = re.search(r"(?ms)^  caddy:\n.*?(?=^  [A-Za-z0-9_-]+:|^networks:)", compose)
if not match:
    raise SystemExit("cannot locate caddy service")
service = match.group(0)
service, image_replacements = re.subn(
    r"(?m)^    image: caddy:[^\n]+$",
    f"    image: {caddy_image}",
    service,
    count=1,
)
if image_replacements != 1:
    raise SystemExit("cannot locate Caddy image reference")
if "    init: true\n" not in service:
    service = service.replace("    restart: unless-stopped\n", "    restart: unless-stopped\n    init: true\n", 1)
if "      - livesync_proxy\n" not in service:
    service = service.replace("    networks:\n      - syncnet\n", "    networks:\n      - syncnet\n      - livesync_proxy\n", 1)
    compose = compose[:match.start()] + service + compose[match.end():]
if "  livesync_proxy:\n" not in compose:
    compose = compose.replace("\nvolumes:\n", "\n  livesync_proxy:\n    external: true\n    name: obsidian-livesync-proxy\n\nvolumes:\n", 1)
compose_path.write_text(compose)
caddy = caddy_path.read_text()
if domain not in caddy:
    fragment = fragment_path.read_text().replace("__LIVESYNC_DOMAIN__", domain).strip()
    caddy = caddy.rstrip() + "\n\n# BEGIN obsidian-livesync managed\n" + fragment + "\n# END obsidian-livesync managed\n"
    caddy_path.write_text(caddy)
PY
domain_value="$(sed -n 's/^DOMAIN=//p' "${MINIO_PROJECT_DIR}/.env" | head -1)"
[ -n "$domain_value" ] || die "missing existing MinIO DOMAIN"
docker compose -f "$MINIO_COMPOSE_FILE" --env-file "${MINIO_PROJECT_DIR}/.env" config >/dev/null
docker run --rm --network none -e "DOMAIN=${domain_value}" -v "${CADDYFILE}:/etc/caddy/Caddyfile:ro" "$CADDY_IMAGE" caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null || { rollback; die "Caddy validation failed; proxy files restored"; }
compose_minio up -d --no-deps --no-build caddy >/dev/null || { rollback; die "Caddy restart failed; proxy files restored"; }
for attempt in $(seq 1 60); do [ "$(docker inspect -f '{{.State.Health.Status}}' obsidian-minio-caddy 2>/dev/null || true)" = healthy ] && break; sleep 2; done
[ "$(docker inspect -f '{{.State.Health.Status}}' obsidian-minio-caddy)" = healthy ] || { rollback; die "Caddy did not become healthy; proxy files restored"; }
curl -kLsS --connect-timeout 8 --max-time 15 -o /dev/null -w '%{http_code}' "https://${LIVESYNC_DOMAIN}/" | grep -Eq '401|403' || { rollback; die "anonymous LiveSync request was not rejected; proxy files restored"; }
curl -kLsS --connect-timeout 8 --max-time 15 -o /dev/null -w '%{http_code}' "https://${domain_value}/minio/health/live" | grep -qx 200 || { rollback; die "MinIO regression detected; proxy files restored"; }
info "existing Caddy integrated; backup=${backup_dir}"
