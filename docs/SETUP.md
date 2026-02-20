# LocoCloud Setup — Kompletter Start bei Null

## Schnellstart

Auf einem frischen Debian 13 (Trixie) Server als root:

```bash
apt update && apt install -y curl
curl -fsSL https://raw.githubusercontent.com/Ollornog/LocoCloud/main/scripts/setup.sh -o setup.sh
bash setup.sh
```

Das Script fragt interaktiv alles ab: Domain, Name, E-Mail, Netbird-Zugang, SMTP.
Danach sind Pakete, Netbird, Repo, Ansible und Config fertig eingerichtet.

---

## Was das Setup-Script macht

1. **System aktualisieren** — `apt update && apt upgrade`
2. **Grundpakete installieren** — sudo, curl, git, wget, gnupg, ca-certificates, pipx, jq
3. **Netbird installieren** — `curl -fsSL https://pkgs.netbird.io/install.sh | sh`
4. **Netbird joinen** (optional) — Management-URL + Setup-Key abfragen, Netbird-IP ermitteln
5. **Repo klonen** — `git clone https://github.com/Ollornog/LocoCloud.git /root/LocoCloud`
6. **Ansible installieren** — via pipx, PATH automatisch gesetzt
7. **Ansible Collections installieren** — community.general, community.docker, ansible.posix
8. **Konfiguration abfragen** — Name, E-Mail, Domain. Subdomains werden automatisch generiert
9. **`config/lococloudd.yml` schreiben** — alle URLs automatisch aus der Basis-Domain abgeleitet
10. **Master-Inventar vorbereiten** — `inventories/master/hosts.yml` mit Netbird-IP befuellen

---

## Voraussetzungen

- Debian 13 (Trixie), Minimal-Installation
- Mindestens 2 CPU-Kerne, 2 GB RAM, 20 GB Disk
- Root-Zugang (SSH oder Konsole)
- Ein Netbird-Management-Server (extern oder self-hosted)

---

## Nach dem Setup-Script

### 1. DNS einrichten

```
*.admin.example.com → A-Record auf die Public IP des Gateway-Servers
```

### 2. SSH-Keys eintragen

Datei `inventories/master/group_vars/all.yml`:

```yaml
admin_ssh_pubkeys:
  - "ssh-ed25519 AAAA... admin@workstation"
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
2. Admin-Passwort aus Ansible-Ausgabe oder Vaultwarden
3. Settings → API → Token generieren
4. Token in `config/lococloudd.yml` eintragen:
   ```yaml
   pocketid:
     api_token: "euer-token-hier"
   ```

### 5. Vaultwarden einrichten

1. `https://vault.admin.example.com` oeffnen
2. Admin-Account erstellen
3. Organisation "LocoCloud" anlegen
4. Organisation-ID in `config/lococloudd.yml` eintragen

### 6. Vault-Passwort konfigurieren

```bash
# Item in Vaultwarden: Name = "lococloudd-ansible-vault"
# Passwort = langes, zufaelliges Passwort
bash scripts/vault-pass.sh  # Testen
```

### 7. Playbook erneut ausfuehren

```bash
ansible-playbook playbooks/setup-master.yml -i inventories/master/
```

Jetzt werden Credentials automatisch in Vaultwarden gespeichert.

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

Falls du das Script nicht nutzen willst:

```bash
# System
apt update && apt upgrade -y
apt install -y sudo curl git wget gnupg ca-certificates pipx jq

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
# -> Datei ausfuellen

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

## Naechste Schritte

- **Kunden onboarden:** Siehe [ONBOARDING.md](ONBOARDING.md)
- **App-Rolle entwickeln:** Siehe [APP-DEVELOPMENT.md](APP-DEVELOPMENT.md)
- **Probleme:** Siehe [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
