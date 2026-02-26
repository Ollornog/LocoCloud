# LocoCloud Setup — Kompletter Start bei Null

## Schnellstart

Auf einem frischen Debian 12/13 Server als root:

```bash
apt update && apt install -y curl
curl -fsSL https://raw.githubusercontent.com/Ollornog/LocoCloud/main/scripts/setup.sh -o setup.sh
bash setup.sh
```

Das Script fragt zuerst alles ab, installiert dann alles automatisch
und fuehrt am Ende das Ansible-Playbook aus.

---

## Was das Setup-Script macht

**Zuerst: Alle Fragen auf einmal**
- Name, E-Mail, Basis-Domain
- Admin-Subdomain (default: `admin`)
- SMTP-Zugangsdaten (optional)
- Gateway Public IP
- Eigener Netbird-Server? Wenn ja: Domain + Relay-Domain
- Netbird Management-URL + Setup-Key

**Dann: Automatische Installation**
1. `apt update && apt upgrade` + Grundpakete
2. Docker installieren (`get.docker.com`)
3. Netbird-Server deployen (falls self-hosted)
4. Netbird-Client installieren + joinen
5. Repo klonen nach `/root/LocoCloud`
6. Ansible installieren (pipx) + Collections
7. `config/lococloudd.yml` generieren
8. SSH-Key generieren + in Inventar eintragen
9. Master-Inventar mit `ansible_connection: local` vorbereiten
10. Master-Playbook automatisch ausfuehren

**Am Ende: Zusammenfassung mit naechsten Schritten**

---

## Voraussetzungen

- Debian 12 (Bookworm) oder 13 (Trixie), Minimal-Installation
- Mindestens 2 CPU-Kerne, 2 GB RAM, 20 GB Disk
- Root-Zugang (SSH oder Konsole)

---

## Nach dem Setup-Script

Das Playbook laeuft automatisch am Ende des Scripts. Danach gibt es
nur noch wenige manuelle Schritte:

### 1. DNS einrichten

Wildcard-DNS auf die Gateway Public IP zeigen lassen:

```
*.admin.example.com → A-Record auf Gateway Public IP
```

Falls Netbird self-hosted:
```
netbird.example.com → A-Record auf diesen Server
relay.example.com   → A-Record auf diesen Server
```

### 2. Gateway-Caddy konfigurieren

Auf dem Gateway-Server muss Caddy den Admin-Wildcard an den Master weiterleiten:

```
*.admin.example.com {
    tls {
        dns cloudflare {env.CF_API_TOKEN}
    }
    reverse_proxy https://<MASTER-NETBIRD-IP> {
        header_up Host {host}
        transport http {
            tls_server_name admin.example.com
            versions 1.1
        }
    }
}
```

> **Wichtig:** `versions 1.1` ist bei `reverse_proxy https://` ueber Netbird VPN Pflicht.
> HTTP/2 Binary Framing fragmentiert bei WireGuard MTU ~1420 und fuehrt zu leeren Responses.

### 3. PocketID: Passkey registrieren + API-Key erstellen

1. `https://id.admin.example.com` im Browser oeffnen
2. Admin-Account mit Passkey einrichten
3. Settings → API Keys → Neuen Key erstellen
4. Key in `config/lococloudd.yml` eintragen:
   ```yaml
   pocketid:
     api_token: "euer-api-key"
   ```

### 4. Playbook erneut ausfuehren (mit API-Key)

```bash
ansible-playbook playbooks/setup-master.yml -i inventories/master/
```

Beim zweiten Lauf passiert automatisch:
- Vaultwarden wird als OIDC-Client in PocketID registriert
- SSO-Login fuer Vaultwarden wird aktiviert (`SSO_ONLY=true`)
- OIDC-Credentials werden in Vaultwarden gespeichert

### 5. Vaultwarden: Master-Passwort setzen

1. `https://vault.admin.example.com` oeffnen
2. "Use single sign-on" klicken (Login via PocketID)
3. Master-Passwort setzen (fuer Vault-Verschluesselung)
4. Organisation "LocoCloud" im Admin-Panel anlegen
5. Organisation-ID in `config/lococloudd.yml` eintragen

---

## Sicherheitskonzept

| Massnahme | Details |
|-----------|---------|
| PocketID Registration | Blockiert via Caddy (`/register` → 403) |
| Vaultwarden Signups | Deaktiviert via Admin-Config-API (von `vw-credentials.py` gesteuert) |
| Vaultwarden Login | Nur via SSO/PocketID (`SSO_ONLY=true`) |
| Admin-Dienste | Hinter Tinyauth Forward-Auth (PocketID OIDC) |
| SSH-Key | Automatisch generiert, in `/root/.ssh/id_ed25519` |

---

## Ergebnis

| Dienst | URL | Funktion |
|--------|-----|----------|
| PocketID | `https://id.admin.example.com` | OIDC Provider |
| Tinyauth | `https://auth.admin.example.com` | Forward Auth |
| Vaultwarden | `https://vault.admin.example.com` | Credential Store (SSO via PocketID) |
| Semaphore | `https://deploy.admin.example.com` | Ansible Web-UI |
| Grafana | `https://grafana.admin.example.com` | Monitoring (Grafana + Prometheus + Loki) |
| Baserow | `https://baserow.admin.example.com` | Berechtigungsverwaltung |

Alle Credentials (Admin-Passwoerter, API-Tokens, OIDC-Secrets) werden automatisch
in der Admin-Vaultwarden-Instanz gespeichert.

---

## Manuelles Setup (ohne Script)

```bash
# System
apt update && apt upgrade -y
apt install -y sudo curl git wget gnupg ca-certificates pipx jq

# Docker
curl -fsSL https://get.docker.com | sh

# Netbird
curl -fsSL https://pkgs.netbird.io/install.sh | sh
netbird up --management-url https://netbird.example.com --setup-key DEIN-KEY

# Repo
git clone https://github.com/Ollornog/LocoCloud.git /root/LocoCloud
cd /root/LocoCloud

# Ansible
pipx install ansible-core
pipx ensurepath
export PATH="$PATH:/root/.local/bin"
ansible-galaxy collection install -r requirements.yml

# Config
cp config/lococloudd.yml.example config/lococloudd.yml
nano config/lococloudd.yml

# Ausfuehren
ansible-playbook playbooks/setup-master.yml -i inventories/master/
```

---

## Weiter

- **Semaphore einrichten:** Siehe [SEMAPHORE.md](SEMAPHORE.md)
- **Kunden onboarden:** Siehe [ONBOARDING.md](ONBOARDING.md)
- **App-Rolle entwickeln:** Siehe [APP-DEVELOPMENT.md](APP-DEVELOPMENT.md)
- **Probleme:** Siehe [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
