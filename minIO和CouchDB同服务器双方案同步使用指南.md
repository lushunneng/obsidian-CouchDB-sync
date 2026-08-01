# MinIO 和 CouchDB 同服务器双方案同步使用指南

本文说明如何在同一台 VPS 上长期运行两套彼此隔离的 Obsidian 同步方案：

1. **MinIO + Remotely Save**：使用 S3 协议同步 Obsidian Vault。
2. **CouchDB + Self-hosted LiveSync**：使用 CouchDB 作为 LiveSync 后端，通过现有 Caddy 提供 HTTPS 入口。

本文面向已经有生产服务的服务器，重点是安全、可回滚、可备份、可迁移和可重复部署。文中的生产路径和域名以当前部署为例；迁移到其他服务器时，应根据新服务器实际路径、域名和资源情况调整 `.env`，不要直接复制生产秘密。

---

## 1. 重要结论和边界

### 1.1 两套方案可以并存，但一个 Vault 不能同时同步

两套服务在服务器端可以同时运行：

```text
Vault A ── Remotely Save ──> MinIO
Vault B ── Self-hosted LiveSync ──> CouchDB
```

但是，同一个 Vault 不能同时启用 Remotely Save 和 Self-hosted LiveSync。两个插件都可能修改、删除、重命名同一批文件，最终会产生文件冲突、删除覆盖、附件状态不一致和离线追赶异常。

正确做法是：

- 用独立测试 Vault 分别验证两套方案；
- 正式迁移时选择一种方案作为该 Vault 的唯一同步来源；
- 原方案的数据保留为回退和历史备份，但不再让两个插件同时写入同一个 Vault。

### 1.2 服务端并存不等于数据自动互通

MinIO 中的对象不会自动转换为 CouchDB 文档，CouchDB 中的 LiveSync 数据也不会自动写回 MinIO。两套方案是两个独立的同步后端：

- MinIO 的数据由 MinIO 数据卷、S3 逻辑对象和 Remotely Save 配置管理；
- CouchDB 的数据由 CouchDB 数据目录、认证、LiveSync 数据库和客户端 E2EE 设置管理。

不要把 MinIO 数据目录用作 CouchDB 数据目录，也不要把 CouchDB 数据目录挂载到 MinIO 容器。

### 1.3 生产变更原则

对已有 MinIO 生产服务执行变更时：

- 不执行整个 MinIO Compose 项目的 `down`；
- 不执行 `docker system prune`、`docker volume prune`；
- 不修改 MinIO Access Key、Secret Key、Bucket、数据目录或 Remotely Save 配置；
- 只在备份、语法检查和回滚准备完成后，重建需要变更的单个服务；
- 修改共享 Caddy 时，先备份 Compose 和 `Caddyfile`，然后语法检查，再只重建 Caddy；
- 任何不可逆操作都需要单独确认。

---

## 2. 实际总体架构

### 2.1 ASCII 架构图

```text
                                 Internet
                    ┌──────────────┴──────────────┐
                    │                             │
      Obsidian Desktop/Mobile              Obsidian Desktop/Mobile
      Remotely Save 插件                    Self-hosted LiveSync 插件
                    │                             │
                    │ HTTPS + S3 签名             │ HTTPS + CouchDB 认证
                    │                             │ + LiveSync E2EE
                    ▼                             ▼
       minio.superxuniziyuan.win       sync.superxuniziyuan.win
                    │                             │
                    └──────────────┬──────────────┘
                                   │ TCP 80 / TCP 443
                                   ▼
                    现有唯一公网反向代理：Caddy
                    容器：obsidian-minio-caddy
                                   │
              ┌────────────────────┴────────────────────┐
              │                                         │
              │ Docker 网络 obsidian-minio-net           │ Docker 网络
              │                                         │ obsidian-livesync-proxy
              ▼                                         ▼
      MinIO API :9000                         CouchDB :5984
      容器：obsidian-minio-minio               容器：obsidian-livesync-couchdb
              │                                         │
              ▼                                         ▼
      obsidian-minio-minio-data                /opt/obsidian-livesync/data/couchdb
      Docker Volume                            CouchDB 数据目录

      MinIO Console :9001                      CouchDB 5984
      仅容器网络访问                            仅 Docker 私有网络访问
      不直接暴露公网                            不绑定宿主机端口
```

### 2.2 Mermaid 架构图

```mermaid
flowchart LR
    R[Obsidian + Remotely Save] -->|HTTPS / S3| MDomain[minio.superxuniziyuan.win]
    L[Obsidian + Self-hosted LiveSync] -->|HTTPS / CouchDB + E2EE| CDomain[sync.superxuniziyuan.win]
    MDomain --> Caddy[唯一公网入口 Caddy\nTCP 80/443]
    CDomain --> Caddy
    Caddy -->|MinIO 网络| MinIO[MinIO API\nobsidian-minio-minio:9000]
    Caddy -->|LiveSync 私有网络| CouchDB[CouchDB\nobsidian-livesync-couchdb:5984]
    MinIO --> MData[MinIO 数据 Volume]
    CouchDB --> CData[/opt/obsidian-livesync/data/couchdb]
```

