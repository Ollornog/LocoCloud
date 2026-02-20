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
echo "  Zabbix:      https://monitor.${ADMIN_DOMAIN}"
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

# --- Netbird ---
echo ""
echo -e "${BOLD}--- Netbird VPN ---${NC}"
echo ""
echo "LocoCloud nutzt Netbird als VPN-Mesh fuer alle Server."
echo "Du kannst einen eigenen Netbird-Server auf diesem Host einrichten"
echo "oder einen bestehenden verwenden."
echo ""
ask_default "Eigenen Netbird-Server einrichten? (j/n)" NETBIRD_SELF_HOSTED "n"

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
if [[ "$NETBIRD_SELF_HOSTED" =~ ^[jJyY]$ ]]; then
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
  info "Phase 4: Netbird-Server wird uebersprungen (extern)"
fi

# =====================================================
# Phase 5: Netbird-Client installieren + joinen
# =====================================================
info "Phase 5: Netbird-Client installieren"

if command -v netbird &>/dev/null; then
  ok "Netbird ist bereits installiert"
else
  curl -fsSL https://pkgs.netbird.io/install.sh | sh
  ok "Netbird installiert"
fi

if [ -n "$NETBIRD_URL" ] && [ -n "$NETBIRD_SETUP_KEY" ]; then
  netbird up --management-url "$NETBIRD_URL" --setup-key "$NETBIRD_SETUP_KEY"
  ok "Netbird verbunden"
  sleep 2
  # Try to get IP automatically
  NETBIRD_IP=$(netbird status --json 2>/dev/null | jq -r '.localPeerState.ip // empty' 2>/dev/null || true)
  if [ -n "$NETBIRD_IP" ]; then
    NETBIRD_IP="${NETBIRD_IP%/32}"
    ok "Netbird-IP: $NETBIRD_IP"
  else
    warn "Netbird-IP konnte nicht automatisch ermittelt werden."
    ask "Netbird-IP manuell eingeben (100.x.x.x):" NETBIRD_IP
  fi
elif [ -n "$NETBIRD_URL" ]; then
  warn "Kein Setup-Key angegeben. Netbird-Join spaeter manuell:"
  echo "  netbird up --management-url $NETBIRD_URL --setup-key <KEY>"
else
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

if command -v ansible &>/dev/null; then
  ok "Ansible ist bereits installiert: $(ansible --version | head -1)"
else
  pipx install ansible-core
  pipx ensurepath
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
# Phase 10: Master-Inventar vorbereiten
# =====================================================
info "Phase 10: Master-Inventar vorbereiten"

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

# Oeffentliche IP ermitteln
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
echo ""

if [[ "$NETBIRD_SELF_HOSTED" =~ ^[jJyY]$ ]]; then
  echo -e "${BOLD}Netbird-Server:${NC}"
  echo "  Stack:     ${NETBIRD_STACK}"
  echo "  Dashboard: http://${PUBLIC_IP}:8080"
  echo ""
fi

echo -e "${BOLD}Admin-URLs (nach Playbook-Lauf):${NC}"
echo "  PocketID:    https://id.${ADMIN_DOMAIN}"
echo "  Tinyauth:    https://auth.${ADMIN_DOMAIN}"
echo "  Vaultwarden: https://vault.${ADMIN_DOMAIN}"
echo "  Semaphore:   https://deploy.${ADMIN_DOMAIN}"

echo ""
echo ""
echo -e "${BOLD}==================== NAECHSTE SCHRITTE ====================${NC}"
echo ""

STEP=1

if [[ "$NETBIRD_SELF_HOSTED" =~ ^[jJyY]$ ]]; then
  echo -e "${BOLD}  ${STEP}. DNS fuer Netbird-Server einrichten${NC}"
  echo ""
  echo "     ${NETBIRD_DOMAIN}       -> A ${PUBLIC_IP}"
  echo "     ${NETBIRD_RELAY_DOMAIN} -> A ${PUBLIC_IP}"
  echo ""
  STEP=$((STEP + 1))
fi

if [ -z "$NETBIRD_IP" ]; then
  echo -e "${BOLD}  ${STEP}. Netbird-Client mit dem Server verbinden${NC}"
  echo ""
  echo "     netbird up --management-url ${NETBIRD_URL:-<URL>} --setup-key <KEY>"
  echo ""
  echo "     Danach die Netbird-IP in das Inventar eintragen:"
  echo "     nano $REPO_DIR/inventories/master/hosts.yml"
  echo "     -> ansible_host: <NETBIRD-IP>"
  echo ""
  STEP=$((STEP + 1))
fi

echo -e "${BOLD}  ${STEP}. DNS fuer Admin-Dienste einrichten${NC}"
echo ""
echo "     *.${ADMIN_DOMAIN} -> A ${GATEWAY_IP:-<GATEWAY-IP>}"
echo ""
echo "     Dieser Wildcard-Eintrag deckt alle Admin-Subdomains ab"
echo "     (id, auth, vault, deploy, monitor)."
echo ""
STEP=$((STEP + 1))

echo -e "${BOLD}  ${STEP}. SSH-Public-Key eintragen${NC}"
echo ""
echo "     Damit Ansible sich per SSH verbinden kann, muss mindestens"
echo "     ein Public Key hinterlegt werden. Deinen Key findest du auf"
echo "     deinem Admin-Rechner unter ~/.ssh/id_ed25519.pub (oder .pub)."
echo ""
echo "     nano $REPO_DIR/inventories/master/group_vars/all.yml"
echo ""
echo "     admin_ssh_pubkeys:"
echo "       - \"ssh-ed25519 AAAA... dein-name@rechner\""
echo ""
STEP=$((STEP + 1))

echo -e "${BOLD}  ${STEP}. Master-Playbook ausfuehren${NC}"
echo ""
echo "     cd $REPO_DIR"
echo "     ansible-playbook playbooks/setup-master.yml -i inventories/master/"
echo ""
STEP=$((STEP + 1))

echo -e "${BOLD}  ${STEP}. PocketID API-Token eintragen (nach erstem Playbook-Lauf)${NC}"
echo ""
echo "     a) https://id.${ADMIN_DOMAIN} oeffnen"
echo "     b) Einloggen (Passwort steht in der Ansible-Ausgabe)"
echo "     c) Settings -> API -> Token generieren"
echo "     d) Token eintragen:"
echo "        nano $REPO_DIR/config/lococloudd.yml"
echo "        -> pocketid.api_token: \"<TOKEN>\""
echo ""
STEP=$((STEP + 1))

echo -e "${BOLD}  ${STEP}. Vaultwarden einrichten + Playbook erneut ausfuehren${NC}"
echo ""
echo "     a) https://vault.${ADMIN_DOMAIN} oeffnen"
echo "     b) Admin-Account erstellen"
echo "     c) Organisation \"LocoCloud\" anlegen"
echo "     d) Organisation-ID in config/lococloudd.yml eintragen"
echo "     e) Playbook nochmal ausfuehren:"
echo "        ansible-playbook playbooks/setup-master.yml -i inventories/master/"
echo ""
