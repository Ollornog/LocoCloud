#!/bin/bash
# scripts/vault-pass.sh
# Retrieves the Ansible Vault password from Vaultwarden via bw CLI.
# Referenced in ansible.cfg as vault_password_file.
#
# Prerequisites:
#   - bw CLI installed on the master server
#   - BW_SESSION or master password available
#   - Vaultwarden item named per config (default: "lococloudd-ansible-vault")

set -euo pipefail

# Unlock vault and get session
_bw_session="$(bw unlock --raw 2>/dev/null)" || {
    echo "ERROR: Could not unlock Bitwarden vault. Is bw CLI configured?" >&2
    exit 1
}

# Retrieve the vault password
bw get password "lococloudd-ansible-vault" --session "${_bw_session}" --raw 2>/dev/null || {
    echo "ERROR: Could not retrieve Ansible Vault password from Vaultwarden." >&2
    exit 1
}