---

## 3. 两套方案的服务对应表

### 3.1 MinIO + Remotely Save

| 项目 | 当前配置 |
|---|---|
| 项目目录 | `/opt/obsidian-minio-sync` |
| Compose 文件 | `/opt/obsidian-minio-sync/docker-compose.yml` |
| 主入口 | `/opt/obsidian-minio-sync/install.sh` |
| Caddy 容器 | `obsidian-minio-caddy` |
| MinIO 容器 | `obsidian-minio-minio` |
| 备份容器 | `obsidian-minio-backups` |
| MinIO API | 容器内部 `minio:9000` |
| MinIO Console | 容器内部 `minio:9001` |
| 公网 API 域名 | `https://minio.superxuniziyuan.win` |
| MinIO 数据 | Docker Volume `obsidian-minio-minio-data` |
| Docker 网络 | `obsidian-minio-net` |
| Caddy 镜像 | `caddy:2.11.4-alpine@sha256:5f5c8640aae01df9654968d946d8f1a56c497f1dd5c5cda4cf95ab7c14d58648` |
| MinIO 镜像 | 由 `.env` 中 `MINIO_IMAGE` 固定 |

Remotely Save 使用 S3 API 访问 MinIO。MinIO 的 Access Key、Secret Key、Bucket 名称和 Endpoint 属于生产配置，不能提交到 Git 或写入公开文档。

### 3.2 CouchDB + Self-hosted LiveSync

| 项目 | 当前配置 |
|---|---|
| 项目目录 | `/opt/obsidian-livesync` |
| Compose 文件 | `/opt/obsidian-livesync/compose.yaml` |
| 环境文件 | `/opt/obsidian-livesync/.env` |
| CouchDB 容器 | `obsidian-livesync-couchdb` |
| CouchDB 端口 | `5984`，仅 Docker 网络，不绑定宿主机 |
| 公网域名 | `https://sync.superxuniziyuan.win` |
| 反向代理 | 现有 `obsidian-minio-caddy` |
| 代理网络 | 外部网络 `obsidian-livesync-proxy` |
| CouchDB 数据 | `/opt/obsidian-livesync/data/couchdb` |
| LiveSync 数据库 | `.env` 中 `COUCHDB_DATABASE`，当前为 `obsidiannotes` |
| CouchDB 镜像 | `couchdb:3.5.2.1`，固定版本并记录 digest |
| CouchDB 日志 | Docker `json-file`，最大 `50m`，保留 3 个文件 |

CouchDB 不直接暴露公网。客户端只能通过 Caddy 的 HTTPS 路由访问，Caddy 再通过 `obsidian-livesync-proxy` 访问 CouchDB。

---

## 4. 端口、域名和网络关系

| 层级 | 地址/端口 | 服务 | 是否公网开放 | 访问来源 | 用途 |
|---|---|---|---|---|---|
| 宿主机 | TCP `22` | SSH | 是，建议限制来源 IP | 管理员 | 服务器维护 |
| 宿主机 | TCP `80` | Caddy | 是 | Internet | HTTP 到 HTTPS、ACME |
| 宿主机 | TCP `443` | Caddy | 是 | Internet | MinIO 和 LiveSync HTTPS |
| 宿主机 | TCP `5984` | CouchDB | 否 | 无 | 不应有监听 |
| 宿主机 | TCP `9000` | MinIO API | 否 | 无 | 仅容器网络 |
| 宿主机 | TCP `9001` | MinIO Console | 否 | 无 | 仅容器网络 |
| Docker | `obsidian-minio-net` | MinIO 网络 | 否 | Caddy、MinIO | MinIO 内部通信 |
| Docker | `obsidian-livesync-proxy` | 共享代理网络 | 否 | Caddy、CouchDB | Caddy 到 CouchDB |
| Docker | `obsidian-livesync-backend` | CouchDB 后端网络 | 否 | CouchDB | 后端隔离 |

DNS 记录：

```text
minio.superxuniziyuan.win  A  116.204.132.102
sync.superxuniziyuan.win   A  116.204.132.102
```

当前不使用 Cloudflare CDN、Proxy 或 Tunnel。若以后启用，应重新验证 CouchDB `_changes` 持续流、缓存和超时行为。

检查端口：

```bash
sudo ss -lntup
sudo ss -lntH | grep -E ':(22|80|443|5984|9000|9001)\\b' || true
docker ps --format 'table {{.Names}}\\t{{.Image}}\\t{{.Ports}}\\t{{.Status}}'
```

正确状态是 80/443 由唯一 Caddy 占用，5984/9000/9001 没有宿主机公网监听。

---

