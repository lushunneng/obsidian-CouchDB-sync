# Architecture

```text
Internet
  ├─ minio.superxuniziyuan.win ─┐
  └─ sync.superxuniziyuan.win ──┤ TCP 80/443
                                ▼
                       existing Caddy
                         │       │
                         │       └─ obsidian-livesync-proxy → couchdb:5984
                         └─ obsidian-minio-net → minio:9000

obsidian-livesync project
  couchdb:3.4.3 → ${COUCHDB_DATA_DIR}:/opt/couchdb/data
```

The new Compose project has an internal backend network and a dedicated proxy
network. CouchDB has no `ports` mapping, so host port `5984` remains closed.
MinIO volumes and the MinIO Compose project are never reused.
