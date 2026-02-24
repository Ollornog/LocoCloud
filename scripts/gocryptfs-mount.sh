#!/bin/bash
# ============================================
# gocryptfs-mount.sh — Auto-mount gocryptfs after reboot
# Fetches keyfile from master, mounts /mnt/data, removes keyfile
# Called by systemd gocryptfs-mount.service
# ============================================
set -euo pipefail

CIPHER_DIR="${GOCRYPTFS_CIPHER_DIR:-/mnt/data-encrypted}"
PLAIN_DIR="${GOCRYPTFS_PLAIN_DIR:-/mnt/data}"
MASTER_HOST="${GOCRYPTFS_MASTER_HOST:-}"
MASTER_USER="${GOCRYPTFS_MASTER_USER:-root}"
MASTER_KEY_PATH="${GOCRYPTFS_MASTER_KEY_PATH:-/opt/lococloudd/keys}"
SSH_KEY="${GOCRYPTFS_SSH_KEY:-/root/.ssh/id_ed25519}"
LOCAL_KEYFILE="/tmp/gocryptfs-$(hostname).key"
HOSTNAME=$(hostname)

# Check if already mounted
if mountpoint -q "${PLAIN_DIR}"; then
  echo "[gocryptfs] ${PLAIN_DIR} is already mounted."
  exit 0
fi

# Validate master host is configured
if [ -z "${MASTER_HOST}" ]; then
  echo "[gocryptfs] ERROR: GOCRYPTFS_MASTER_HOST not set. Cannot fetch keyfile."
  exit 1
fi

# Ensure directories exist
mkdir -p "${CIPHER_DIR}" "${PLAIN_DIR}"

# Fetch keyfile from master
echo "[gocryptfs] Fetching keyfile from master (${MASTER_HOST})..."
MAX_RETRIES=5
RETRY=0
while [ ${RETRY} -lt ${MAX_RETRIES} ]; do
  if scp -i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
    "${MASTER_USER}@${MASTER_HOST}:${MASTER_KEY_PATH}/${HOSTNAME}.key" "${LOCAL_KEYFILE}" 2>/dev/null; then
    echo "[gocryptfs] Keyfile fetched successfully."
    break
  fi
  RETRY=$((RETRY + 1))
  echo "[gocryptfs] Retry ${RETRY}/${MAX_RETRIES} — waiting..."
  sleep 10
done

if [ ! -f "${LOCAL_KEYFILE}" ]; then
  echo "[gocryptfs] ERROR: Failed to fetch keyfile after ${MAX_RETRIES} retries."
  exit 1
fi

# Mount gocryptfs
echo "[gocryptfs] Mounting ${CIPHER_DIR} to ${PLAIN_DIR}..."
gocryptfs -masterkey "$(cat "${LOCAL_KEYFILE}")" "${CIPHER_DIR}" "${PLAIN_DIR}"

# IMMEDIATELY remove keyfile
rm -f "${LOCAL_KEYFILE}"
echo "[gocryptfs] Keyfile removed from local server."

# Verify mount
if mountpoint -q "${PLAIN_DIR}"; then
  echo "[gocryptfs] Successfully mounted ${PLAIN_DIR}."
else
  echo "[gocryptfs] ERROR: Mount verification failed!"
  exit 1
fi