## 5. 新服务器使用 Docker 部署

以下流程适合没有现有生产服务的新服务器。若新服务器已有 80/443、Docker Compose 或反向代理，必须先审计，不要直接执行 `up`。

### 5.1 准备系统和 DNS

建议：Ubuntu 22.04/24.04 或 Debian 12，至少 2 vCPU、2 GiB RAM，并为 CouchDB 预留独立数据盘。先检查：

```bash
uname -a
cat /etc/os-release
free -h
df -h
df -ih
docker version
docker compose version
```

DNS 先创建：

```text
minio.<你的域名>  A  新服务器 IPv4
sync.<你的域名>   A  新服务器 IPv4
```

确认解析后再申请证书。云防火墙只开放 SSH、80、443；5984、9000、9001 不开放。

### 5.2 克隆两个项目

```bash
sudo mkdir -p /opt/src
cd /opt/src
git clone git@github.com:lushunneng/obsidian-minio-sync.git /opt/src/obsidian-minio-sync
sudo git clone --branch audit-and-deploy \
  git@github.com:lushunneng/obsidian-CouchDB-sync.git \
  /opt/obsidian-livesync
```

真实 `.env`、备份、TLS 私钥、Setup URI 和 E2EE 密码必须通过带外安全方式传输，不能从 Git 获取。

### 5.3 部署 MinIO

```bash
cd /opt/src/obsidian-minio-sync
sudo ./install.sh install --local --domain minio.example.com
```

生产环境建议先审阅脚本再执行，不要盲目使用 `curl | bash`。完成后检查：

```bash
cd /opt/obsidian-minio-sync
sudo ./install.sh status
docker compose ps
curl -fsS -o /dev/null -w '%{http_code}\\n' https://minio.example.com/minio/health/live
curl -fsS -o /dev/null -w '%{http_code}\\n' https://minio.example.com/minio/health/ready
```

Remotely Save 配置为 HTTPS Endpoint、Bucket、Access Key、Secret Key、`us-east-1`，并开启 Path Style。

### 5.4 部署 CouchDB

```bash
cd /opt/obsidian-livesync
cp .env.example .env
chmod 600 .env
```

填写 `.env`：

```dotenv
COMPOSE_PROJECT_NAME=obsidian-livesync
LIVESYNC_DOMAIN=sync.example.com
COUCHDB_DATABASE=obsidiannotes
COUCHDB_IMAGE=couchdb:3.5.2.1
COUCHDB_DATA_DIR=/opt/obsidian-livesync/data/couchdb
COUCHDB_HEALTHCHECK_FILE=/opt/obsidian-livesync/secrets/couchdb-healthcheck.netrc
BACKUP_DIR=/opt/backup/obsidian-livesync
COUCHDB_ADMIN_USER=专用管理员用户名
COUCHDB_ADMIN_PASSWORD=至少32字符随机密码
COUCHDB_SECRET=至少32字符另一组随机密钥
MINIO_PROJECT_DIR=/opt/obsidian-minio-sync
```

生成随机值时不要把秘密放进命令行参数：

```bash
openssl rand -base64 36
openssl rand -base64 48
```

预检查和部署：

```bash
sudo ./scripts/preflight.sh --dry-run
sudo ./scripts/deploy.sh
sudo ./scripts/validate.sh
```

部署脚本会创建独立数据目录、创建 `obsidian-livesync-proxy` 网络、拉取固定 CouchDB 镜像、启动 CouchDB、等待健康检查并执行数据库初始化。

### 5.5 接入现有 Caddy

如果新服务器已经有 Caddy，不能再启动第二个占用 80/443 的代理。使用 LiveSync 项目的集成脚本：

```bash
cd /opt/obsidian-livesync
sudo ./scripts/integrate-proxy.sh
```

它应先备份现有 Compose 和 `Caddyfile`，再添加私有网络和 LiveSync 路由，最后只执行：

```bash
docker compose up -d --no-deps --no-build caddy
```

验证：

```bash
curl -I https://sync.example.com/
curl -I https://minio.example.com/minio/health/live
```

LiveSync 匿名请求返回 `401` 或 `403` 是预期行为。

---

## 6. Obsidian 客户端使用方法

### 6.1 Remotely Save + MinIO

在 Obsidian 中安装并启用 Remotely Save，选择 Amazon S3 或 S3 Compatible，填写：

```text
Endpoint:   https://minio.example.com
Bucket:     vault
Region:     us-east-1
Path Style: 开启
Access Key: MinIO .env 中的用户名
Secret Key: MinIO .env 中的密码
```

配置后执行 Check Connection，再用独立测试 Vault 验证新建、编辑、重命名、删除、图片、PDF 和小附件。

注意：

- Endpoint 必须使用 HTTPS；
- 不要在客户端 Endpoint 中填写 `9000`；
- 不要把 MinIO Console 的 `9001` 当作 S3 API；
- 不要把 Access Key 或 Secret Key 提交到 Git；
- 轮换 Secret Key 前必须安排所有客户端重新配置；
- 同一个 Vault 不要同时启用 LiveSync。

