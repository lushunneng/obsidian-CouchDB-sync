# Backup and restore

`./scripts/backup.sh` creates a gzip archive and SHA-256 sidecar under
`BACKUP_DIR`. The archive is a point-in-time file backup and must only be made
while CouchDB is stopped or after a verified consistent snapshot procedure.
For active production migration, prefer CouchDB logical replication or a
consistent database export rather than copying live files.

Keep encrypted copies on a separate host with restricted access and a retention
policy. Test restoration in an isolated server and validate `_up`, admin
authentication, the database, and LiveSync database-version negotiation before
using it in production.

`restore.sh` deliberately refuses destructive extraction. A restore operator
must stop only the LiveSync project, extract to an isolated path, verify the
archive and permissions, point a temporary Compose project at it, validate, and
only then perform an explicitly approved data-path switch.

MinIO backups are separate and remain owned by the existing MinIO repository.
