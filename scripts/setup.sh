#!/bin/bash
# scripts/setup.sh
# LocoCloud — Kompletter Setup vom blanken Debian-Server.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Ollornog/LocoCloud/main/scripts/setup.sh -o setup.sh
#   bash setup.sh
#
# Oder wenn das Repo bereits geklont ist:
#   bash scripts/setup.sh
#
# WICHTIG: Nicht mit "curl | bash" ausfuehren — das Script braucht
# interaktive Eingaben und muss vom Terminal lesen koennen.

set -eo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Read from /dev/tty so it works even if script is piped
# Usage: ask "Prompt text:" VARNAME
ask() {
  local prompt="$1"
  local varname="$2"
  echo -en "${CYAN}${prompt}${NC} " >/dev/tty
  IFS= read -r "$varname" </dev/tty || true
}

# Ask with a default value — shows [default] and uses it if input is empty
# Usage: ask_default "Prompt text" VARNAME "default"
ask_default() {
  local prompt="$1"
  local varname="$2"
  local default="$3"
  echo -en "${CYAN}${prompt}${NC} [${default}] " >/dev/tty
  local input=""
  IFS= read -r input </dev/tty || true
  if [ -z "$input" ]; then
    eval "$varname=\"$default\""
  else
    eval "$varname=\"$input\""
  fi
}

# Pre-init all variables to avoid unbound errors
NETBIRD_URL=""
NETBIRD_SETUP_KEY=""
NETBIRD_IP=""
NETBIRD_SELF_HOSTED="n"
NETBIRD_DOMAIN=""
NETBIRD_RELAY_DOMAIN=""
OPERATOR_NAME=""
OPERATOR_EMAIL=""
BASE_DOMAIN=""
ADMIN_SUB="admin"
ADMIN_DOMAIN=""
SMTP_HOST=""
SMTP_PORT="587"
SMTP_USER=""
SMTP_FROM=""
GATEWAY_IP=""
WRITE_CONFIG=""

REPO_DIR="/root/LocoCloud"

# =====================================================
echo ""
echo -e "${BOLD}==========================================${NC}"
echo -e "${BOLD}  LocoCloud Setup${NC}"
echo -e "${BOLD}==========================================${NC}"
echo ""

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
echo "Falls noch kein Netbird-Server existiert, kannst du diesen Schritt"
echo "ueberspringen und spaeter 'netbird up' manuell ausfuehren."
echo ""
ask "Netbird Management-URL (leer = ueberspringen):" NETBIRD_URL