### 6.2 Self-hosted LiveSync + CouchDB

第一台设备建议使用桌面端，并先创建独立测试 Vault：

1. 完整备份测试 Vault；
2. 安装并启用 Self-hosted LiveSync；
3. 选择 Self-hosted CouchDB；
4. 填写 CouchDB HTTPS 地址、数据库、用户名和密码；
5. 设置独立的 Vault E2EE 密码；
6. 由第一台设备初始化并完成首次上传；
7. 创建测试笔记，验证服务器和第二台设备；
8. 从已成功工作的第一台设备为每台新增设备生成新的 Setup URI；
9. Setup URI 与对应口令分开保存。

示例：

```text
Remote URL: https://sync.example.com
Database:   obsidiannotes
Username:   .env 中的 CouchDB 用户
Password:   .env 中的 CouchDB 密码
```

### 6.3 E2EE、Setup URI 和凭据管理

以下内容必须分别保管：

- CouchDB 管理员用户名和密码；
- `COUCHDB_SECRET`；
- LiveSync Vault E2EE 密码；
- 每台设备的 Setup URI；
- Setup URI 对应口令；
- MinIO Access Key 和 Secret Key；
- SSH 私钥和 Git 推送凭据。

不要把这些内容放入 Git、README、聊天记录、Shell 历史、截图、公开工单或未加密备份。Setup URI 不是普通 URL，应按密码级别保护。

### 6.4 手机后台限制

手机系统可能在锁屏、电池优化、网络切换或后台进程回收时暂停 Obsidian。服务端不能保证手机锁屏后持续实时同步。验收时应测试：

- 手机前台打开 Obsidian 时接收变更；
- 手机离线编辑后恢复联网时追赶同步；
- 重新打开 Obsidian 后能完成同步；
- 桌面到手机、手机到桌面双向同步；
- 新建、修改、重命名、删除和小附件。

---

## 7. 常用 Docker 和服务命令

### 7.1 MinIO 项目

```bash
cd /opt/obsidian-minio-sync

# 状态和日志
sudo ./install.sh status
sudo ./install.sh logs
sudo ./install.sh logs -f

# 启动、停止、重启
sudo ./install.sh start
sudo ./install.sh stop
sudo ./install.sh restart

# Compose 状态
sudo docker compose ps

# 只重建 Caddy，不重启 MinIO
sudo docker compose up -d --no-deps --no-build caddy

# 查看指定容器
sudo docker ps --filter name=obsidian-minio
sudo docker logs --tail=100 obsidian-minio-minio
sudo docker logs --tail=100 obsidian-minio-caddy
```

生产环境修改 Caddy 后优先使用单服务命令，不要使用 `docker compose down`。

### 7.2 CouchDB 项目

```bash
cd /opt/obsidian-livesync

# 配置和状态
sudo docker compose --env-file .env -f compose.yaml config
sudo docker compose --env-file .env -f compose.yaml ps

# 日志
sudo docker compose --env-file .env -f compose.yaml logs --tail=100 couchdb
sudo docker compose --env-file .env -f compose.yaml logs -f couchdb

# 只重启 CouchDB
sudo docker compose --env-file .env -f compose.yaml restart couchdb

# 停止或启动 LiveSync 项目，不影响 MinIO
sudo docker compose --env-file .env -f compose.yaml stop
sudo docker compose --env-file .env -f compose.yaml up -d

# 项目脚本
sudo ./scripts/preflight.sh --dry-run
sudo ./scripts/validate.sh
sudo ./scripts/backup.sh
```

### 7.3 通用检查

```bash
sudo docker ps --format 'table {{.Names}}\\t{{.Image}}\\t{{.Status}}'
sudo docker inspect obsidian-minio-caddy
sudo docker inspect obsidian-minio-minio
sudo docker inspect obsidian-livesync-couchdb
sudo docker network ls
sudo docker network inspect obsidian-livesync-proxy
sudo docker volume ls
sudo docker stats --no-stream
sudo docker system df
```

不要在生产服务器使用：

```bash
docker system prune
docker system prune -a
docker volume prune
docker compose down -v
```

这些命令可能删除仍需使用的镜像、Volume 或生产数据。

---

## 8. 备份策略和备份格式

### 8.1 基本原则

备份建议满足 3-2-1 原则：至少 3 份副本、2 种介质、1 份异机或异地。推荐同时保留：

- 服务器本地快速恢复副本；
- 另一台服务器或对象存储中的加密副本；
- 管理员本地离线副本；
- 一个经过实际恢复验证的历史版本。

备份不是只看文件存在。每次备份至少检查：

