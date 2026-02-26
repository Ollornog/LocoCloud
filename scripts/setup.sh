#!/bin/bash
# scripts/setup.sh
# LocoCloud — Kompletter Setup vom blanken Debian-Server.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Ollornog/LocoCloud/main/scripts/setup.sh -o setup.sh
#   bash setup.sh
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
ask() {
  local prompt="$1"
  local varname="$2"
  echo -en "${CYAN}${prompt}${NC} " >/dev/tty
  IFS= read -r "$varname" </dev/tty || true
}

# Ask with default value — shows [default], uses it on empty input
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

# Pre-init all variables
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
POCKETID_API_TOKEN=""
WRITE_CONFIG=""

REPO_DIR="/root/LocoCloud"
NETBIRD_STACK="/opt/stacks/netbird"

# =====================================================
echo ""
echo -e "${BOLD}==========================================${NC}"
echo -e "${BOLD}  LocoCloud Setup${NC}"
echo -e "${BOLD}==========================================${NC}"
echo ""

# =====================================================
# Phase 1: Alle Fragen zuerst stellen
# =====================================================
info "Phase 1: Konfiguration abfragen"
echo ""
echo "Zuerst werden alle Einstellungen abgefragt."
echo "Danach laeuft alles automatisch durch."
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
echo "  Grafana:     https://grafana.${ADMIN_DOMAIN}"
echo "  Baserow:     https://baserow.${ADMIN_DOMAIN}"
echo ""

# SMTP
ask "SMTP Host (leer = spaeter):" SMTP_HOST
if [ -n "$SMTP_HOST" ]; then
  ask_default "SMTP Port" SMTP_PORT "587"
  ask "SMTP User:" SMTP_USER
  ask_default "SMTP From-Adresse" SMTP_FROM "noreply@${BASE_DOMAIN}"
fi

# Gateway
echo ""
ask "Public IP des Gateway-Servers (leer = spaeter):" GATEWAY_IP

# --- Netbird (optional) ---
echo ""
echo -e "${BOLD}--- Netbird VPN (optional) ---${NC}"
echo ""
echo "Netbird ist OPTIONAL. Server koennen auch direkt per IP erreichbar sein."
echo "Netbird bietet ein VPN-Mesh fuer Admin-Zugriff zwischen Servern."
echo ""
NETBIRD_ENABLED="n"
ask_default "Netbird aktivieren? (j/n)" NETBIRD_ENABLED "n"

if [[ "$NETBIRD_ENABLED" =~ ^[jJyY]$ ]]; then
  echo ""
  echo "Du kannst einen eigenen Netbird-Server auf diesem Host einrichten"
  echo "oder einen bestehenden verwenden."
  echo ""
  ask_default "Eigenen Netbird-Server einrichten? (j/n)" NETBIRD_SELF_HOSTED "n"
else
  info "Netbird wird uebersprungen."
fi

