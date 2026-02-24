#!/bin/bash
# scripts/vault-pass.sh
# Retrieves the Ansible Vault password from Vaultwarden via bw CLI.
# Referenced in ansible.cfg as vault_password_file.
#
# Bootstrap-safe: If bw CLI is not installed or not configured,
# returns a dummy password so Ansible can run without vault-encrypted
# files during initial setup. Vault-encrypted vars will fail to decrypt
# individually but non-encrypted playbooks work fine.
#
# Prerequisites (for production use):
#   - bw CLI installed on the master server
#   - BW_SESSION or master password available
#   - Vaultwarden item named per config (default: "lococloudd-ansible-vault")

set -euo pipefail

# If ANSIBLE_VAULT_PASSWORD is set as env var, use it directly
if [ -n "${ANSIBLE_VAULT_PASSWORD:-}" ]; then
    echo "${ANSIBLE_VAULT_PASSWORD}"
    exit 0
fi

# If a local password file exists (for initial bootstrap), use it
VAULT_PASS_FILE="/root/.loco-vault-pass"
if [ -f "${VAULT_PASS_FILE}" ]; then
    cat "${VAULT_PASS_FILE}"
    exit 0
fi

# Check if bw CLI is available
if ! command -v bw &>/dev/null; then
    echo "bootstrap-no-vault-configured" >&2
    echo "bootstrap-dummy-password"
    exit 0
fi

# Try to unlock vault and get session
_bw_session="$(bw unlock --raw 2>/dev/null)" || {
    echo "WARNING: Could not unlock Bitwarden vault. Using dummy password." >&2
    echo "bootstrap-dummy-password"
    exit 0
}

# Retrieve the vault password
bw get password "lococloudd-ansible-vault" --session "${_bw_session}" --raw 2>/dev/null || {
    echo "WARNING: Could not retrieve Ansible Vault password. Using dummy password." >&2
    echo "bootstrap-dummy-password"
    exit 0
}