```bash
ls -lh /opt/backup
find /opt/backup -type f -printf '%TY-%Tm-%Td %TH:%TM %s %p\n' | sort
gzip -t 文件名.tar.gz
sha256sum 文件名.tar.gz
tar -tzf 文件名.tar.gz | head
```

### 8.2 MinIO 自动备份

MinIO 备份容器根据 `BACKUP_KEEP_DAYS` 保留备份，通常生成：

```text
minio-YYYYMMDD-HHMMSS.tar.gz
snapshot-YYYYMMDD-HHMMSS.txt
changes.log
```

查看备份容器：

```bash
sudo docker logs --tail=100 obsidian-minio-backups
sudo docker volume inspect obsidian-minio-minio-backup
```

手动执行一次备份：

```bash
sudo docker exec obsidian-minio-backups /entrypoint.sh backup
```

`snapshot-*.txt` 是普通文本对象清单，通常包含对象相对路径、大小和修改时间，可以本地直接阅读；`changes.log` 也是文本文件。

当前自动备份是对 MinIO 数据目录的打包，并明确排除了 `.minio.sys`。它适合作为对象数据的附加保护和变化检查，但不能单独视为完整的 MinIO 灾难恢复包。对完整恢复或高一致性迁移，应使用项目导出、S3 逻辑复制或经过验证的一致性备份方案，并安排写入冻结。

### 8.3 MinIO 完整导出

MinIO 的 `install.sh export` 会打包：

- `.env`；
- `minio_data` 数据卷；
- `backup_data` 备份卷。

执行：

```bash
cd /opt/obsidian-minio-sync
sudo ./install.sh export minio-full-$(date +%Y%m%d-%H%M%S).tar.gz
sudo mv minio-full-*.tar.gz /opt/backup/
```

验证和查看：

```bash
gzip -t /opt/backup/minio-full-YYYYMMDD-HHMMSS.tar.gz
sha256sum /opt/backup/minio-full-YYYYMMDD-HHMMSS.tar.gz
tar -tzf /opt/backup/minio-full-YYYYMMDD-HHMMSS.tar.gz | less
```

`.tar.gz` 可以在 macOS、Linux 和 Windows 上用 7-Zip、Keka、归档管理器或命令行打开。但解包后主要是 MinIO 内部对象存储布局，不是可直接阅读的标准 Obsidian Vault。需要阅读笔记时，优先通过运行中的 MinIO、S3 客户端或 Remotely Save 下载对象，不要直接修改 MinIO 内部数据目录。

### 8.4 CouchDB 文件级备份

执行：

```bash
cd /opt/obsidian-livesync
sudo ./scripts/backup.sh
```

脚本会：

1. 停止 CouchDB 容器；
2. 打包 `/opt/obsidian-livesync/data/couchdb`；
3. 排除日志；
4. 执行 `gzip -t`；
5. 生成 `.sha256`；
6. 重新启动 CouchDB；
7. 等待健康检查恢复。

备份格式：

```text
couchdb-YYYYMMDDTHHMMSSZ.tar.gz
couchdb-YYYYMMDDTHHMMSSZ.tar.gz.sha256
```

验证：

```bash
gzip -t /opt/backup/obsidian-livesync/couchdb-YYYYMMDDTHHMMSSZ.tar.gz
sha256sum -c /opt/backup/obsidian-livesync/couchdb-YYYYMMDDTHHMMSSZ.tar.gz.sha256
tar -tzf /opt/backup/obsidian-livesync/couchdb-YYYYMMDDTHHMMSSZ.tar.gz | less
```

该压缩包能在本地打开查看目录，但 CouchDB 的 `.couch` 数据文件不是普通文本，不能直接作为 Markdown 阅读，也不能用编辑器安全修改。应通过 CouchDB API、Fauxton 或逻辑导出查看文档。

### 8.5 CouchDB 逻辑导出

```bash
cd /opt/obsidian-livesync
sudo ./scripts/migrate-export.sh ./exports/obsidiannotes-$(date -u +%Y%m%dT%H%M%SZ).json
```

JSON 可以本地阅读：

```bash
less ./exports/obsidiannotes-*.json
jq '.total_rows' ./exports/obsidiannotes-*.json
jq '.rows[0].doc | keys' ./exports/obsidiannotes-*.json
```

当前逻辑导出基于 `_all_docs?include_docs=true`，适合检查文档和迁移前审阅，但不能未经验证就假设它完整包含附件二进制、全部修订历史、冲突元数据和 security 记录。正式迁移优先使用 CouchDB 原生复制，或在隔离环境验证完整导入流程。

当前 `migrate-import.sh` 会主动拒绝直接导入，防止未经审阅覆盖生产数据。

### 8.6 哪些备份能直接阅读

