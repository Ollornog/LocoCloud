#!/bin/bash
# scripts/setup.sh
# LocoCloud — Kompletter Setup vom blanken Debian-Server.
#
# Usage: curl -fsSL https://raw.githubusercontent.com/Ollornog/LocoCloud/main/scripts/setup.sh | bash
#   oder: bash scripts/setup.sh  (wenn Repo bereits geklont)
#
# Was das Script macht:
#   1. System aktualisieren (apt update/upgrade)
#   2. Grundpakete installieren (sudo, curl, git, etc.)
#   3. Netbird installieren und optional joinen
#   4. Repo klonen (falls noch nicht vorhanden)
#   5. Ansible installieren (pipx)
#   6. Ansible Collections installieren
#   7. Interaktiv: Domain, Name, E-Mail abfragen
#   8. config/lococloudd.yml automatisch generieren
#   9. Master-Inventar vorbereiten

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
ask()   { echo -en "${CYAN}$1${NC} "; read -r "$2"; }

REPO_DIR="/root/LocoCloud"

# =====================================================
# Phase 1: System aktualisieren + Grundpakete
# =====================================================
info "Phase 1: System aktualisieren und Grundpakete installieren"

apt update && apt upgrade -y

apt install -y \
  sudo \
  curl \
  wget \
  git \
  gnupg \
  ca-certificates \
  pipx \
  jq

ok "Grundpakete installiert"

# =====================================================
# Phase 2: Netbird installieren
# =====================================================
info "Phase 2: Netbird installieren"

if command -v netbird &>/dev/null; then
  ok "Netbird ist bereits installiert"
else
  curl -fsSL https://pkgs.netbird.io/install.sh | sh
  ok "Netbird installiert"
fi

echo ""
echo "Netbird muss mit einem Management-Server verbunden werden."
echo "Falls du einen eigenen Netbird-Server betreibst, gib die URL an."
echo "Falls noch kein Netbird-Server existiert, kannst du diesen Schritt ueberspringen"
echo "und spaeter 'netbird up' manuell ausfuehren."
echo ""
ask "Netbird Management-URL (leer = ueberspringen):" NETBIRD_URL

if [ -n "${NETBIRD_URL:-}" ]; then
  ask "Netbird Setup-Key:" NETBIRD_SETUP_KEY
  if [ -n "${NETBIRD_SETUP_KEY:-}" ]; then
    netbird up --management-url "$NETBIRD_URL" --setup-key "$NETBIRD_SETUP_KEY"
    ok "Netbird verbunden"
    sleep 2
    NETBIRD_IP=$(netbird status --json 2>/dev/null | jq -r '.localPeerState.fqdn // empty' 2>/dev/null || true)
    if [ -z "$NETBIRD_IP" ]; then
      NETBIRD_IP=$(netbird status --json 2>/dev/null | jq -r '.localPeerState.ip // empty' 2>/dev/null || true)
    fi
    if [ -n "$NETBIRD_IP" ]; then
      # Strip /32 CIDR suffix if present
      NETBIRD_IP="${NETBIRD_IP%/32}"
      ok "Netbird-IP: $NETBIRD_IP"
    else
      warn "Netbird-IP konnte nicht automatisch ermittelt werden."
      ask "Netbird-IP manuell eingeben (100.x.x.x):" NETBIRD_IP
    fi
  fi
else
  warn "Netbird-Join uebersprungen. Spaeter manuell: netbird up --management-url URL --setup-key KEY"
  NETBIRD_IP=""
  NETBIRD_URL=""
fi

# =====================================================
# Phase 3: Repo klonen
# =====================================================
info "Phase 3: LocoCloud-Repo klonen"

if [ -d "$REPO_DIR/.git" ]; then
  ok "Repo existiert bereits in $REPO_DIR"
else
  git clone https://github.com/Ollornog/LocoCloud.git "$REPO_DIR"
  ok "Repo geklont nach $REPO_DIR"
fi

cd "$REPO_DIR"

# =====================================================
# Phase 4: Ansible installieren
# =====================================================
info "Phase 4: Ansible installieren"

if command -v ansible &>/dev/null; then
  ok "Ansible ist bereits installiert: $(ansible --version | head -1)"
else
  pipx install ansible-core
  pipx ensurepath

  # PATH fuer diese Session aktualisieren
  export PATH="$PATH:/root/.local/bin"

  if command -v ansible &>/dev/null; then
    ok "Ansible installiert: $(ansible --version | head -1)"
  else
    error "Ansible Installation fehlgeschlagen. Bitte manuell pruefen."
  fi
fi

# =====================================================
# Phase 5: Ansible Collections
# =====================================================
info "Phase 5: Ansible Collections installieren"

ansible-galaxy collection install -r "$REPO_DIR/requirements.yml"
ok "Collections installiert"