if [[ "$NETBIRD_ENABLED" =~ ^[jJyY]$ ]]; then
  if [[ "$NETBIRD_SELF_HOSTED" =~ ^[jJyY]$ ]]; then
    ask_default "Netbird-Domain" NETBIRD_DOMAIN "netbird.${BASE_DOMAIN}"
    ask_default "Netbird-Relay-Domain" NETBIRD_RELAY_DOMAIN "relay.${BASE_DOMAIN}"
    NETBIRD_URL="https://${NETBIRD_DOMAIN}"
    echo ""
    info "Netbird-Server wird auf diesem Host eingerichtet."
    info "Management-URL: ${NETBIRD_URL}"
    echo ""
    echo "Nach dem Server-Start musst du im Netbird-Dashboard einen Setup-Key"
    echo "erstellen. Das Script fragt spaeter danach."
  else
    echo ""
    ask "Netbird Management-URL (leer = spaeter):" NETBIRD_URL
    # https:// Fallback
    if [ -n "$NETBIRD_URL" ] && [[ ! "$NETBIRD_URL" =~ ^https?:// ]]; then
      NETBIRD_URL="https://${NETBIRD_URL}"
      info "URL korrigiert: $NETBIRD_URL"
    fi
    if [ -n "$NETBIRD_URL" ]; then
      ask "Netbird Setup-Key:" NETBIRD_SETUP_KEY
    fi
  fi
fi

echo ""
echo -e "${BOLD}==========================================${NC}"
echo -e "${BOLD}  Konfiguration abgeschlossen${NC}"
echo -e "${BOLD}==========================================${NC}"
echo ""
info "Jetzt wird automatisch installiert. Das dauert ein paar Minuten."
echo ""

# =====================================================
# Phase 2: System aktualisieren + Grundpakete
# =====================================================
info "Phase 2: System aktualisieren und Grundpakete installieren"

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
# Phase 3: Docker installieren (immer — wird spaeter auch von Ansible benoetigt)
# =====================================================
info "Phase 3: Docker installieren"

if command -v docker &>/dev/null; then
  ok "Docker ist bereits installiert: $(docker --version)"
else
  curl -fsSL https://get.docker.com | sh
  ok "Docker installiert: $(docker --version)"
fi

# =====================================================
# Phase 4: Netbird-Server einrichten (falls self-hosted)
# =====================================================
if [[ "$NETBIRD_ENABLED" =~ ^[jJyY]$ ]] && [[ "$NETBIRD_SELF_HOSTED" =~ ^[jJyY]$ ]]; then
  info "Phase 4: Netbird-Server einrichten"

  mkdir -p "${NETBIRD_STACK}"

  cat > "${NETBIRD_STACK}/docker-compose.yml" <<COMPOSE
services:
  management:
    image: netbirdio/management:latest
    container_name: netbird-management
    restart: unless-stopped
    ports:
      - "443:443"
      - "33073:33073"
    volumes:
      - ${NETBIRD_STACK}/config:/etc/netbird
      - ${NETBIRD_STACK}/management:/var/lib/netbird
    command: ["--port", "443", "--log-level", "info"]

  signal:
    image: netbirdio/signal:latest
    container_name: netbird-signal
    restart: unless-stopped
    ports:
      - "10000:80"

  relay:
    image: netbirdio/relay:latest
    container_name: netbird-relay
    restart: unless-stopped
    ports:
      - "33080:33080"
    environment:
      - NB_LOG_LEVEL=info
      - NB_LISTEN_ADDRESS=:33080
      - NB_EXPOSED_ADDRESS=rels://${NETBIRD_RELAY_DOMAIN}:443

  dashboard:
    image: netbirdio/dashboard:latest
    container_name: netbird-dashboard
    restart: unless-stopped
    ports:
      - "8080:80"
    environment:
      - NETBIRD_MGMT_API_ENDPOINT=https://${NETBIRD_DOMAIN}
      - NETBIRD_MGMT_GRPC_API_ENDPOINT=https://${NETBIRD_DOMAIN}
COMPOSE

  # Start the stack
  docker compose -f "${NETBIRD_STACK}/docker-compose.yml" up -d
  ok "Netbird-Server gestartet"

  echo ""
  warn "Netbird-Server laeuft. Naechste Schritte:"
  echo "  1. DNS: ${NETBIRD_DOMAIN} -> A-Record auf diesen Server"
  echo "  2. Caddy/Reverse-Proxy fuer TLS einrichten"
  echo "  3. Im Dashboard einen Setup-Key erstellen"
  echo ""
  echo "Dashboard: http://$(hostname -I | awk '{print $1}'):8080"
  echo ""
  ask "Setup-Key eingeben (wenn Dashboard schon erreichbar, sonst leer = spaeter):" NETBIRD_SETUP_KEY
else
  info "Phase 4: Netbird-Server wird uebersprungen (extern oder deaktiviert)"
fi

# =====================================================
# Phase 5: Netbird-Client installieren + joinen (nur wenn aktiviert)
# =====================================================
if [[ "$NETBIRD_ENABLED" =~ ^[jJyY]$ ]]; then
  info "Phase 5: Netbird-Client installieren"

  if command -v netbird &>/dev/null; then
    ok "Netbird ist bereits installiert"
  else
    curl -fsSL https://pkgs.netbird.io/install.sh | sh
    ok "Netbird installiert"
  fi
else
  info "Phase 5: Netbird uebersprungen (deaktiviert)"
fi

if [[ "$NETBIRD_ENABLED" =~ ^[jJyY]$ ]] && [ -n "$NETBIRD_URL" ] && [ -n "$NETBIRD_SETUP_KEY" ]; then
  netbird up --management-url "$NETBIRD_URL" --setup-key "$NETBIRD_SETUP_KEY"
  ok "Netbird verbunden"
  sleep 3
  # Try to get IP automatically — Netbird uses uppercase "IP" in JSON
  NB_JSON=$(netbird status --json 2>/dev/null || true)
  if [ -n "$NB_JSON" ]; then
    NETBIRD_IP=$(echo "$NB_JSON" | jq -r '.localPeerState.IP // .localPeerState.ip // empty' 2>/dev/null || true)
  fi
  # Strip CIDR suffix (/16 or /32)
  NETBIRD_IP="${NETBIRD_IP%/*}"
  # Fallback: read IP from wt0 interface
  if [ -z "$NETBIRD_IP" ]; then
    NETBIRD_IP=$(ip -4 addr show wt0 2>/dev/null | grep -oP 'inet \K[0-9.]+' || true)
  fi
  if [ -n "$NETBIRD_IP" ]; then
    ok "Netbird-IP: $NETBIRD_IP"
  else
    warn "Netbird-IP konnte nicht automatisch ermittelt werden."
    ask "Netbird-IP manuell eingeben (100.x.x.x):" NETBIRD_IP
  fi
elif [[ "$NETBIRD_ENABLED" =~ ^[jJyY]$ ]] && [ -n "$NETBIRD_URL" ]; then
  warn "Kein Setup-Key angegeben. Netbird-Join spaeter manuell:"
  echo "  netbird up --management-url $NETBIRD_URL --setup-key <KEY>"
elif [[ "$NETBIRD_ENABLED" =~ ^[jJyY]$ ]]; then
  warn "Netbird-Join uebersprungen."
  echo "  Spaeter: netbird up --management-url <URL> --setup-key <KEY>"
fi

# =====================================================
# Phase 6: Repo klonen
# =====================================================
info "Phase 6: LocoCloud-Repo klonen"

if [ -d "$REPO_DIR/.git" ]; then
  ok "Repo existiert bereits in $REPO_DIR"
else
  git clone https://github.com/Ollornog/LocoCloud.git "$REPO_DIR"
  ok "Repo geklont nach $REPO_DIR"
fi

cd "$REPO_DIR"

# =====================================================
# Phase 7: Ansible installieren
# =====================================================
info "Phase 7: Ansible installieren"

export PATH="$PATH:/root/.local/bin"

# Persist PATH for future shells (ansible-playbook, ansible-galaxy etc.)
if ! grep -q '/root/.local/bin' /root/.bashrc 2>/dev/null; then
  echo 'export PATH="$PATH:/root/.local/bin"' >> /root/.bashrc
fi

if command -v ansible &>/dev/null; then
  ok "Ansible ist bereits installiert: $(ansible --version | head -1)"
else
  pipx install ansible-core
  export PATH="$PATH:/root/.local/bin"

  if command -v ansible &>/dev/null; then
    ok "Ansible installiert: $(ansible --version | head -1)"
  else
    error "Ansible Installation fehlgeschlagen."
  fi
fi

# =====================================================
# Phase 8: Ansible Collections
# =====================================================
info "Phase 8: Ansible Collections installieren"

ansible-galaxy collection install -r "$REPO_DIR/requirements.yml"
ok "Collections installiert"

# =====================================================
# Phase 9: Config-Datei generieren
# =====================================================
info "Phase 9: config/lococloudd.yml generieren"

# Generate PocketID API token (STATIC_API_KEY)
POCKETID_API_TOKEN=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48 || true)
ok "PocketID API-Token generiert (STATIC_API_KEY)"

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
  grafana: "grafana.${ADMIN_DOMAIN}"
  baserow: "baserow.${ADMIN_DOMAIN}"

# --- Netbird (optional) ---
netbird:
  enabled: $(if [[ "$NETBIRD_ENABLED" =~ ^[jJyY]$ ]]; then echo "true"; else echo "false"; fi)
  manager_url: "${NETBIRD_URL}"
  api_token: ""

# --- PocketID (Admin-Instanz) ---
# STATIC_API_KEY — automatisch generiert, kein manueller Schritt noetig.
# PocketID nutzt Passkeys (WebAuthn), keine Passwoerter.
pocketid:
  api_token: "${POCKETID_API_TOKEN}"

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

# --- gocryptfs ---
gocryptfs:
  key_store_path: "/opt/lococloudd/keys"

# --- Key Backup ---
key_backup:
  host: ""
  sync_interval: "0 */6 * * *"

# --- Grafana Stack ---
grafana:
  admin_password: ""
  prometheus_retention: "30d"
  loki_retention: "4320h"
  prometheus_remote_write_url: ""
  loki_push_url: ""
  alerting:
    enabled: true
    email_to: "${OPERATOR_EMAIL}"

# --- Baserow ---
baserow:
  admin_email: "${OPERATOR_EMAIL}"

# --- Compliance ---
compliance:
  docs_output_path: "/opt/lococloudd/compliance-docs"
YAML

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
# Phase 10: SSH-Key generieren
# =====================================================
info "Phase 10: SSH-Key fuer Ansible generieren"

SSH_KEY="/root/.ssh/id_ed25519"
if [ -f "$SSH_KEY" ]; then
  ok "SSH-Key existiert bereits: $SSH_KEY"
else
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "loco-master@$(hostname)" >/dev/null 2>&1
  ok "SSH-Key generiert: $SSH_KEY"
fi
SSH_PUBKEY=$(cat "${SSH_KEY}.pub")

# Write SSH key to group_vars
GROUP_VARS="$REPO_DIR/inventories/master/group_vars/all.yml"
cat > "$GROUP_VARS" <<YAML
---
# inventories/master/group_vars/all.yml
# Master-Server configuration

admin_user: "srvadmin"
admin_ssh_pubkeys:
  - "${SSH_PUBKEY}"

is_lxc: true
docker_install: true
server_roles: [master]
YAML
ok "SSH-Key in group_vars/all.yml eingetragen"

# =====================================================
# Phase 11: Master-Inventar vorbereiten
# =====================================================
info "Phase 11: Master-Inventar vorbereiten"

HOSTS_FILE="$REPO_DIR/inventories/master/hosts.yml"

# Use ansible_connection: local for initial setup (no SSH needed)
cat > "$HOSTS_FILE" <<YAML
---
all:
  hosts:
    loco-master:
      ansible_connection: local
      ansible_host: "${NETBIRD_IP:-127.0.0.1}"
      ansible_user: root
      ansible_python_interpreter: /usr/bin/python3
      server_roles: [master]
      is_lxc: true
YAML

if [ -n "$NETBIRD_IP" ]; then
  ok "hosts.yml geschrieben (Netbird-IP: ${NETBIRD_IP}, connection: local)"
else
  ok "hosts.yml geschrieben (connection: local, Netbird-IP spaeter setzen)"
fi

# =====================================================
# Phase 12: Master-Playbook ausfuehren
# =====================================================
info "Phase 12: Master-Playbook ausfuehren"
echo ""
echo "Das Playbook richtet die Admin-Dienste ein:"
echo "  base → pocketid → tinyauth → vaultwarden → semaphore → grafana → baserow → caddy"
echo ""

ansible-playbook "$REPO_DIR/playbooks/setup-master.yml" \
  -i "$REPO_DIR/inventories/master/" \
  2>&1 | tee /tmp/loco-setup-playbook.log

PLAYBOOK_EXIT=${PIPESTATUS[0]}

if [ "$PLAYBOOK_EXIT" -eq 0 ]; then
  ok "Master-Playbook erfolgreich abgeschlossen"
else
  warn "Playbook mit Fehlern beendet (Exit-Code: $PLAYBOOK_EXIT)"
  warn "Log: /tmp/loco-setup-playbook.log"
  warn "Nach Fehlerbehebung erneut ausfuehren:"
  echo "  ansible-playbook $REPO_DIR/playbooks/setup-master.yml -i $REPO_DIR/inventories/master/"
fi

# =====================================================
# Zusammenfassung
# =====================================================

PUBLIC_IP=$(curl -fsSL -4 https://ifconfig.me 2>/dev/null || curl -fsSL -4 https://api.ipify.org 2>/dev/null || echo "nicht ermittelt")

echo ""
echo -e "${BOLD}==========================================${NC}"
echo -e "${GREEN}${BOLD}  LocoCloud Setup abgeschlossen!${NC}"
echo -e "${BOLD}==========================================${NC}"
echo ""
echo -e "${BOLD}Server-Info:${NC}"
echo "  Oeffentliche IP: ${PUBLIC_IP}"
if [ -n "$NETBIRD_IP" ]; then
  echo "  Netbird-IP:      ${NETBIRD_IP}"
fi
echo "  Repo:            $REPO_DIR"
echo "  Config:          $REPO_DIR/config/lococloudd.yml"
echo "  SSH-Key:         ${SSH_KEY}"
echo ""

if [[ "$NETBIRD_ENABLED" =~ ^[jJyY]$ ]] && [[ "$NETBIRD_SELF_HOSTED" =~ ^[jJyY]$ ]]; then
  echo -e "${BOLD}Netbird-Server:${NC}"
  echo "  Stack:     ${NETBIRD_STACK}"
  echo "  Dashboard: http://${PUBLIC_IP}:8080"
  echo ""
fi

echo -e "${BOLD}Admin-URLs:${NC}"
echo "  PocketID:    https://id.${ADMIN_DOMAIN}"
echo "  Tinyauth:    https://auth.${ADMIN_DOMAIN}"
echo "  Vaultwarden: https://vault.${ADMIN_DOMAIN}"
echo "  Semaphore:   https://deploy.${ADMIN_DOMAIN}"
echo "  Grafana:     https://grafana.${ADMIN_DOMAIN}"
echo "  Baserow:     https://baserow.${ADMIN_DOMAIN}"

echo ""
echo ""
echo -e "${BOLD}==================== NAECHSTE SCHRITTE ====================${NC}"
echo ""

STEP=1

if [[ "$NETBIRD_ENABLED" =~ ^[jJyY]$ ]] && [[ "$NETBIRD_SELF_HOSTED" =~ ^[jJyY]$ ]]; then
  echo -e "${BOLD}  ${STEP}. DNS fuer Netbird-Server einrichten${NC}"
  echo ""
  echo "     ${NETBIRD_DOMAIN}       -> A ${PUBLIC_IP}"
  echo "     ${NETBIRD_RELAY_DOMAIN} -> A ${PUBLIC_IP}"
  echo ""
  STEP=$((STEP + 1))
fi

echo -e "${BOLD}  ${STEP}. DNS fuer Admin-Dienste einrichten${NC}"
echo ""
echo "     Wildcard-DNS auf die Gateway Public IP zeigen lassen:"
echo "     *.${ADMIN_DOMAIN} -> A ${GATEWAY_IP:-<GATEWAY-IP>}"
echo ""
MASTER_PROXY_IP="${NETBIRD_IP:-${PUBLIC_IP}}"
echo "     Auf dem Gateway-Server die Caddyfile ergaenzen:"
echo ""
echo "     *.${ADMIN_DOMAIN} {"
echo "         tls {"
echo "             dns cloudflare {env.CF_API_TOKEN}"
echo "         }"
echo "         reverse_proxy https://${MASTER_PROXY_IP:-<MASTER-IP>} {"
echo "             header_up Host {host}"
echo "             transport http {"
echo "                 tls_server_name ${ADMIN_DOMAIN}"
echo "                 versions 1.1"
echo "             }"
echo "         }"
echo "     }"
echo ""
STEP=$((STEP + 1))

if [[ "$NETBIRD_ENABLED" =~ ^[jJyY]$ ]] && [ -z "$NETBIRD_IP" ]; then
  echo -e "${BOLD}  ${STEP}. Netbird-Client verbinden${NC}"
  echo ""
  echo "     netbird up --management-url ${NETBIRD_URL:-<URL>} --setup-key <KEY>"
  echo ""
  echo "     Danach hosts.yml anpassen und Playbook erneut ausfuehren."
  echo ""
  STEP=$((STEP + 1))
fi

echo -e "${BOLD}  ${STEP}. PocketID: Admin-Passkey registrieren${NC}"
echo ""
echo "     a) https://id.${ADMIN_DOMAIN} im Browser oeffnen"
echo "     b) Admin-Account mit Passkey einrichten"
echo ""
echo "     Der API-Key wurde automatisch generiert (STATIC_API_KEY)."
echo "     Registration ist deaktiviert (ALLOW_USER_SIGNUPS=disabled)."
echo ""
STEP=$((STEP + 1))

echo -e "${BOLD}  ${STEP}. Vaultwarden: Master-Passwort setzen${NC}"
echo ""
echo "     a) https://vault.${ADMIN_DOMAIN} oeffnen"
echo "     b) 'Use single sign-on' klicken (Login via PocketID)"
echo "     c) Master-Passwort setzen (fuer Vault-Verschluesselung)"
echo "     d) Organisation 'LocoCloud' im Admin-Panel anlegen"
echo "     e) Organisation-ID in Config eintragen:"
echo "        nano $REPO_DIR/config/lococloudd.yml"
echo "        -> vaultwarden.organization_id: \"<ID>\""
echo ""
