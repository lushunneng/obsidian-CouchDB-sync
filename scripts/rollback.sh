#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
load_env
compose stop || true
info "Only the obsidian-livesync project was stopped; MinIO was not touched"
