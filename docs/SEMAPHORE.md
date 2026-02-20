# Semaphore-Templates — Konfiguration

Semaphore ist die Web-UI für Ansible-Deployments. Erreichbar unter `deploy.admin.example.com`.

---

## Semaphore einrichten

### Zugang

Nach dem Master-Setup ist Semaphore unter `https://deploy.admin.example.com` erreichbar. Login-Credentials befinden sich in der Admin-Vaultwarden-Instanz.

### Repository hinzufügen

1. **Key Store** → SSH-Key des Masters hinzufügen (für Git-Zugriff)
2. **Repositories** → Neues Repository:
   - Name: `LocoCloud`
   - URL: `git@github.com:Ollornog/LocoCloud.git`
   - Branch: `main`
   - Access Key: SSH-Key aus Schritt 1

### Vault-Passwort hinterlegen

1. **Key Store** → Neuen Eintrag:
   - Name: `Ansible Vault Password`
   - Type: `Login with password`
   - Password: Das Ansible-Vault-Passwort

---

## Projekt-Templates pro Kunde

Für jeden Kunden wird ein Semaphore-Projekt erstellt. Jedes Projekt enthält Templates für alle verfügbaren Playbooks.

### Projekt erstellen

1. **Projects** → Neues Projekt:
   - Name: `Kunde — Firma ABC (firma-abc.de)`
2. **Inventory** → Neue Inventory:
   - Name: `Firma ABC`
   - Type: `File`
   - Path: `inventories/kunde-abc001/`

### Templates

Folgende Templates pro Kunde anlegen:

#### Full Deploy (site.yml)

| Feld | Wert |
|------|------|
| Name | Full Deploy |
| Playbook | `playbooks/site.yml` |
| Inventory | Firma ABC |
| Vault Password | Ansible Vault Password |
| Description | Vollständiger Deploy: Base + Auth + alle Apps. Idempotent. |

#### Add App

| Feld | Wert |
|------|------|
| Name | Add App |
| Playbook | `playbooks/add-app.yml` |
| Inventory | Firma ABC |
| Vault Password | Ansible Vault Password |
| Extra Variables | `{"app_name": "Nextcloud"}` |
| Description | Einzelne App hinzufügen. `app_name` anpassen. |

#### Remove App

| Feld | Wert |
|------|------|
| Name | Remove App |
| Playbook | `playbooks/remove-app.yml` |
| Inventory | Firma ABC |
| Vault Password | Ansible Vault Password |
| Extra Variables | `{"app_name": "Nextcloud"}` |
| Description | App entfernen (Daten werden archiviert). |

#### Add User

| Feld | Wert |
|------|------|
| Name | Add User |
| Playbook | `playbooks/add-user.yml` |
| Inventory | Firma ABC |
| Vault Password | Ansible Vault Password |
| Extra Variables | `{"username": "m.mustermann", "email": "m.mustermann@firma-abc.de", "display_name": "Max Mustermann"}` |
| Description | Benutzer in PocketID + Tinyauth anlegen. |

#### Remove User

| Feld | Wert |
|------|------|
| Name | Remove User |
| Playbook | `playbooks/remove-user.yml` |
| Inventory | Firma ABC |
| Vault Password | Ansible Vault Password |
| Extra Variables | `{"username": "m.mustermann", "email": "m.mustermann@firma-abc.de"}` |
| Description | Benutzer aus PocketID + Tinyauth entfernen. |

#### OS Update

| Feld | Wert |
|------|------|
| Name | OS Update |
| Playbook | `playbooks/update-all.yml` |
| Inventory | Firma ABC |
| Vault Password | Ansible Vault Password |
| Description | OS-Updates auf allen Servern des Kunden. Seriell (ein Server nach dem anderen). |

#### Backup Now

| Feld | Wert |
|------|------|
| Name | Backup Now |
| Playbook | `playbooks/backup-now.yml` |
| Inventory | Firma ABC |
| Vault Password | Ansible Vault Password |
| Description | Sofortiges Backup auslösen. |

#### Restore

| Feld | Wert |
|------|------|
| Name | Restore |
| Playbook | `playbooks/restore.yml` |
| Inventory | Firma ABC |
| Vault Password | Ansible Vault Password |
| Description | Restore aus Backup. |

#### Offboard Customer

| Feld | Wert |
|------|------|
| Name | Offboard Customer |
| Playbook | `playbooks/offboard-customer.yml` |
| Inventory | Firma ABC |
| Vault Password | Ansible Vault Password |
| Extra Variables | `{"destroy": false}` |
| Description | Kunden-Offboarding. `destroy: true` löscht LXCs + Netbird-Peers. |

---

## Master-Projekt

Ein zusätzliches Projekt für den Master-Server:

### Templates

#### Master Setup

| Feld | Wert |
|------|------|
| Name | Master Setup |
| Playbook | `playbooks/setup-master.yml` |
| Inventory | Master |
| Vault Password | Ansible Vault Password |
| Description | Master-Server Setup/Update. Idempotent. |

---

## Schedules

Für wiederkehrende Aufgaben können Schedules eingerichtet werden:

| Template | Cron | Beschreibung |
|----------|------|-------------|
| OS Update | `0 3 * * 0` | Sonntags 03:00 — OS-Updates |
| Backup Now | `0 2 * * *` | Täglich 02:00 — Backup (zusätzlich zum Cron auf dem Server) |
| Full Deploy | `0 4 * * 1` | Montags 04:00 — Drift-Detection (idempotent) |

---

## Berechtigungen

- **Admin** (Betreiber): Voller Zugriff auf alle Projekte
- **Kunden-Admins**: Kein Semaphore-Zugriff (nur über Betreiber)
- Semaphore ist hinter Tinyauth geschützt — nur gewhitelistete Admins haben Zugang
