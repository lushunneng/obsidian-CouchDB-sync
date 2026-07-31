# Ports and domains

| Layer | Address | Service | Public | Source | Purpose |
|---|---|---|---|---|---|
| Host | TCP 22 | SSH | yes | administration | server access |
| Host | TCP 80 | existing Caddy | yes | Internet | HTTP to HTTPS redirect |
| Host | TCP 443 | existing Caddy | yes | Internet | MinIO and LiveSync HTTPS |
| Docker | TCP 5984 | CouchDB | no | Caddy private network | LiveSync backend |
| Docker | TCP 9000 | MinIO API | no | existing Caddy network | Remotely Save |
| Docker | TCP 9001 | MinIO Console | no | existing MinIO network | not published |

DNS A records:

```text
minio.superxuniziyuan.win → 116.204.132.102
sync.superxuniziyuan.win  → 116.204.132.102
```

Confirm the cloud firewall allows only the required public ports. Do not expose
`5984`, `9000`, or `9001`.
