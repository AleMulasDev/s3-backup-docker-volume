# S3 Backup Docker Volume

A lightweight Docker sidecar container that backs up Docker volumes to any S3-compatible storage. Add it to any `docker-compose.yml` to get automated, scheduled backups with optional encryption and retention policies.

**~35 MB image** — Alpine 3.21 + rclone + supercronic.

## Features

- **Any S3-compatible backend** — AWS S3, MinIO, Wasabi, Backblaze B2, Cloudflare R2, DigitalOcean Spaces, and [50+ more](https://rclone.org/s3/#s3-provider)
- **Cron-scheduled** — configurable schedule via cron expression (default: 2 AM UTC daily)
- **Compressed archives** — each backup is a timestamped `.tar.gz`
- **File exclusion** — regex-based pattern to skip files (logs, temp files, caches)
- **Client-side encryption** — optional rclone crypt encryption before upload
- **Time-based retention** — auto-delete backups older than N days
- **Zero config files** — everything configured via environment variables
- **Container-native cron** — uses [supercronic](https://github.com/aptible/supercronic) (proper signal handling, env passthrough, stdout logging)

## Quick Start

### 1. Add to your existing docker-compose.yml

```yaml
services:
  # Your existing service
  app:
    image: my-app:latest
    volumes:
      - app-data:/data

  # Add the backup sidecar
  backup:
    build: https://github.com/user/s3-backup-docker-volume.git
    volumes:
      - app-data:/backup/data:ro
    environment:
      BACKUP_PATH: /backup/data
      S3_ENDPOINT: https://s3.amazonaws.com
      S3_ACCESS_KEY: ${S3_ACCESS_KEY}
      S3_SECRET_KEY: ${S3_SECRET_KEY}
      S3_BUCKET: my-backups
      S3_PATH: /app-backups
      BACKUP_PREFIX: my-app
      BACKUP_CRON: "0 2 * * *"
    restart: unless-stopped

volumes:
  app-data:
```

### 2. Set your credentials

```bash
cp .env.example .env
# Edit .env with your S3 credentials
```

### 3. Start

```bash
docker compose up -d
```

The backup container will start and wait for the cron schedule. To test immediately:

```bash
docker compose exec backup /scripts/backup.sh
```

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `BACKUP_PATH` | **Yes** | — | Path inside the container to back up |
| `S3_ENDPOINT` | **Yes** | — | S3-compatible endpoint URL |
| `S3_ACCESS_KEY` | **Yes** | — | S3 access key ID |
| `S3_SECRET_KEY` | **Yes** | — | S3 secret access key |
| `S3_BUCKET` | **Yes** | — | S3 bucket name |
| `S3_REGION` | No | `us-east-1` | S3 region |
| `S3_PROVIDER` | No | `Minio` | rclone S3 provider preset (see below) |
| `S3_PATH` | No | `/` | Path prefix inside the bucket |
| `BACKUP_CRON` | No | `0 2 * * *` | Cron expression (default: 2 AM UTC) |
| `BACKUP_PREFIX` | No | `backup` | Archive filename prefix |
| `BACKUP_RETENTION_DAYS` | No | `30` | Delete archives older than N days (0 = keep all) |
| `EXCLUDE_REGEX` | No | — | Regex pattern for files to exclude |
| `ENCRYPTION_PASSWORD` | No | — | Enables client-side encryption |
| `ENCRYPTION_SALT` | No | — | Additional salt for encryption |
| `TZ` | No | `UTC` | Container timezone |

## S3 Provider Presets

The `S3_PROVIDER` variable tells rclone which S3-compatible backend you're using, so it can handle provider-specific quirks automatically:

| Provider | `S3_PROVIDER` | `S3_ENDPOINT` example |
|---|---|---|
| Amazon AWS | `AWS` | `https://s3.amazonaws.com` |
| MinIO | `Minio` | `http://minio:9000` |
| Wasabi | `Wasabi` | `https://s3.wasabisys.com` |
| Backblaze B2 | `B2` | `https://s3.us-west-004.backblazeb2.com` |
| Cloudflare R2 | `Cloudflare` | `https://<account-id>.r2.cloudflarestorage.com` |
| DigitalOcean Spaces | `DigitalOcean` | `https://<region>.digitaloceanspaces.com` |
| Linode Object Storage | `Linode` | `https://<region>.linodeobjects.com` |
| Scaleway | `Scaleway` | `https://s3.<region>.scw.cloud` |
| Any S3-compatible | `Minio` or `Other` | Your endpoint URL |

For the full list, see [rclone S3 providers](https://rclone.org/s3/#s3-provider).

## Examples

### AWS S3

```yaml
backup:
  build: https://github.com/user/s3-backup-docker-volume.git
  volumes:
    - app-data:/backup/data:ro
  environment:
    BACKUP_PATH: /backup/data
    S3_ENDPOINT: https://s3.amazonaws.com
    S3_REGION: eu-west-1
    S3_PROVIDER: AWS
    S3_ACCESS_KEY: ${AWS_ACCESS_KEY_ID}
    S3_SECRET_KEY: ${AWS_SECRET_ACCESS_KEY}
    S3_BUCKET: my-app-backups
    S3_PATH: /production
    BACKUP_PREFIX: prod-app
```

### MinIO (self-hosted)

```yaml
backup:
  build: https://github.com/user/s3-backup-docker-volume.git
  volumes:
    - app-data:/backup/data:ro
  environment:
    BACKUP_PATH: /backup/data
    S3_ENDPOINT: http://minio:9000
    S3_PROVIDER: Minio
    S3_ACCESS_KEY: minioadmin
    S3_SECRET_KEY: minioadmin
    S3_BUCKET: backups
```

### Backblaze B2

```yaml
backup:
  build: https://github.com/user/s3-backup-docker-volume.git
  volumes:
    - app-data:/backup/data:ro
  environment:
    BACKUP_PATH: /backup/data
    S3_ENDPOINT: https://s3.us-west-004.backblazeb2.com
    S3_REGION: us-west-004
    S3_PROVIDER: B2
    S3_ACCESS_KEY: ${B2_KEY_ID}
    S3_SECRET_KEY: ${B2_APPLICATION_KEY}
    S3_BUCKET: my-backups
```

### Cloudflare R2

```yaml
backup:
  build: https://github.com/user/s3-backup-docker-volume.git
  volumes:
    - app-data:/backup/data:ro
  environment:
    BACKUP_PATH: /backup/data
    S3_ENDPOINT: https://${CF_ACCOUNT_ID}.r2.cloudflarestorage.com
    S3_PROVIDER: Cloudflare
    S3_ACCESS_KEY: ${R2_ACCESS_KEY}
    S3_SECRET_KEY: ${R2_SECRET_KEY}
    S3_BUCKET: backups
```

### With encryption and exclusions

```yaml
backup:
  build: https://github.com/user/s3-backup-docker-volume.git
  volumes:
    - app-data:/backup/data:ro
  environment:
    BACKUP_PATH: /backup/data
    S3_ENDPOINT: https://s3.amazonaws.com
    S3_PROVIDER: AWS
    S3_ACCESS_KEY: ${AWS_ACCESS_KEY_ID}
    S3_SECRET_KEY: ${AWS_SECRET_ACCESS_KEY}
    S3_BUCKET: encrypted-backups
    EXCLUDE_REGEX: "\\.log$|\\.tmp$|\\.cache$|/node_modules/"
    ENCRYPTION_PASSWORD: ${BACKUP_ENCRYPTION_PASSWORD}
    ENCRYPTION_SALT: ${BACKUP_ENCRYPTION_SALT}
    BACKUP_RETENTION_DAYS: 90
    BACKUP_CRON: "0 */6 * * *"
    BACKUP_PREFIX: my-app-encrypted
```

### Multiple volumes from different services

```yaml
services:
  postgres:
    image: postgres:16
    volumes:
      - pg-data:/var/lib/postgresql/data

  redis:
    image: redis:7
    volumes:
      - redis-data:/data

  backup-postgres:
    build: https://github.com/user/s3-backup-docker-volume.git
    volumes:
      - pg-data:/backup/data:ro
    environment:
      BACKUP_PATH: /backup/data
      S3_ENDPOINT: https://s3.amazonaws.com
      S3_ACCESS_KEY: ${S3_ACCESS_KEY}
      S3_SECRET_KEY: ${S3_SECRET_KEY}
      S3_BUCKET: my-backups
      S3_PATH: /postgres
      BACKUP_PREFIX: postgres
      EXCLUDE_REGEX: "pg_stat_tmp|pg_replslot"

  backup-redis:
    build: https://github.com/user/s3-backup-docker-volume.git
    volumes:
      - redis-data:/backup/data:ro
    environment:
      BACKUP_PATH: /backup/data
      S3_ENDPOINT: https://s3.amazonaws.com
      S3_ACCESS_KEY: ${S3_ACCESS_KEY}
      S3_SECRET_KEY: ${S3_SECRET_KEY}
      S3_BUCKET: my-backups
      S3_PATH: /redis
      BACKUP_PREFIX: redis
      BACKUP_CRON: "0 */4 * * *"

volumes:
  pg-data:
  redis-data:
```

## File Exclusion

The `EXCLUDE_REGEX` variable accepts an extended regex (ERE) pattern that is matched against relative file paths. Files matching the pattern are excluded from the archive.

```bash
# Exclude log files
EXCLUDE_REGEX="\\.log$"

# Exclude multiple extensions
EXCLUDE_REGEX="\\.(log|tmp|cache|swp)$"

# Exclude directories
EXCLUDE_REGEX="^\\./node_modules/|^\\./\\.git/"

# Combine patterns
EXCLUDE_REGEX="\\.(log|tmp)$|^\\./cache/|^\\./temp/"
```

## Client-Side Encryption

When `ENCRYPTION_PASSWORD` is set, all archives are encrypted using [rclone crypt](https://rclone.org/crypt/) before being uploaded. This means:

- File contents are encrypted with XSalsa20 + Poly1305
- File names in the S3 bucket are obfuscated
- **You need the same password (and salt) to decrypt/restore**
- The S3 provider cannot read your data

To restore an encrypted backup, you'll need rclone with the same crypt configuration:

```bash
# Create rclone config for decryption
rclone config
# Set up an S3 remote, then a crypt remote wrapping it with the same password

# Download and decrypt
rclone copy encrypted:backup-2026-02-16T02-00-00Z.tar.gz /local/path/
```

## Restoring a Backup

```bash
# List available backups
docker compose exec backup rclone --config /tmp/rclone.conf ls "${RCLONE_REMOTE}/"

# Download a specific backup (non-encrypted)
rclone --config rclone.conf copy s3remote:my-bucket/path/backup-2026-02-16T02-00-00Z.tar.gz ./

# Extract
tar -xzf backup-2026-02-16T02-00-00Z.tar.gz -C /restore/path/
```

## Manual Backup

To trigger a backup immediately without waiting for cron:

```bash
docker compose exec backup /scripts/backup.sh
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│  docker-compose.yml                             │
│                                                 │
│  ┌──────────┐     ┌──────────────────────────┐  │
│  │  app      │     │  backup (sidecar)        │  │
│  │          │     │                          │  │
│  │  /data ──┼─────┼── /backup/data (ro)      │  │
│  │          │     │                          │  │
│  └──────────┘     │  supercronic             │  │
│       │           │    └─ backup.sh (cron)   │  │
│       │           │        ├─ tar + gzip     │  │
│  ┌────┴─────┐     │        ├─ rclone upload  │  │
│  │ app-data │     │        └─ retention      │  │
│  │ (volume) │     └──────────┬───────────────┘  │
│  └──────────┘                │                  │
└──────────────────────────────┼──────────────────┘
                               │
                    ┌──────────▼──────────┐
                    │  S3-compatible       │
                    │  storage backend     │
                    │  (AWS/MinIO/B2/R2)  │
                    └─────────────────────┘
```

## Building

```bash
# Build locally
docker build -t s3-backup .

# Build for multiple architectures
docker buildx build --platform linux/amd64,linux/arm64 -t s3-backup .
```

## License

MIT
