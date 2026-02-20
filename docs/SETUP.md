# LocoCloud Setup — Kompletter Start bei Null

Diese Anleitung beschreibt die Ersteinrichtung von LocoCloud auf einem frischen Server — vom blanken Debian bis zum laufenden Master mit allen Admin-Diensten.

---

## Phase 1: Server vorbereiten (manuell)

### 1.1 Frischen Server bereitstellen

- Debian 13 (Trixie), Minimal-Installation
- Mindestens 2 CPU-Kerne, 2 GB RAM, 20 GB Disk
- Öffentliche IP-Adresse (für Gateway) oder nur Netbird-erreichbar (für Master)
- Root-Zugang (SSH oder Konsole)

### 1.2 System aktualisieren

```bash
apt update && apt upgrade -y
```

### 1.3 Grundpakete installieren

```bash
apt install -y sudo curl git wget gnupg ca-certificates
```

### 1.4 Netbird installieren

Netbird wird als VPN-Mesh für die gesamte Kommunikation verwendet. Ein externer Netbird-Management-Server muss bereits existieren (z.B. `netbird.example.com`).

```bash
# Signing Key herunterladen
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.netbird.io/debian/public.key -o /etc/apt/keyrings/netbird.asc

# Repository hinzufügen
echo "deb [signed-by=/etc/apt/keyrings/netbird.asc] https://pkgs.netbird.io/debian stable main" \
  > /etc/apt/sources.list.d/netbird.list

# Installieren und starten
apt update && apt install -y netbird
netbird up --management-url https://netbird.example.com --setup-key DEIN-SETUP-KEY
```

Nach dem Join die Netbird-IP notieren:

```bash
netbird status
# Die 100.x.x.x IP wird für das Ansible-Inventar benötigt
```

### 1.5 Admin-Benutzer anlegen (optional)

Falls du nicht als root arbeiten willst:

```bash
adduser srvadmin
usermod -aG sudo srvadmin
```

---

## Phase 2: LocoCloud-Repo klonen

```bash
git clone https://github.com/Ollornog/LocoCloud.git
cd LocoCloud
```

**Hinweis:** HTTPS, kein SSH — so braucht der Server keinen Deploy-Key für den initialen Clone.

---

## Phase 3: Ansible auf dem Server einrichten

### 3.1 Ansible installieren

```bash
apt install -y pipx
pipx install ansible-core
pipx ensurepath
# Neue Shell öffnen oder:
export PATH="$PATH:/root/.local/bin"
```

### 3.2 Ansible Collections installieren

```bash
cd /root/LocoCloud  # oder wo auch immer das Repo liegt
ansible-galaxy collection install -r requirements.yml
```

Die benötigten Collections:
- `community.general` — Proxmox LXC, Bitwarden Lookup-Plugin
- `community.docker` — Docker Compose Management
- `ansible.posix` — sysctl, authorized_key, etc.

---

## Phase 4: Globale Konfiguration

### 4.1 Config-Datei anlegen

```bash
cp config/lococloudd.yml.example config/lococloudd.yml
```

### 4.2 Config ausfüllen

Die wichtigsten Felder:

| Feld | Beschreibung | Beispiel |
|------|-------------|---------|
| `operator.name` | Dein Name | `"Max Mustermann"` |
| `operator.email` | Admin-E-Mail (wird PocketID-Admin) | `"admin@example.com"` |
| `operator.domain` | Basis-Domain | `"example.com"` |
| `admin.full_domain` | Admin-Subdomain | `"admin.example.com"` |
| `urls.*` | Subdomains für Admin-Dienste | `id.admin.example.com` etc. |
| `netbird.manager_url` | URL des Netbird-Management-Servers | `"https://netbird.example.com"` |
| `netbird.api_token` | Netbird API-Token | — |
| `smtp.*` | SMTP-Zugangsdaten für E-Mail-Versand | — |

**Wichtig:** `config/lococloudd.yml` ist in `.gitignore` und wird NICHT committet.

---

## Phase 5: Master-Inventar konfigurieren

### 5.1 hosts.yml bearbeiten

Datei `inventories/master/hosts.yml`:

```yaml
all:
  hosts:
    loco-master:
      ansible_host: 100.x.x.x      # Netbird-IP des Servers (aus Phase 1.4)
      ansible_user: root             # Erster Lauf als root, danach srvadmin
      server_roles: [master]
      is_lxc: true                   # Falls LXC-Container, sonst false
```

### 5.2 SSH-Keys hinterlegen

Datei `inventories/master/group_vars/all.yml`:

```yaml
admin_ssh_pubkeys:
  - "ssh-ed25519 AAAA... admin@workstation"
```

### 5.3 Vault-Datei anlegen

Datei `inventories/master/group_vars/vault.yml`:

```yaml
vault_master_netbird_setup_key: "DEIN-NETBIRD-SETUP-KEY"
vault_master_netbird_ip: "100.x.x.x"
```

Verschlüsseln:

```bash
ansible-vault encrypt inventories/master/group_vars/vault.yml
```

---

## Phase 6: Master-Playbook ausführen

### 6.1 DNS einrichten

Bevor das Playbook läuft, müssen DNS-Einträge existieren:

- `*.admin.example.com` → A-Record auf die Public IP des Gateway-Servers

### 6.2 Playbook starten

```bash
ansible-playbook playbooks/setup-master.yml -i inventories/master/
```

Das Playbook richtet in dieser Reihenfolge ein:

1. **base** — OS-Hardening, Docker, UFW, Fail2ban
2. **netbird_client** — VPN-Anbindung
3. **pocketid** — OIDC-Provider (Admin-Instanz)
4. **tinyauth** — Forward-Auth
5. **vaultwarden** — Credential-Store
6. **semaphore** — Ansible Web-UI
7. **caddy** — Reverse Proxy (kommt zuletzt, braucht alle Backends)

---

## Phase 7: Nach dem ersten Lauf

### 7.1 PocketID API-Token eintragen

1. PocketID unter `https://id.admin.example.com` öffnen
2. Admin-Passwort findet sich in der Ansible-Ausgabe (oder in Vaultwarden)
3. API-Token generieren unter Settings → API
4. Token in `config/lococloudd.yml` eintragen:
   ```yaml
   pocketid:
     api_token: "euer-token-hier"
   ```

### 7.2 Vaultwarden einrichten

1. `https://vault.admin.example.com` öffnen
2. Admin-Account erstellen
3. Organisation "LocoCloud" anlegen
4. Organisation-ID in `config/lococloudd.yml` eintragen

### 7.3 Vault-Passwort konfigurieren

```bash
# Item in Vaultwarden erstellen: Name = "lococloudd-ansible-vault"
# Passwort = ein langes, zufälliges Passwort

# Testen:
bash scripts/vault-pass.sh
```

### 7.4 Playbook erneut ausführen (mit Credentials)

```bash
ansible-playbook playbooks/setup-master.yml -i inventories/master/
```

Jetzt werden Credentials automatisch in Vaultwarden gespeichert.

---

## Ergebnis

Nach der Einrichtung sind folgende Dienste erreichbar:

| Dienst | URL | Funktion |
|--------|-----|----------|
| PocketID | `https://id.admin.example.com` | OIDC Provider |
| Tinyauth | `https://auth.admin.example.com` | Forward Auth |
| Vaultwarden | `https://vault.admin.example.com` | Credential Store |
| Semaphore | `https://deploy.admin.example.com` | Ansible Web-UI |

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

DNS: `*.admin.example.com` → A-Record auf die Public IP des Gateway-Servers.

---

## Nächste Schritte

- **Ersten Kunden onboarden:** Siehe [ONBOARDING.md](ONBOARDING.md)
- **Neue App-Rolle entwickeln:** Siehe [APP-DEVELOPMENT.md](APP-DEVELOPMENT.md)
- **Probleme lösen:** Siehe [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

---

## Troubleshooting

| Problem | Lösung |
|---------|--------|
| `ansible: command not found` | `export PATH="$PATH:/root/.local/bin"` oder neue Shell öffnen |
| Netbird Join schlägt fehl | Setup-Key prüfen, Management-URL prüfen |
| Playbook findet Config nicht | `config/lococloudd.yml` muss existieren (Kopie von `.example`) |
| SSH-Verbindung abgelehnt | `ansible_user` und SSH-Key in `hosts.yml` prüfen |
| 502 auf Admin-URLs | Caddy-Config prüfen, `tls_server_name` gesetzt? |
