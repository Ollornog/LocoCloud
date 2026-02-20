# Kunden-Onboarding — Schritt für Schritt

Diese Anleitung beschreibt den kompletten Ablauf, einen neuen Kunden in LocoCloud einzurichten.

---

## Überblick

```
1. Kunden-Inventar anlegen          ← scripts/new-customer.sh
2. Inventar konfigurieren           ← hosts.yml + group_vars/all.yml + vault.yml
3. Netbird + Auth-Stack deployen    ← onboard-customer.yml
4. Apps deployen                    ← site.yml oder add-app.yml
5. Benutzer anlegen                 ← add-user.yml
```

---

## Schritt 1: Kunden-Inventar anlegen

```bash
bash scripts/new-customer.sh <kunde_id> "<kunde_name>" "<kunde_domain>" <variante>
```

**Beispiel:**
```bash
bash scripts/new-customer.sh abc001 "Firma ABC GmbH" "firma-abc.de" hybrid
```

Varianten:
- `cloud_only` — Server bei Hetzner, kein lokaler Proxmox
- `hybrid` — Hetzner Entry-Point + lokaler Proxmox mit LXCs
- `lokal_only` — Alles lokal auf Proxmox, Gateway-LXC als Entry-Point

Das Script erstellt:
```
inventories/kunde-abc001/
├── hosts.yml
└── group_vars/
    ├── all.yml
    └── vault.yml
```

## Schritt 2: Inventar konfigurieren

### hosts.yml

Server-Einträge je nach Variante:

**Cloud-Only:**
```yaml
all:
  hosts:
    abc001-online:
      ansible_host: "{{ vault_hetzner_netbird_ip }}"
      ansible_user: srvadmin
      is_lxc: false
      server_role: online
```

**Hybrid:**
```yaml
all:
  hosts:
    abc001-online:
      ansible_host: "{{ vault_hetzner_netbird_ip }}"
      ansible_user: srvadmin
      is_lxc: false
      server_role: online
    abc001-proxmox:
      ansible_host: "{{ vault_proxmox_netbird_ip }}"
      ansible_user: root
      server_role: proxmox
```

**Lokal-Only:**
```yaml
all:
  hosts:
    abc001-proxmox:
      ansible_host: "{{ vault_proxmox_netbird_ip }}"
      ansible_user: root
      server_role: proxmox
    abc001-gateway:
      ansible_host: "{{ vault_gateway_netbird_ip }}"
      ansible_user: srvadmin
      is_lxc: true
      server_role: gateway
```

### group_vars/all.yml

Apps konfigurieren:

```yaml
apps_enabled:
  - name: "Nextcloud"
    subdomain: "cloud"
    port: 8080
    image: "nextcloud:29"
    target: "online"          # online = Hetzner, lokal = Proxmox-LXC
    oidc_enabled: true
    oidc_redirect_path: "/apps/user_oidc/code"
    needs_db: true
    db_type: "mariadb"
    needs_redis: true
    redis_db: 0
    public_paths:
      - "/index.php/s/*"
      - "/s/*"
    backup_paths:
      - "/mnt/data/nextcloud"

  - name: "Paperless"
    subdomain: "docs"
    port: 8000
    image: "ghcr.io/paperless-ngx/paperless-ngx:latest"
    target: "online"
    oidc_enabled: true
    needs_db: true
    db_type: "postgres"
    needs_redis: true
    redis_db: 1
    backup_paths:
      - "/opt/stacks/paperless"

  - name: "Vaultwarden"
    subdomain: "vault"
    port: 8222
    image: "vaultwarden/server:latest"
    target: "online"
    oidc_enabled: true
    backup_paths:
      - "/opt/stacks/vaultwarden/data"
```

Benutzer definieren:

```yaml
kunden_users:
  - username: "m.mustermann"
    display_name: "Max Mustermann"
    email: "m.mustermann@firma-abc.de"
  - username: "e.muster"
    display_name: "Erika Muster"
    email: "e.muster@firma-abc.de"
```