# =====================================================
# Phase 6: Interaktive Konfiguration
# =====================================================
info "Phase 6: Konfiguration"
echo ""
echo "Jetzt werden die wichtigsten Einstellungen abgefragt."
echo "Subdomains werden automatisch aus der Basis-Domain generiert."
echo ""

ask "Dein Name:" OPERATOR_NAME
ask "Admin-E-Mail:" OPERATOR_EMAIL
ask "Basis-Domain (z.B. example.com):" BASE_DOMAIN
ask "Admin-Subdomain [admin]:" ADMIN_SUB
ADMIN_SUB="${ADMIN_SUB:-admin}"
ADMIN_DOMAIN="${ADMIN_SUB}.${BASE_DOMAIN}"

echo ""
info "Generierte Admin-URLs:"
echo "  PocketID:    id.${ADMIN_DOMAIN}"
echo "  Tinyauth:    auth.${ADMIN_DOMAIN}"
echo "  Vaultwarden: vault.${ADMIN_DOMAIN}"
echo "  Semaphore:   deploy.${ADMIN_DOMAIN}"
echo "  Zabbix:      monitor.${ADMIN_DOMAIN}"
echo ""

# SMTP (optional)
ask "SMTP Host (leer = spaeter konfigurieren):" SMTP_HOST
SMTP_PORT=""
SMTP_USER=""
SMTP_FROM=""
if [ -n "${SMTP_HOST:-}" ]; then
  ask "SMTP Port [587]:" SMTP_PORT
  SMTP_PORT="${SMTP_PORT:-587}"
  ask "SMTP User:" SMTP_USER
  ask "SMTP From-Adresse [noreply@${BASE_DOMAIN}]:" SMTP_FROM
  SMTP_FROM="${SMTP_FROM:-noreply@${BASE_DOMAIN}}"
fi

# Gateway
ask "Public IP des Gateway-Servers (leer = spaeter):" GATEWAY_IP

# Netbird Server self-hosted?
echo ""
ask "Eigenen Netbird-Server mit einrichten? (j/n) [n]:" NETBIRD_SELF_HOSTED
NETBIRD_SELF_HOSTED="${NETBIRD_SELF_HOSTED:-n}"
NETBIRD_DOMAIN=""
NETBIRD_RELAY_DOMAIN=""
if [[ "$NETBIRD_SELF_HOSTED" =~ ^[jJyY]$ ]]; then
  ask "Netbird-Domain (z.B. netbird.${BASE_DOMAIN}):" NETBIRD_DOMAIN
  NETBIRD_DOMAIN="${NETBIRD_DOMAIN:-netbird.${BASE_DOMAIN}}"
  ask "Netbird-Relay-Domain (z.B. relay.${BASE_DOMAIN}):" NETBIRD_RELAY_DOMAIN
  NETBIRD_RELAY_DOMAIN="${NETBIRD_RELAY_DOMAIN:-relay.${BASE_DOMAIN}}"
  # If no management URL was set earlier, set it now
  NETBIRD_URL="${NETBIRD_URL:-https://${NETBIRD_DOMAIN}}"
fi

# =====================================================
# Phase 7: Config-Datei generieren
# =====================================================
info "Phase 7: config/lococloudd.yml generieren"

CONFIG_FILE="$REPO_DIR/config/lococloudd.yml"

if [ -f "$CONFIG_FILE" ]; then
  warn "Config existiert bereits: $CONFIG_FILE"
  ask "Ueberschreiben? (j/n) [n]:" OVERWRITE
  if [[ ! "$OVERWRITE" =~ ^[jJyY]$ ]]; then
    info "Config wird nicht ueberschrieben."
  else
    WRITE_CONFIG=true
  fi
else
  WRITE_CONFIG=true
fi

