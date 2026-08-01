# Operations

Run commands from the repository directory on the server. The proxy integration
also requires the existing Caddy project to attach its container to
`obsidian-livesync-proxy` and to include the reviewed site block in
`config/proxy/caddy-livesync.Caddyfile`; that is a separate, backed-up change.

```sh
./scripts/preflight.sh
./scripts/provision.sh
docker compose --env-file .env -f compose.yaml ps
docker compose --env-file .env -f compose.yaml logs --tail=100 couchdb
./scripts/validate.sh
./scripts/backup.sh
```

Stop or restart only this project:

```sh
docker compose --env-file .env -f compose.yaml stop
docker compose --env-file .env -f compose.yaml restart couchdb
```

Never use the MinIO project directory for CouchDB data. Before an image update,
make a verified backup, inspect the release notes, pin the new image, run
`compose config`, then recreate only this project and validate it. Do not use
`latest` or automatic update agents. Caddy changes require a backup, syntax
check, and graceful reload; verify MinIO immediately afterward.