### vault.yml verschlüsseln

```bash
# Secrets eintragen
vim inventories/kunde-abc001/group_vars/vault.yml

# Verschlüsseln
ansible-vault encrypt inventories/kunde-abc001/group_vars/vault.yml
```

## Schritt 3: Onboarding ausführen

```bash
ansible-playbook playbooks/onboard-customer.yml -i inventories/kunde-abc001/
```

Das Playbook durchläuft:

1. **Play 1 (localhost):** Netbird-Gruppe + Policies + Setup-Key erstellen
2. **Play 2 (Entry-Point):** Base + Netbird + PocketID + Tinyauth + Caddy
3. **Play 3 (Proxmox):** LXCs erstellen (nur hybrid/lokal_only)
4. **Play 4 (Gateway):** Auth-Stack auf Gateway (nur lokal_only)

## Schritt 4: Apps deployen

**Alle Apps auf einmal:**
```bash
ansible-playbook playbooks/site.yml -i inventories/kunde-abc001/
```

**Einzelne App hinzufügen:**
```bash
ansible-playbook playbooks/add-app.yml -i inventories/kunde-abc001/ \
  -e "app_name=Nextcloud"
```

## Schritt 5: Benutzer anlegen

```bash
ansible-playbook playbooks/add-user.yml -i inventories/kunde-abc001/ \
  -e "username=m.mustermann email=m.mustermann@firma-abc.de display_name='Max Mustermann'"
```

---

## DNS-Konfiguration

### Cloud-Only / Hybrid

DNS beim Kunden-Domain-Provider:

```
*.firma-abc.de  →  A-Record  →  Hetzner-IP des Entry-Point-Servers
```

### Lokal-Only

Port-Forward auf dem Kunden-Router:
- Port 80 → Gateway-LXC IP
- Port 443 → Gateway-LXC IP

DNS:
```
*.firma-abc.de  →  A-Record  →  Öffentliche IP des Kunden-Routers
```

Bei dynamischer IP: DynDNS aktivieren in `group_vars/all.yml`:
```yaml
dyndns:
  enabled: true
  provider: "master"
```

---

## Nachträgliche Änderungen

### App hinzufügen

1. App zu `apps_enabled` in `group_vars/all.yml` hinzufügen
2. `ansible-playbook playbooks/add-app.yml -i inventories/kunde-abc001/ -e "app_name=Nextcloud"`

### App entfernen

```bash
ansible-playbook playbooks/remove-app.yml -i inventories/kunde-abc001/ \
  -e "app_name=Nextcloud"
```

Daten werden archiviert (unter `/opt/archives/`), nicht gelöscht.

### Benutzer entfernen

```bash
ansible-playbook playbooks/remove-user.yml -i inventories/kunde-abc001/ \
  -e "username=m.mustermann email=m.mustermann@firma-abc.de"
```

### Kunden-Offboarding

```bash
# Archivieren (Services stoppen, Daten behalten)
ansible-playbook playbooks/offboard-customer.yml -i inventories/kunde-abc001/

# Komplett löschen (LXCs + Netbird-Peers entfernen)
ansible-playbook playbooks/offboard-customer.yml -i inventories/kunde-abc001/ \
  -e "destroy=true"
```

---

## Checkliste nach Onboarding

- [ ] Alle Subdomains erreichbar (PocketID, Tinyauth, Apps)
- [ ] Admin-Login in PocketID funktioniert
- [ ] OIDC-Login in jeder App funktioniert
- [ ] Kunden-Benutzer können sich anmelden
- [ ] Credentials in Vaultwarden gespeichert
- [ ] Backup konfiguriert und getestet (falls aktiviert)
- [ ] Monitoring-Agent meldet sich beim Zabbix-Server (falls aktiviert)
