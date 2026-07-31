# Cross-server migration

1. Lower DNS TTL before the maintenance window.
2. Install Docker and Compose using the distribution's verified Docker
   instructions; do not overwrite an existing production Docker setup.
3. Clone this repository and create a `0600` `.env` through a secure channel.
4. Run `preflight.sh` on the new server.
5. Restore or replicate CouchDB into an isolated target and validate it.
6. Freeze writes at the agreed maintenance point. Prefer CouchDB replication or
   a logical export/import for the final consistent transfer.
7. Configure the existing HTTPS proxy on the new host, validate TLS, anonymous
   rejection, authenticated access, and database health.
8. Switch DNS, then validate both device directions and offline catch-up.
9. Keep the old server untouched for the rollback window. Rollback means
   restoring DNS and the client endpoint; do not delete the old data first.

Transfer real credentials, TLS private keys, Setup URIs, and E2EE passphrases
out of band. MinIO migration is a separate runbook and must not reuse this
CouchDB data path.