if [ "${WRITE_CONFIG:-}" = "true" ] || [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" <<YAML
# config/lococloudd.yml
# Generiert durch scripts/setup.sh
# Diese Datei ist in .gitignore und wird NICHT committet!

# --- Betreiber ---
operator:
  name: "${OPERATOR_NAME}"
  email: "${OPERATOR_EMAIL}"
  domain: "${BASE_DOMAIN}"

# --- Admin-Subdomain ---
admin:
  subdomain: "${ADMIN_SUB}"
  full_domain: "${ADMIN_DOMAIN}"

# --- Admin-Dienste URLs ---
urls:
  pocketid: "id.${ADMIN_DOMAIN}"
  tinyauth: "auth.${ADMIN_DOMAIN}"
  vaultwarden: "vault.${ADMIN_DOMAIN}"
  semaphore: "deploy.${ADMIN_DOMAIN}"
  zabbix: "monitor.${ADMIN_DOMAIN}"

# --- Netbird ---
netbird:
  manager_url: "${NETBIRD_URL:-}"
  api_token: ""

# --- PocketID (Admin-Instanz) ---
# Token wird nach dem ersten Setup-Lauf hier eingetragen.
pocketid:
  api_token: ""

# --- SMTP ---
smtp:
  host: "${SMTP_HOST:-}"
  port: ${SMTP_PORT:-587}
  starttls: true
  user: "${SMTP_USER:-}"
  from: "${SMTP_FROM:-noreply@${BASE_DOMAIN}}"

# --- GitHub Repo ---
repo:
  url: "https://github.com/Ollornog/LocoCloud.git"
  branch: "main"

# --- Vaultwarden (Admin-Instanz) ---
vaultwarden:
  url: "https://vault.${ADMIN_DOMAIN}"
  api_token_path: "/root/.loco-vaultwarden-token"
  organization_id: ""

# --- Bitwarden CLI ---
bitwarden_cli:
  server_url: "https://vault.${ADMIN_DOMAIN}"
  vault_item_name: "lococloudd-ansible-vault"

# --- Gateway ---
admin_gateway:
  public_ip: "${GATEWAY_IP:-}"
YAML

  # Append netbird_server section if self-hosted
  if [[ "${NETBIRD_SELF_HOSTED:-n}" =~ ^[jJyY]$ ]]; then
    cat >> "$CONFIG_FILE" <<YAML

# --- Netbird Server (Self-Hosted) ---
netbird_server:
  self_hosted: true
  domain: "${NETBIRD_DOMAIN}"
  relay_domain: "${NETBIRD_RELAY_DOMAIN}"
YAML
  fi

  chmod 600 "$CONFIG_FILE"
  ok "Config geschrieben: $CONFIG_FILE"
fi

# =====================================================
# Phase 8: Master-Inventar vorbereiten
# =====================================================
info "Phase 8: Master-Inventar vorbereiten"

HOSTS_FILE="$REPO_DIR/inventories/master/hosts.yml"
GROUPVARS_FILE="$REPO_DIR/inventories/master/group_vars/all.yml"

if [ -n "${NETBIRD_IP:-}" ]; then
  cat > "$HOSTS_FILE" <<YAML
---
all:
  hosts:
    loco-master:
      ansible_host: "${NETBIRD_IP}"
      ansible_user: root
      server_roles: [master]
      is_lxc: true
YAML
  ok "hosts.yml geschrieben mit Netbird-IP ${NETBIRD_IP}"
else
  warn "Keine Netbird-IP bekannt. hosts.yml muss manuell bearbeitet werden."
  warn "  Datei: $HOSTS_FILE"
  warn "  Feld:  ansible_host: <NETBIRD-IP>"
fi

# =====================================================
# Zusammenfassung
# =====================================================
echo ""
echo "==========================================="
echo -e "${GREEN} LocoCloud Setup abgeschlossen!${NC}"
echo "==========================================="
echo ""
echo "Repo:   $REPO_DIR"
echo "Config: $REPO_DIR/config/lococloudd.yml"
echo ""
echo "Admin-URLs (nach Playbook-Lauf):"
echo "  PocketID:    https://id.${ADMIN_DOMAIN}"
echo "  Tinyauth:    https://auth.${ADMIN_DOMAIN}"
echo "  Vaultwarden: https://vault.${ADMIN_DOMAIN}"
echo "  Semaphore:   https://deploy.${ADMIN_DOMAIN}"
echo ""

if [ -n "${NETBIRD_IP:-}" ]; then
  echo "Netbird-IP:    ${NETBIRD_IP}"
fi

echo ""
echo "Naechste Schritte:"
echo ""

STEP=1
if [ -z "${NETBIRD_IP:-}" ]; then
  echo "  ${STEP}. Netbird joinen:"
  echo "     netbird up --management-url <URL> --setup-key <KEY>"
  echo "     Dann: inventories/master/hosts.yml bearbeiten (ansible_host setzen)"
  STEP=$((STEP + 1))
fi

echo "  ${STEP}. DNS einrichten:"
echo "     *.${ADMIN_DOMAIN} -> A-Record auf Gateway Public IP"
STEP=$((STEP + 1))

echo "  ${STEP}. SSH-Keys in inventories/master/group_vars/all.yml eintragen"
STEP=$((STEP + 1))

echo "  ${STEP}. Master-Playbook ausfuehren:"
echo "     cd $REPO_DIR"
echo "     ansible-playbook playbooks/setup-master.yml -i inventories/master/"
STEP=$((STEP + 1))

echo "  ${STEP}. PocketID API-Token eintragen (nach erstem Lauf):"
echo "     -> https://id.${ADMIN_DOMAIN} -> Settings -> API"
echo "     -> Token in config/lococloudd.yml bei pocketid.api_token eintragen"
STEP=$((STEP + 1))

echo "  ${STEP}. Vaultwarden einrichten + Playbook erneut ausfuehren"
echo ""