| 备份类型 | 格式 | 能否本地打开 | 能否直接阅读笔记 |
|---|---|---|---|
| MinIO 自动备份 | `tar.gz` | 能查看和解包 | 通常不能直接作为 Vault 阅读 |
| MinIO 快照清单 | `txt` | 能 | 只能看对象路径、大小、时间 |
| MinIO 变更日志 | `log` | 能 | 只能看对象增删记录 |
| MinIO 完整导出 | `tar.gz` | 能查看和解包 | 数据为 MinIO 内部布局，建议经 S3 导出 |
| CouchDB 文件备份 | `tar.gz` + `.couch` | 能查看和解包 | 不能直接作为 Markdown 阅读 |
| CouchDB 逻辑导出 | `json` | 能 | 能审阅文档结构，但可能仍是 LiveSync 编码数据 |
| Obsidian Vault 本地备份 | 普通目录/zip | 能 | 能，最适合直接阅读 |

如果目标是“备份后能在电脑上立即打开 Markdown 阅读”，必须额外保留客户端 Vault 的普通文件备份。服务器底层数据库备份主要用于灾难恢复，不等同于可直接浏览的笔记归档。

---

## 9. 恢复方法

### 9.1 MinIO 恢复

恢复前必须确认备份来自正确环境，并且已经验证：

```bash
gzip -t /path/to/minio-full-YYYYMMDD-HHMMSS.tar.gz
tar -tzf /path/to/minio-full-YYYYMMDD-HHMMSS.tar.gz | head
```

恢复命令：

```bash
cd /opt/obsidian-minio-sync
sudo ./install.sh import /path/to/minio-full-YYYYMMDD-HHMMSS.tar.gz
```

恢复前要保存当前 `.env` 和当前数据快照，确认维护窗口，并通知所有 Remotely Save 客户端暂停同步。恢复后检查：

```bash
sudo ./install.sh status
curl -fsS -o /dev/null -w '%{http_code}\n' https://minio.example.com/minio/health/live
curl -fsS -o /dev/null -w '%{http_code}\n' https://minio.example.com/minio/health/ready
```

不要把一个环境的 `.env` 自动覆盖到另一个环境，除非明确确认域名、Access Key、Secret Key、Bucket、Compose 项目名和数据都属于同一套服务。

### 9.2 CouchDB 恢复

`restore.sh` 默认不会执行破坏性恢复，这是安全设计。推荐流程：

1. 复制备份到隔离目录；
2. 验证压缩包和 SHA-256；
3. 解包到临时目录，不覆盖生产目录；
4. 使用不同 Compose project 启动临时 CouchDB；
5. 验证 `_up`、数据库、认证和文档数量；
6. 使用测试 Vault 验证 LiveSync；
7. 确认恢复窗口后，只停止 LiveSync 项目；
8. 切换 `COUCHDB_DATA_DIR` 或恢复数据目录；
9. 启动并运行 `validate.sh`；
10. 确认 MinIO 没有被停止或修改。

不要在 CouchDB 正在写入时直接复制底层数据目录并声称一致。文件级恢复依赖“备份时 CouchDB 已停止”或“底层快照具备一致性”。

---

## 10. 跨服务器迁移方案

### 10.1 需要迁移的内容

#### MinIO

- MinIO Compose 文件和脚本；
- Caddy 配置和证书数据，或在新服务器重新签发证书；
- MinIO 数据卷；
- MinIO 备份卷；
- `.env` 中的 Access Key、Secret Key、Bucket 和镜像配置；
- Remotely Save 客户端 Endpoint 和凭据；
- Caddy 镜像 tag 与 digest。

#### CouchDB

- `compose.yaml`、`config/`、`scripts/`；
- CouchDB 数据或 CouchDB 原生复制结果；
- `.env` 中的管理员凭据、`COUCHDB_SECRET` 和数据库名；
- LiveSync Caddy 路由；
- TLS 证书或新服务器自动签发策略；
- LiveSync E2EE 密码、Setup URI 和设备配置，通过带外方式传输。

真实 `.env`、SSH 私钥、TLS 私钥、Setup URI 和 E2EE 密码不要通过 Git 迁移。

### 10.2 迁移前准备

至少提前几天完成：

1. 新服务器 SSH、系统、防火墙和 Docker 审计；
2. 克隆两个仓库并锁定 commit；
3. 创建新服务器 `.env`，权限 `600`；
4. 降低 DNS TTL；
5. 在新服务器执行 MinIO 和 CouchDB preflight；
6. 复制一份历史备份到新服务器并做隔离恢复演练；
7. 验证 Caddy、TLS、MinIO health、CouchDB auth；
8. 记录旧服务器 IP、旧镜像 digest、旧 commit、旧 DNS；
9. 准备回滚步骤和维护窗口通知。

### 10.3 CouchDB 最终一致性迁移

优先级：

1. CouchDB 原生复制或官方支持的复制方式；
2. 写入冻结后执行逻辑导出/导入；
3. 停止 CouchDB 后做文件级一致备份并恢复。

不推荐在生产写入持续进行时直接复制 `/opt/obsidian-livesync/data/couchdb`。这可能遗漏事务状态、索引状态或正在写入的数据页。

