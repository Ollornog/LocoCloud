# LocoCloud Setup — Kompletter Start bei Null

## Schnellstart

Auf einem frischen Debian 12/13 Server als root:

```bash
apt update && apt install -y curl
curl -fsSL https://raw.githubusercontent.com/Ollornog/LocoCloud/main/scripts/setup.sh -o setup.sh
bash setup.sh
```

Das Script fragt zuerst alles ab (Name, E-Mail, Domain, Netbird, SMTP) und
fuehrt danach automatisch aus: Pakete, Docker, Netbird-Server (optional),
Netbird-Client, Repo-Clone, Ansible, Config-Generierung.

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
1. `apt update && apt upgrade` + Grundpakete (sudo, curl, git, pipx, jq, ...)
2. Docker installieren (`get.docker.com`)
3. Netbird-Server deployen (falls self-hosted) — Docker Compose Stack
4. Netbird-Client installieren + joinen
5. Repo klonen nach `/root/LocoCloud`
6. Ansible installieren (pipx) + Collections
7. `config/lococloudd.yml` generieren — alle Subdomains automatisch aus der Basis-Domain
8. Master-Inventar vorbereiten

**Am Ende: Zusammenfassung mit konkreten Befehlen und IPs**

---

## Voraussetzungen

- Debian 12 (Bookworm) oder 13 (Trixie), Minimal-Installation
- Mindestens 2 CPU-Kerne, 2 GB RAM, 20 GB Disk
- Root-Zugang (SSH oder Konsole)

---

## Nach dem Setup-Script

Das Script zeigt am Ende die naechsten Schritte mit konkreten Befehlen an.
Hier die Kurzfassung:

### 1. DNS einrichten

Das Script zeigt die oeffentliche IP des Servers an. DNS-Eintraege erstellen:

```
*.admin.example.com → A-Record auf die Public IP des Gateway-Servers
```

Falls Netbird self-hosted:
```
netbird.example.com → A-Record auf diesen Server
relay.example.com   → A-Record auf diesen Server
```

### 2. SSH-Public-Key eintragen

Damit Ansible sich per SSH verbinden kann, muss mindestens ein Public Key
hinterlegt werden. Den Key findest du auf deinem Admin-Rechner:

```bash
cat ~/.ssh/id_ed25519.pub
```

Diesen Key eintragen in `inventories/master/group_vars/all.yml`:

```yaml
admin_ssh_pubkeys:
  - "ssh-ed25519 AAAA... dein-name@rechner"
```

### 3. Master-Playbook ausfuehren

```bash
cd /root/LocoCloud
ansible-playbook playbooks/setup-master.yml -i inventories/master/
```

Das Playbook richtet ein:

| Reihenfolge | Rolle | Funktion |
|-------------|-------|----------|
| 1 | base | OS-Hardening, Docker, UFW, Fail2ban |
| 2 | netbird_client | VPN-Anbindung |
| 3 | pocketid | OIDC Provider |
| 4 | tinyauth | Forward Auth |
| 5 | vaultwarden | Credential Store |
| 6 | semaphore | Ansible Web-UI |
| 7 | caddy | Reverse Proxy |

### 4. PocketID API-Token eintragen

1. `https://id.admin.example.com` oeffnen
2. Einloggen (Passwort steht in der Ansible-Ausgabe)
3. Settings → API → Token generieren
4. Token in `config/lococloudd.yml` eintragen:
   ```yaml
   pocketid:
     api_token: "euer-token-hier"
   ```

### 5. Vaultwarden einrichten + Playbook erneut ausfuehren

1. `https://vault.admin.example.com` oeffnen
2. Admin-Account erstellen
3. Organisation "LocoCloud" anlegen
4. Organisation-ID in `config/lococloudd.yml` eintragen
5. Playbook nochmal ausfuehren:
   ```bash
   ansible-playbook playbooks/setup-master.yml -i inventories/master/
   ```

---

## Ergebnis

| Dienst | URL | Funktion |
|--------|-----|----------|
| PocketID | `https://id.admin.example.com` | OIDC Provider |
| Tinyauth | `https://auth.admin.example.com` | Forward Auth |
| Vaultwarden | `https://vault.admin.example.com` | Credential Store |
| Semaphore | `https://deploy.admin.example.com` | Ansible Web-UI |

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

## Admin-Gateway (Caddy)

Der Gateway-Server leitet `*.admin.example.com` per Caddy an den Master weiter:

```
*.admin.example.com {
    reverse_proxy https://<MASTER-NETBIRD-IP>:443 {
        header_up Host {host}
        transport http {
            tls_server_name admin.example.com
        }
    }
}
```

---

## Weiter

- **Kunden onboarden:** Siehe [ONBOARDING.md](ONBOARDING.md)
- **App-Rolle entwickeln:** Siehe [APP-DEVELOPMENT.md](APP-DEVELOPMENT.md)
- **Probleme:** Siehe [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
