# Troubleshooting

- **TLS fails:** check the existing Caddy certificate storage, DNS, and Caddy
  syntax before reloading. Do not add a second proxy.
- **Anonymous access succeeds:** stop the LiveSync project and inspect CouchDB
  `require_valid_user` settings and the proxy route.
- **CouchDB unhealthy:** inspect `docker compose logs couchdb`, disk space,
  permissions, and memory. Do not delete the data directory.
- **Changes feed stalls:** verify Caddy `flush_interval -1`, unlimited upstream
  read/write timeouts, and that no buffering proxy is in front of Caddy.
- **MinIO regresses:** restore the backed-up Caddyfile, syntax-check it, reload
  Caddy gracefully, and verify both MinIO health endpoints. Never run the new
  project's `down` command against the MinIO project.