建议迁移窗口：

```text
T-30 分钟：确认新服务器健康、TLS、DNS、Compose 和备份
T-10 分钟：所有 Obsidian 设备完成最后同步并停止编辑
T-05 分钟：冻结旧服务写入或停止旧入口
T+00 分钟：执行最终复制、逻辑导出或一致性备份
T+10 分钟：新服务器启动服务并验证数据库
T+15 分钟：切换 DNS
T+20 分钟：桌面端验证同步
T+30 分钟：手机前台验证同步
T+60 分钟：观察日志、错误率、磁盘、内存
```

### 10.4 MinIO 迁移

推荐使用 `install.sh export/import` 或经过验证的 MinIO/S3 复制方式。流程：

1. 让 Remotely Save 在所有设备完成最后同步；
2. 暂停客户端写入；
3. 执行 `sudo ./install.sh export`；
4. 验证压缩包；
5. 传输到新服务器；
6. 在新服务器安装 MinIO 项目；
7. 执行 `install.sh import`；
8. 验证 health endpoint；
9. 用一个测试客户端执行受控同步；
10. DNS 切换后再逐步恢复所有客户端。

如果只迁移 CouchDB，不要动 MinIO 数据和客户端配置。

### 10.5 DNS 切换和回滚

切换前：

```bash
dig +short minio.example.com
dig +short sync.example.com
curl -I https://sync.example.com/
curl -I https://minio.example.com/minio/health/live
```

切换 DNS 后保留旧服务器 24 至 72 小时。若失败：

1. 暂停新服务器客户端写入；
2. DNS 恢复到旧服务器；
3. 等待 TTL；
4. 客户端重新连接旧 Endpoint；
5. 不删除新服务器数据；
6. 保留日志和备份用于分析；
7. 如有两端写入，需要人工选择唯一可信源合并。

### 10.6 迁移后验收

MinIO：

- Caddy 健康；
- MinIO 容器健康；
- API HTTPS 返回 `200`；
- Bucket 可访问；
- Remotely Save 受控同步成功；
- 小附件和大附件均可读写；
- 日志无新增严重错误。

CouchDB：

- `sync.example.com` 证书匹配；
- 匿名访问被拒绝；
- 鉴权后 `_up` 正常；
- 指定数据库可访问；
- 5984 未绑定宿主机；
- LiveSync 桌面端双向同步成功；
- 手机前台同步成功；
- 离线编辑恢复联网后能追赶；
- `_changes` 持续连接不被代理缓冲或超时破坏。

---

## 11. 日常维护计划

### 11.1 每日检查

```bash
sudo docker ps --format 'table {{.Names}}\t{{.Status}}'
sudo docker stats --no-stream
df -h
df -ih
sudo docker logs --since 24h obsidian-minio-minio 2>&1 | grep -Ei 'error|fatal|panic' || true
sudo docker logs --since 24h obsidian-livesync-couchdb 2>&1 | grep -Ei 'error|fatal|panic' || true
find /opt/backup -type f -printf '%TY-%Tm-%Td %TH:%TM %s %p\n' | sort
```

### 11.2 每周检查

- 检查备份文件数量和大小趋势；
- 下载一份备份到本地；
- 执行 `gzip -t` 和 SHA-256 校验；
- 检查 Docker 日志是否增长过快；
- 检查 TLS 证书；
- 检查磁盘 inode；
- 检查防火墙规则；
- 确认 `5984/9000/9001` 未公网监听；
- 查看是否存在 Watchtower、Diun 等自动更新工具。

### 11.3 每月检查

- 在隔离环境恢复一次 MinIO 备份；
- 在隔离环境恢复一次 CouchDB 备份；
- 测试 Remotely Save 客户端连接；
- 测试 LiveSync 桌面端和手机前台同步；
- 审查镜像版本和 digest；
- 审查 SSH 登录和密钥；
- 审查 `.env` 权限；
- 审查异机备份；
- 更新迁移文档中的 commit、镜像和目录信息。

### 11.4 镜像升级

不要使用 `latest`，不要让 Watchtower 自动升级生产容器。流程：

1. 阅读官方发行说明；
2. 记录当前 tag、digest、容器 ID 和配置 hash；
3. 完成并验证备份；
4. 在测试环境拉取新镜像；
5. 执行 `docker compose config`；
6. 执行应用健康检查；
7. 只重建目标服务；
8. 观察日志和客户端同步；
9. 保留旧镜像一段时间用于回滚。

Caddy 固定写法示例：

```yaml
image: caddy:2.11.4-alpine@sha256:5f5c8640aae01df9654968d946d8f1a56c497f1dd5c5cda4cf95ab7c14d58648
```

---

## 12. 常见故障排查

### 12.1 MinIO 域名无法访问

