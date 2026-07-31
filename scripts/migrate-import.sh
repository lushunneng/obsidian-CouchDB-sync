#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
load_env
require_env COUCHDB_ADMIN_USER COUCHDB_ADMIN_PASSWORD COUCHDB_DATABASE
[ "${1:-}" ] || die "usage: migrate-import.sh export.json"
die "import requires an isolated target and explicit review; use CouchDB _bulk_docs after validating the export"
