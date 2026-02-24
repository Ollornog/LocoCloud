#!/bin/bash
# ============================================
# pre-backup.sh — Pre-backup DB dumps
# Called by Restic backup cron before snapshot
# Dumps PostgreSQL and MariaDB databases to /opt/backups/dumps/
# ============================================
set -euo pipefail

DUMP_DIR="/opt/backups/dumps"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "${DUMP_DIR}"

echo "[pre-backup] Starting DB dumps at $(date)"

# PostgreSQL dumps (all running PostgreSQL containers)
for container in $(docker ps --format '{{.Names}}' --filter 'ancestor=postgres*' 2>/dev/null); do
  echo "[pre-backup] Dumping PostgreSQL from ${container}..."
  docker exec "${container}" pg_dumpall -U postgres > "${DUMP_DIR}/${container}_pg_${TIMESTAMP}.sql" 2>/dev/null || \
    echo "[pre-backup] WARNING: Failed to dump ${container}"
done

# MariaDB/MySQL dumps (all running MariaDB containers)
for container in $(docker ps --format '{{.Names}}' --filter 'ancestor=mariadb*' 2>/dev/null); do
  echo "[pre-backup] Dumping MariaDB from ${container}..."
  docker exec "${container}" sh -c 'mysqldump --all-databases -u root -p"${MYSQL_ROOT_PASSWORD}"' \
    > "${DUMP_DIR}/${container}_mysql_${TIMESTAMP}.sql" 2>/dev/null || \
    echo "[pre-backup] WARNING: Failed to dump ${container}"
done

# Also check for containers with "postgres" or "mariadb" in name
for container in $(docker ps --format '{{.Names}}' | grep -i postgres 2>/dev/null); do
  if [ ! -f "${DUMP_DIR}/${container}_pg_${TIMESTAMP}.sql" ]; then
    echo "[pre-backup] Dumping PostgreSQL from ${container}..."
    docker exec "${container}" pg_dumpall -U postgres > "${DUMP_DIR}/${container}_pg_${TIMESTAMP}.sql" 2>/dev/null || true
  fi
done

for container in $(docker ps --format '{{.Names}}' | grep -i mariadb 2>/dev/null); do
  if [ ! -f "${DUMP_DIR}/${container}_mysql_${TIMESTAMP}.sql" ]; then
    echo "[pre-backup] Dumping MariaDB from ${container}..."
    docker exec "${container}" sh -c 'mysqldump --all-databases -u root -p"${MYSQL_ROOT_PASSWORD}"' \
      > "${DUMP_DIR}/${container}_mysql_${TIMESTAMP}.sql" 2>/dev/null || true
  fi
done

# Cleanup old dumps (keep last 3)
find "${DUMP_DIR}" -name "*.sql" -mtime +3 -delete 2>/dev/null || true

echo "[pre-backup] DB dumps completed at $(date)"