```bash
cd /opt/obsidian-minio-sync
sudo docker compose ps
sudo docker logs --tail=100 obsidian-minio-caddy
sudo docker logs --tail=100 obsidian-minio-minio
curl -vk https://minio.example.com/minio/health/live
```

重点检查：Caddy 是否健康、DNS 是否指向正确 IP、80/443 是否冲突、MinIO healthcheck 是否正常、Remotely Save 是否开启 Path Style、Access Key/Secret Key 是否正确。

### 12.2 LiveSync 鉴权失败

匿名请求返回 `401/403` 是正常的。带凭据仍失败时检查：

```bash
cd /opt/obsidian-livesync
sudo ./scripts/validate.sh
sudo docker compose --env-file .env -f compose.yaml logs --tail=200 couchdb
curl -vk https://sync.example.com/_up
```

重点检查：URL 是否 HTTPS、用户名密码是否正确、数据库名是否正确、Caddy 是否转发 Authorization、CouchDB 是否健康、Caddy 是否连接 `obsidian-livesync-proxy`。

### 12.3 LiveSync 同步卡住

重点检查：

- Caddy `flush_interval -1`；
- 反代读写超时；
- 请求体大小限制；
- 是否存在缓存或缓冲 `_changes` 的代理；
- 手机是否被系统暂停后台；
- E2EE 密码是否一致；
- 是否有两个插件同时同步同一 Vault。

### 12.4 磁盘空间不足

```bash
df -h
df -ih
sudo docker system df
sudo du -sh /opt/obsidian-livesync/data/couchdb
sudo du -sh /opt/backup/*
```

不要直接执行 `docker system prune`。先确认哪些备份可以按保留策略删除、哪些镜像仍被容器使用、CouchDB 或 MinIO 是否异常增长，以及是否需要扩容数据盘。

### 12.5 Caddy 配置变更失败

恢复流程：

1. 停止继续修改；
2. 找到 `/opt/backup/` 中对应时间戳的代理备份；
3. 恢复 `docker-compose.yml` 和 `Caddyfile`；
4. 执行 Caddy 配置验证；
5. 只重建 Caddy；
6. 检查 MinIO 和 LiveSync 两个域名；
7. 确认 MinIO 容器 ID 没有变化。

不要为了修复 Caddy 执行整个 MinIO 项目的 `down`。

---

## 13. 安全检查清单

### 部署前

- [ ] 已验证 SSH 主机身份；
- [ ] 已确认服务器没有连错；
- [ ] 已确认 DNS；
- [ ] 已确认 80/443 的实际占用者；
- [ ] 已确认 5984/9000/9001 不会公网暴露；
- [ ] 已检查云防火墙和主机防火墙；
- [ ] 已创建备份目录；
- [ ] 已准备强随机凭据；
- [ ] `.env` 权限为 `600`；
- [ ] `.env` 未提交 Git；
- [ ] 已运行 preflight。

### 变更前

- [ ] 已备份 Compose 和代理配置；
- [ ] 已记录容器 ID、镜像 ID 和 digest；
- [ ] 已记录 MinIO 数据卷；
- [ ] 已验证备份文件存在且可读取；
- [ ] 已执行 `docker compose config`；
- [ ] 已执行 Caddy `validate`；
- [ ] 已准备回滚命令；
- [ ] 已确认不会使用 `down -v` 或 prune。

### 变更后

- [ ] Caddy 健康；
- [ ] MinIO 容器 ID 未改变；
- [ ] CouchDB 容器健康；
- [ ] MinIO Live/Ready 返回 `200`；
- [ ] LiveSync 匿名访问返回 `401/403`；
- [ ] LiveSync 授权访问正常；
- [ ] TLS 主机名和证书链正确；
- [ ] 5984/9000/9001 没有宿主机监听；
- [ ] 日志无新增严重错误；
- [ ] 客户端测试已由用户完成。

---

## 14. 最终建议

1. MinIO 和 CouchDB 继续保持独立 Compose 项目、独立数据目录和独立备份策略。
2. 公网入口只使用一个 Caddy，不要让两个代理竞争 80/443。
3. CouchDB 永远不要绑定到 `0.0.0.0:5984`。
4. MinIO API、Console 和 CouchDB 端口都不要直接开放公网。
5. 所有镜像使用固定版本和 digest，禁止 `latest` 和自动更新器直接改生产。
6. 同一个 Vault 只选择一个同步插件。
7. 迁移时先测试、再冻结写入、再做一致性复制、最后切 DNS。
8. 备份必须经过存在性、大小、压缩完整性、哈希和实际恢复验证。
9. `.tar.gz` 可以本地解包查看目录，但 MinIO 内部对象布局和 CouchDB `.couch` 文件不适合作为普通笔记阅读；需要阅读内容时使用 S3 导出、CouchDB 逻辑 JSON 导出或客户端 Vault 文件备份。
10. 不要把“容器还在运行”当成“数据已经备份”或“客户端同步已经验收”。
