#!/bin/bash
# scripts/new-customer.sh
# Generate customer inventory from templates.
#
# Usage: bash scripts/new-customer.sh <kunde_id> "<kunde_name>" "<kunde_domain>"
# Example: bash scripts/new-customer.sh abc001 "Firma ABC GmbH" "firma-abc.de"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE_DIR="${REPO_DIR}/inventories/_template"

# --- Argument parsing ---
if [ $# -lt 3 ]; then
    echo "Usage: $0 <kunde_id> <kunde_name> <kunde_domain>"
    echo ""
    echo "Example: $0 abc001 \"Firma ABC GmbH\" \"firma-abc.de\""
    exit 1
fi

KUNDE_ID="$1"
KUNDE_NAME="$2"
KUNDE_DOMAIN="$3"

# --- Target directory ---
TARGET_DIR="${REPO_DIR}/inventories/kunde-${KUNDE_ID}"

if [ -d "$TARGET_DIR" ]; then
    echo "ERROR: Inventory directory already exists: ${TARGET_DIR}"
    exit 1
fi

echo "Creating customer inventory: ${TARGET_DIR}"
echo "  Customer: ${KUNDE_NAME}"
echo "  Domain:   ${KUNDE_DOMAIN}"
echo ""

# --- Create directory ---
mkdir -p "${TARGET_DIR}/group_vars"

# --- Generate hosts.yml (simple variable substitution) ---
sed -e "s/{{ kunde_id }}/${KUNDE_ID}/g" \
    "${TEMPLATE_DIR}/hosts.yml.j2" > "${TARGET_DIR}/hosts.yml"

# --- Generate group_vars/all.yml ---
sed -e "s/{{ kunde_id }}/${KUNDE_ID}/g" \
    -e "s/{{ kunde_name }}/${KUNDE_NAME}/g" \
    -e "s/{{ kunde_domain }}/${KUNDE_DOMAIN}/g" \
    "${TEMPLATE_DIR}/group_vars/all.yml.j2" > "${TARGET_DIR}/group_vars/all.yml"

# --- Create empty vault file ---
cat > "${TARGET_DIR}/group_vars/vault.yml" <<VAULT
---
# Encrypted with: ansible-vault encrypt inventories/kunde-${KUNDE_ID}/group_vars/vault.yml
# Contains: Netbird keys, server IPs, Proxmox tokens

vault_master_ssh_pubkey: ""
vault_netbird_setup_key: ""
vault_gateway_netbird_ip: ""
vault_app01_netbird_ip: ""
vault_proxmox_token: ""
vault_proxmox_netbird_ip: ""
VAULT

echo ""
echo "Customer inventory created successfully!"
echo ""
echo "Next steps:"
echo "  1. Edit: ${TARGET_DIR}/hosts.yml"
echo "     - Configure server_roles per host"
echo "     - Set hosting_type (cloud / proxmox_lxc)"
echo "     - Uncomment proxmox section if needed"
echo "  2. Edit: ${TARGET_DIR}/group_vars/all.yml"
echo "     - Add SSH public keys"
echo "     - Configure apps_enabled"
echo "     - Configure kunden_users"
echo "  3. Edit: ${TARGET_DIR}/group_vars/vault.yml"
echo "     - Fill in Netbird keys, IPs, tokens"
echo "  4. Encrypt: ansible-vault encrypt ${TARGET_DIR}/group_vars/vault.yml"
echo "  5. Deploy: ansible-playbook playbooks/onboard-customer.yml -i ${TARGET_DIR}/"