# https:// Fallback — wenn jemand nur die Domain eingibt
if [ -n "$NETBIRD_URL" ] && [[ ! "$NETBIRD_URL" =~ ^https?:// ]]; then
  NETBIRD_URL="https://${NETBIRD_URL}"
  info "URL korrigiert: $NETBIRD_URL"
fi

if [ -n "$NETBIRD_URL" ]; then
  ask "Netbird Setup-Key:" NETBIRD_SETUP_KEY
  if [ -n "$NETBIRD_SETUP_KEY" ]; then
    netbird up --management-url "$NETBIRD_URL" --setup-key "$NETBIRD_SETUP_KEY"
    ok "Netbird verbunden"
    sleep 2
    # Try to get IP automatically
    NETBIRD_IP=$(netbird status --json 2>/dev/null | jq -r '.localPeerState.ip // empty' 2>/dev/null || true)
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
  warn "Netbird-Join uebersprungen."
  echo "  Spaeter manuell: netbird up --management-url URL --setup-key KEY"
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

# PATH fuer diese Session sicherstellen (falls pipx schon installiert hat)
export PATH="$PATH:/root/.local/bin"

if command -v ansible &>/dev/null; then
  ok "Ansible ist bereits installiert: $(ansible --version | head -1)"
else
  pipx install ansible-core
  pipx ensurepath

  # PATH nochmal aktualisieren
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
echo ""
echo -e "${BOLD}==========================================${NC}"
echo -e "${BOLD}  Konfiguration${NC}"
echo -e "${BOLD}==========================================${NC}"
echo ""
echo "Subdomains werden automatisch aus der Basis-Domain generiert."
echo ""

ask "Dein Name:" OPERATOR_NAME
[ -z "$OPERATOR_NAME" ] && error "Name darf nicht leer sein."

ask "Admin-E-Mail:" OPERATOR_EMAIL
[ -z "$OPERATOR_EMAIL" ] && error "E-Mail darf nicht leer sein."

ask "Basis-Domain (z.B. example.com):" BASE_DOMAIN
[ -z "$BASE_DOMAIN" ] && error "Domain darf nicht leer sein."

ask_default "Admin-Subdomain" ADMIN_SUB "admin"
ADMIN_DOMAIN="${ADMIN_SUB}.${BASE_DOMAIN}"

echo ""
info "Generierte Admin-URLs:"
echo "  PocketID:    https://id.${ADMIN_DOMAIN}"
echo "  Tinyauth:    https://auth.${ADMIN_DOMAIN}"
echo "  Vaultwarden: https://vault.${ADMIN_DOMAIN}"
echo "  Semaphore:   https://deploy.${ADMIN_DOMAIN}"
echo "  Zabbix:      https://monitor.${ADMIN_DOMAIN}"
echo ""

# SMTP (optional)
ask "SMTP Host (leer = spaeter konfigurieren):" SMTP_HOST
if [ -n "$SMTP_HOST" ]; then
  ask_default "SMTP Port" SMTP_PORT "587"
  ask "SMTP User:" SMTP_USER
  ask_default "SMTP From-Adresse" SMTP_FROM "noreply@${BASE_DOMAIN}"
fi

# Gateway
echo ""
ask "Public IP des Gateway-Servers (leer = spaeter):" GATEWAY_IP

# Netbird Server self-hosted?
echo ""
ask_default "Eigenen Netbird-Server mit einrichten? (j/n)" NETBIRD_SELF_HOSTED "n"
if [[ "$NETBIRD_SELF_HOSTED" =~ ^[jJyY]$ ]]; then
  ask_default "Netbird-Domain" NETBIRD_DOMAIN "netbird.${BASE_DOMAIN}"
  ask_default "Netbird-Relay-Domain" NETBIRD_RELAY_DOMAIN "relay.${BASE_DOMAIN}"
  # If no management URL was set earlier, set it now
  if [ -z "$NETBIRD_URL" ]; then
    NETBIRD_URL="https://${NETBIRD_DOMAIN}"
  fi
fi

# =====================================================
# Phase 7: Config-Datei generieren
# =====================================================
info "Phase 7: config/lococloudd.yml generieren"

CONFIG_FILE="$REPO_DIR/config/lococloudd.yml"

WRITE_CONFIG="true"
if [ -f "$CONFIG_FILE" ]; then
  warn "Config existiert bereits: $CONFIG_FILE"
  ask_default "Ueberschreiben? (j/n)" OVERWRITE "n"
  if [[ ! "$OVERWRITE" =~ ^[jJyY]$ ]]; then
    info "Config wird nicht ueberschrieben."
    WRITE_CONFIG=""
  fi
fi

if [ "$WRITE_CONFIG" = "true" ]; then
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
  manager_url: "${NETBIRD_URL}"
  api_token: ""

# --- PocketID (Admin-Instanz) ---
# Token wird nach dem ersten Setup-Lauf hier eingetragen.
pocketid:
  api_token: ""

# --- SMTP ---
smtp:
  host: "${SMTP_HOST}"
  port: ${SMTP_PORT}
  starttls: true
  user: "${SMTP_USER}"
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
  public_ip: "${GATEWAY_IP}"
YAML

  # Append netbird_server section if self-hosted
  if [[ "$NETBIRD_SELF_HOSTED" =~ ^[jJyY]$ ]]; then
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

if [ -n "$NETBIRD_IP" ]; then
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
echo -e "${BOLD}==========================================${NC}"
echo -e "${GREEN}${BOLD}  LocoCloud Setup abgeschlossen!${NC}"
echo -e "${BOLD}==========================================${NC}"
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

if [ -n "$NETBIRD_IP" ]; then
  echo "Netbird-IP:    ${NETBIRD_IP}"
  echo ""
fi

echo -e "${BOLD}Naechste Schritte:${NC}"
echo ""

STEP=1
if [ -z "$NETBIRD_IP" ]; then
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
