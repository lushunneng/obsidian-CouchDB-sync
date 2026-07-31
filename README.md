# Obsidian Self-hosted LiveSync infrastructure

This repository manages the CouchDB side of Self-hosted LiveSync. It does not
manage the existing MinIO project or its data. The existing Caddy instance is
the only public HTTPS entry point and must be integrated separately.

## Quick start

```sh
cp .env.example .env
chmod 600 .env
# Fill .env with secrets; never commit it.
./scripts/preflight.sh
./scripts/deploy.sh
./scripts/validate.sh
```

The deployment binds no host port for CouchDB. Caddy reaches it through the
`obsidian-livesync-proxy` Docker network after the site block in
`config/proxy/caddy-livesync.Caddyfile` is installed and the existing Caddy
container is attached to that network.

Use the official LiveSync provisioning utility from a reviewed, pinned checkout
to apply CouchDB settings and negotiate the database version. Keep its admin
credentials, Vault E2EE passphrase, Setup URI, and Setup URI passphrase outside
this repository.

See `docs/operations.md`, `docs/client-setup.md`, and `docs/migration.md`.
