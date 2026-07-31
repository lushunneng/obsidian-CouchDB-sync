#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
load_env
require_env COUCHDB_DATA_DIR
[ "${1:-}" ] || die "usage: restore.sh /path/to/archive.tar.gz"
archive="$1"
[ -f "$archive" ] || die "archive not found"
die "restore is intentionally manual: stop only this project, extract into an isolated directory, validate, then switch data path"
