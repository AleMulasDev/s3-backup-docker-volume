#!/bin/bash
set -euo pipefail

# =============================================================================
# backup.sh — Creates a tar.gz archive and uploads it to S3 via rclone
# =============================================================================

TIMESTAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
ARCHIVE_NAME="${BACKUP_PREFIX}-${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="/tmp/backup/${ARCHIVE_NAME}"
START_TIME="$(date +%s)"

echo "====================================================="
echo "  Backup started at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "====================================================="

# ---------------------------------------------------------------------------
# Build exclusion arguments for tar
# ---------------------------------------------------------------------------
TAR_EXCLUDE_ARGS=()

if [ -n "${EXCLUDE_REGEX:-}" ]; then
    echo "INFO: Building file list with exclusion regex: ${EXCLUDE_REGEX}"

    # Use find + grep to build a list of files to exclude
    EXCLUDE_LIST="/tmp/backup/exclude_list.txt"
    : > "${EXCLUDE_LIST}"

    # Find all files, get paths relative to BACKUP_PATH, filter matching ones
    cd "${BACKUP_PATH}"
    find . -type f | grep -E "${EXCLUDE_REGEX}" > "${EXCLUDE_LIST}" 2>/dev/null || true

    EXCLUDED_COUNT="$(wc -l < "${EXCLUDE_LIST}" | tr -d ' ')"
    echo "INFO: Excluding ${EXCLUDED_COUNT} file(s) matching regex."

    if [ "${EXCLUDED_COUNT}" -gt 0 ]; then
        # Show first 10 excluded files for debugging
        echo "INFO: First excluded files (up to 10):"
        head -10 "${EXCLUDE_LIST}" | sed 's/^/  /'
        if [ "${EXCLUDED_COUNT}" -gt 10 ]; then
            echo "  ... and $((EXCLUDED_COUNT - 10)) more"
        fi
        TAR_EXCLUDE_ARGS=(--exclude-from="${EXCLUDE_LIST}")
    fi
fi

# ---------------------------------------------------------------------------
# Create tar.gz archive
# ---------------------------------------------------------------------------
echo "INFO: Creating archive: ${ARCHIVE_NAME}"

cd "${BACKUP_PATH}"
tar -czf "${ARCHIVE_PATH}" \
    "${TAR_EXCLUDE_ARGS[@]+"${TAR_EXCLUDE_ARGS[@]}"}" \
    .

ARCHIVE_SIZE="$(du -h "${ARCHIVE_PATH}" | cut -f1)"
echo "INFO: Archive created: ${ARCHIVE_SIZE}"

# ---------------------------------------------------------------------------
# Upload to S3 via rclone
# ---------------------------------------------------------------------------
echo "INFO: Uploading to ${RCLONE_REMOTE}..."

rclone --config "${RCLONE_CONFIG}" \
    copyto "${ARCHIVE_PATH}" "${RCLONE_REMOTE}/${ARCHIVE_NAME}" \
    --progress \
    --log-level INFO

echo "INFO: Upload complete."

# ---------------------------------------------------------------------------
# Clean up local archive
# ---------------------------------------------------------------------------
rm -f "${ARCHIVE_PATH}"

# ---------------------------------------------------------------------------
# Retention: delete backups older than BACKUP_RETENTION_DAYS
# ---------------------------------------------------------------------------
if [ "${BACKUP_RETENTION_DAYS:-0}" -gt 0 ]; then
    echo "INFO: Applying retention policy: deleting backups older than ${BACKUP_RETENTION_DAYS} days..."

    CUTOFF_EPOCH="$(date -u -d "-${BACKUP_RETENTION_DAYS} days" +%s 2>/dev/null || date -u -v-${BACKUP_RETENTION_DAYS}d +%s 2>/dev/null)"

    # List all files in the remote path
    REMOTE_FILES="/tmp/backup/remote_files.txt"
    rclone --config "${RCLONE_CONFIG}" \
        lsf "${RCLONE_REMOTE}/" \
        --files-only \
        > "${REMOTE_FILES}" 2>/dev/null || true

    DELETED_COUNT=0

    while IFS= read -r filename; do
        # Skip files that don't match our naming pattern
        # Expected: PREFIX-YYYY-MM-DDTHH-MM-SSZ.tar.gz
        if ! echo "${filename}" | grep -qE "^${BACKUP_PREFIX}-[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}Z\.tar\.gz$"; then
            continue
        fi

        # Extract the timestamp from the filename
        FILE_TIMESTAMP="$(echo "${filename}" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}Z')"
        if [ -z "${FILE_TIMESTAMP}" ]; then
            continue
        fi

        # Convert timestamp to a format date can parse: YYYY-MM-DD HH:MM:SS
        PARSED_DATE="$(echo "${FILE_TIMESTAMP}" | sed 's/T/ /;s/-\([0-9][0-9]\)-\([0-9][0-9]\)Z/:\1:\2/')"
        FILE_EPOCH="$(date -u -d "${PARSED_DATE}" +%s 2>/dev/null || echo "0")"

        if [ "${FILE_EPOCH}" -gt 0 ] && [ "${FILE_EPOCH}" -lt "${CUTOFF_EPOCH}" ]; then
            echo "INFO: Deleting expired backup: ${filename}"
            rclone --config "${RCLONE_CONFIG}" \
                deletefile "${RCLONE_REMOTE}/${filename}" \
                --log-level INFO || true
            DELETED_COUNT=$((DELETED_COUNT + 1))
        fi
    done < "${REMOTE_FILES}"

    rm -f "${REMOTE_FILES}"
    echo "INFO: Retention cleanup done. Deleted ${DELETED_COUNT} expired backup(s)."
else
    echo "INFO: Retention policy disabled (BACKUP_RETENTION_DAYS=0). Keeping all backups."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
END_TIME="$(date +%s)"
DURATION="$((END_TIME - START_TIME))"

echo "====================================================="
echo "  Backup completed successfully"
echo "  Archive:   ${ARCHIVE_NAME} (${ARCHIVE_SIZE})"
echo "  Remote:    ${RCLONE_REMOTE}/${ARCHIVE_NAME}"
echo "  Duration:  ${DURATION}s"
echo "  Finished:  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "====================================================="
