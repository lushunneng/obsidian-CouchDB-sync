#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf 'INFO: %s\n' "$*"; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
load_env() {
  [ -f "$ENV_FILE" ] || die "missing ${ENV_FILE}; copy .env.example to .env and fill secrets";
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
}
require_env() {
  local name
  for name in "$@"; do [ -n "${!name:-}" ] || die "required variable is empty: ${name}"; done
}
compose() { docker compose --env-file "$ENV_FILE" -f "$ROOT_DIR/compose.yaml" "$@"; }
