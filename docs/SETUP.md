# Master-Server Setup — Anleitung

Diese Anleitung beschreibt die Ersteinrichtung des LocoCloud Master-Servers auf einem frischen Debian 13 (Trixie) LXC oder VPS.

---

## Voraussetzungen

### Hardware / VPS

- Debian 13 (Trixie), frisch installiert
- Mindestens 2 CPU-Kerne, 2 GB RAM, 20 GB Disk
- Öffentliche IP-Adresse (oder Erreichbarkeit über Netbird)
- Root-Zugang via SSH

### Netzwerk

- Ein Netbird-Management-Server muss bereits laufen (z.B. `netbird.example.com`)
- DNS-Wildcard-Eintrag: `*.admin.example.com` → IP des Gateway-Servers
- Der Gateway-Server leitet per Caddy + Netbird an den Master weiter

### Auf dem Admin-Rechner

- Git, SSH-Key-Pair
- Ansible >= 2.15 (mit `community.general`, `community.docker`, `ansible.posix`)
- Bitwarden CLI (`bw`) für Vault-Passwort-Management

---

## Schritt 1: Repo klonen

```bash
git clone git@github.com:Ollornog/LocoCloud.git
cd LocoCloud
```

## Schritt 2: Ansible Collections installieren

```bash
ansible-galaxy collection install -r requirements.yml
```

## Schritt 3: Globale Config anlegen

```bash
cp config/lococloudd.yml.example config/lococloudd.yml
```

Datei ausfüllen:

| Feld | Beschreibung |
|------|-------------|
| `operator.name` | Dein Name |
| `operator.email` | Admin-E-Mail (wird PocketID-Admin) |
| `operator.domain` | Basis-Domain (z.B. `admin.example.com`) |
| `urls.*` | Subdomains für Admin-Dienste |
| `netbird.manager_url` | URL des Netbird-Management-Servers |
| `netbird.api_token` | Netbird API-Token |
| `pocketid.api_token` | PocketID API-Token (nach Erstsetup eintragen) |
| `smtp.*` | SMTP-Zugangsdaten für E-Mail-Versand |
| `vaultwarden.url` | URL der Admin-Vaultwarden-Instanz |

**Wichtig:** `config/lococloudd.yml` ist in `.gitignore` und wird NICHT committet.

## Schritt 4: Master-Inventar konfigurieren

Datei `inventories/master/hosts.yml` bearbeiten:

```yaml
all:
  hosts:
    master:
      ansible_host: <NETBIRD-IP-DES-MASTERS>
      ansible_user: root  # Erster Lauf als root, danach srvadmin
      is_lxc: true        # Falls LXC-Container
      server_roles: [master]
```

Datei `inventories/master/group_vars/all.yml` bearbeiten:

```yaml
admin_ssh_pubkeys:
  - "ssh-ed25519 AAAA... admin@workstation"
```

## Schritt 5: Master-Playbook ausführen

```bash
ansible-playbook playbooks/setup-master.yml -i inventories/master/
```

Das Playbook führt folgende Rollen in Reihenfolge aus:

1. **base** — OS-Hardening, Docker, UFW, Fail2ban
2. **netbird_client** — VPN-Anbindung
3. **pocketid** — OIDC-Provider (Admin-Instanz)
4. **tinyauth** — Forward-Auth
5. **vaultwarden** — Credential-Store
6. **semaphore** — Ansible Web-UI
7. **caddy** — Reverse Proxy (kommt zuletzt, braucht alle Backends)

## Schritt 6: PocketID API-Token eintragen

Nach dem ersten Lauf:

1. PocketID unter `https://id.admin.example.com` öffnen
2. Admin-Passwort findet sich in der Ansible-Ausgabe (oder in Vaultwarden)
3. API-Token generieren unter Settings → API
4. Token in `config/lococloudd.yml` eintragen:
   ```yaml
   pocketid:
     api_token: "euer-token-hier"
   ```

## Schritt 7: Vaultwarden einrichten

1. `https://vault.admin.example.com` öffnen
2. Admin-Account erstellen
3. Organisation "LocoCloud" anlegen
4. Organisation-ID in `config/lococloudd.yml` eintragen

## Schritt 8: Vault-Passwort konfigurieren

```bash
# Item in Vaultwarden erstellen: Name = "lococloudd-ansible-vault"
# Passwort = ein langes, zufälliges Passwort

# Testen:
bash scripts/vault-pass.sh
```

## Schritt 9: Playbook erneut ausführen (mit Credentials)

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

## Troubleshooting

Siehe [docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md) für bekannte Probleme und Lösungen.
