#!/bin/bash
set -euo pipefail

# =============================================================================
# entrypoint.sh — Generates rclone config and crontab, then starts supercronic
# =============================================================================

# ---------------------------------------------------------------------------
# Validate required environment variables
# ---------------------------------------------------------------------------
REQUIRED_VARS=(BACKUP_PATH S3_ENDPOINT S3_ACCESS_KEY S3_SECRET_KEY S3_BUCKET)
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: Required environment variable $var is not set."
        exit 1
    fi
done

if [ ! -d "${BACKUP_PATH}" ]; then
    echo "ERROR: BACKUP_PATH '${BACKUP_PATH}' does not exist or is not a directory."
    exit 1
fi

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
S3_REGION="${S3_REGION:-us-east-1}"
S3_PROVIDER="${S3_PROVIDER:-Minio}"
S3_PATH="${S3_PATH:-/}"
BACKUP_CRON="${BACKUP_CRON:-0 2 * * *}"
BACKUP_PREFIX="${BACKUP_PREFIX:-backup}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
TZ="${TZ:-UTC}"

# ---------------------------------------------------------------------------
# Generate rclone config
# ---------------------------------------------------------------------------
RCLONE_CONFIG="/tmp/rclone.conf"

cat > "${RCLONE_CONFIG}" <<EOF
[s3remote]
type = s3
provider = ${S3_PROVIDER}
env_auth = false
access_key_id = ${S3_ACCESS_KEY}
secret_access_key = ${S3_SECRET_KEY}
endpoint = ${S3_ENDPOINT}
region = ${S3_REGION}
acl = private
EOF

# If the provider is Minio or generic S3-compat, disable bucket verification
# to work with providers that don't support ListBuckets
if [ "${S3_PROVIDER}" = "Minio" ] || [ "${S3_PROVIDER}" = "Other" ]; then
    echo "list_url_encode = false" >> "${RCLONE_CONFIG}"
fi

# ---------------------------------------------------------------------------
# Optional: client-side encryption via rclone crypt
# ---------------------------------------------------------------------------
RCLONE_REMOTE="s3remote:${S3_BUCKET}/${S3_PATH#/}"

if [ -n "${ENCRYPTION_PASSWORD:-}" ]; then
    echo "INFO: Client-side encryption enabled."

    # rclone crypt needs the password obscured
    OBSCURED_PASSWORD="$(rclone obscure "${ENCRYPTION_PASSWORD}")"

    cat >> "${RCLONE_CONFIG}" <<EOF

[encrypted]
type = crypt
remote = s3remote:${S3_BUCKET}/${S3_PATH#/}
password = ${OBSCURED_PASSWORD}
EOF

    # If a salt is provided, add it too
    if [ -n "${ENCRYPTION_SALT:-}" ]; then
        OBSCURED_SALT="$(rclone obscure "${ENCRYPTION_SALT}")"
        echo "password2 = ${OBSCURED_SALT}" >> "${RCLONE_CONFIG}"
    fi

    RCLONE_REMOTE="encrypted:"
fi

# Export variables needed by backup.sh
export RCLONE_CONFIG
export RCLONE_REMOTE
export BACKUP_PATH
export BACKUP_PREFIX
export BACKUP_RETENTION_DAYS
export EXCLUDE_REGEX="${EXCLUDE_REGEX:-}"

echo "====================================================="
echo "  S3 Backup Sidecar — Configuration"
echo "====================================================="
echo "  Backup path:      ${BACKUP_PATH}"
echo "  S3 endpoint:      ${S3_ENDPOINT}"
echo "  S3 region:        ${S3_REGION}"
echo "  S3 provider:      ${S3_PROVIDER}"
echo "  S3 bucket:        ${S3_BUCKET}"
echo "  S3 path:          ${S3_PATH}"
echo "  Cron schedule:    ${BACKUP_CRON}"
echo "  Archive prefix:   ${BACKUP_PREFIX}"
echo "  Retention (days): ${BACKUP_RETENTION_DAYS}"
echo "  Encryption:       $([ -n "${ENCRYPTION_PASSWORD:-}" ] && echo 'enabled' || echo 'disabled')"
echo "  Exclude regex:    ${EXCLUDE_REGEX:-<none>}"
echo "  Timezone:         ${TZ}"
echo "  Rclone remote:    ${RCLONE_REMOTE}"
echo "====================================================="

# ---------------------------------------------------------------------------
# Test S3 connectivity
# ---------------------------------------------------------------------------
echo "INFO: Testing S3 connectivity..."
if rclone --config "${RCLONE_CONFIG}" lsd "s3remote:${S3_BUCKET}" --max-depth 0 2>/dev/null; then
    echo "INFO: S3 connectivity OK."
else
    echo "WARN: Could not list bucket '${S3_BUCKET}'. The backup may still work if the bucket exists and permissions allow writes. Continuing..."
fi

# ---------------------------------------------------------------------------
# Generate crontab with environment variables
# ---------------------------------------------------------------------------
CRONTAB_FILE="/tmp/crontab"

# Supercronic inherits the exported environment from this process,
# so we only need the cron schedule line.
cat > "${CRONTAB_FILE}" <<EOF
${BACKUP_CRON} /scripts/backup.sh
EOF

# Strip any Windows CRLF that may leak from heredoc
sed -i 's/\r$//' "${CRONTAB_FILE}"

echo "INFO: Crontab generated: ${BACKUP_CRON} /scripts/backup.sh"

# ---------------------------------------------------------------------------
# Start supercronic
# ---------------------------------------------------------------------------
echo "INFO: Starting supercronic..."
exec /usr/local/bin/supercronic "${CRONTAB_FILE}"
