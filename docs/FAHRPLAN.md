# LocoCloud — Implementierungs-Fahrplan

**Version:** 1.0 — Februar 2026
**Grundlage:** `docs/KONZEPT.md` v3.3

---

## Übersicht

Der Fahrplan gliedert die Implementierung in 7 Phasen. Jede Phase baut auf der vorherigen auf.
Phasen 1–4 ergeben ein minimal funktionsfähiges System (MVP: ein Cloud-Only-Kunde deployen).
Phasen 5–7 erweitern auf Hybrid/Lokal, Monitoring und Wartungsautomatisierung.

```
Phase 1: Repo-Grundgerüst + Base-Rolle         ← Fundament
Phase 2: Master-Server Setup                    ← Admin-Infrastruktur
Phase 3: Kunden-Onboarding (Cloud-Only)         ← Erster Kunde möglich
Phase 4: App-Rollen (Nextcloud, Paperless, VW)  ← MVP komplett
Phase 5: Proxmox + LXC (Hybrid/Lokal)          ← Volle Deployment-Varianten
Phase 6: Monitoring, Backup, Wartung            ← Produktionsbetrieb
Phase 7: Hardening, Docs, Public-Readiness      ← Release-Qualität
```

---

## Phase 1: Repo-Grundgerüst + Base-Rolle

**Ziel:** Funktionierendes Ansible-Projekt mit der wichtigsten Rolle.

### 1.1 Repo-Skelett anlegen

- [ ] `ansible.cfg` (Inventory-Pfad, Vault-Script, SSH-Pipelining)
- [ ] `requirements.yml` (community.general, community.docker, ansible.posix)
- [ ] `.gitignore` (config/lococloudd.yml, vault.yml, Keys, retry-Files)
- [ ] Verzeichnisstruktur:
  ```
  inventories/master/
  inventories/_template/
  roles/
  playbooks/
  scripts/
  ```

### 1.2 Base-Rolle (`roles/base/`)

Wird auf JEDEM Server/LXC ausgeführt. Grundlage für alles Weitere.

- [ ] `defaults/main.yml` — Konfigurierbare Variablen (admin_user, ssh_port, is_lxc)
- [ ] `tasks/main.yml` — Dispatcher mit Tags
- [ ] Tasks:
  - [ ] `packages.yml` — Basis-Pakete (curl, git, gnupg, htop, ufw, fail2ban, msmtp)
  - [ ] `user.yml` — srvadmin-User anlegen, SSH-Key, NOPASSWD-sudo
  - [ ] `ssh.yml` — Key-Only, PermitRootLogin no, Port konfigurierbar
  - [ ] `firewall.yml` — UFW Default Deny, SSH nur wt0, Ports je nach server_role
  - [ ] `hardening.yml` — sysctl (netzwerk-only bei LXC), unattended-upgrades
  - [ ] `fail2ban.yml` — SSH Jail
  - [ ] `docker.yml` — Docker CE + Compose Plugin installieren
- [ ] `handlers/main.yml` — restart sshd, restart ufw, restart fail2ban
- [ ] LXC-Kompatibilität: `is_lxc`-Checks für Kernel-Params, USB, TUN

### 1.3 Inventar-Templates

- [ ] `inventories/_template/hosts.yml.j2`
- [ ] `inventories/_template/group_vars/all.yml.j2`
- [ ] `inventories/master/hosts.yml`
- [ ] `inventories/master/group_vars/all.yml`

### 1.4 Scripts (Grundgerüst)

- [ ] `scripts/vault-pass.sh` — Ansible-Vault-Passwort aus Vaultwarden (bw CLI)
- [ ] `scripts/new-customer.sh` — Inventar aus Template generieren

**Ergebnis Phase 1:** `ansible-playbook playbooks/setup-master.yml` kann die Base-Rolle auf einem frischen Debian 13 ausführen.

---

## Phase 2: Master-Server Setup

**Ziel:** Vollständige Admin-Infrastruktur auf dem Master-LXC.

### 2.1 Netbird-Client-Rolle (`roles/netbird_client/`)

- [ ] Netbird installieren (apt-Repo)
- [ ] `netbird up` mit Setup-Key + Management-URL
- [ ] Netbird-IP ermitteln und als Fact registrieren
- [ ] TUN-Device-Check für LXC

### 2.2 Caddy-Rolle (`roles/caddy/`)

- [ ] Docker Compose Template (Host-Network-Mode)
- [ ] Caddyfile-Template (Jinja2) mit Snippets `(public)` und `(auth)`
- [ ] Master-spezifisches Caddyfile (Admin-Dienste)
- [ ] Kunden-Caddyfile-Template (Apps dynamisch aus `apps_enabled`)
- [ ] Handler: `docker restart caddy`

### 2.3 PocketID-Rolle (`roles/pocketid/`)

- [ ] Docker Compose Template
- [ ] Admin-Passwort generieren + in Vaultwarden speichern
- [ ] Caddyfile-Block: /register → 403, /settings → auth

### 2.4 Tinyauth-Rolle (`roles/tinyauth/`)

- [ ] Docker Compose Template
- [ ] OIDC-Client in PocketID registrieren (via API)
- [ ] OAUTH_WHITELIST konfigurieren

### 2.5 Credentials-Rolle (`roles/credentials/`)

- [ ] Vaultwarden API-Integration (uri-Modul)
- [ ] Ordner erstellen / Credential speichern / Credential lesen
- [ ] Wiederverwendbar für alle Rollen die Secrets speichern müssen

### 2.6 Vaultwarden-Rolle (Master) (`roles/apps/vaultwarden/`)

- [ ] Docker Compose Template
- [ ] Admin-Token generieren
- [ ] Organisation erstellen

### 2.7 Semaphore-Rolle (`roles/apps/semaphore/`)

- [ ] Docker Compose Template (+ PostgreSQL)
- [ ] OIDC mit Master-PocketID
- [ ] Projekt-Templates vorbereiten

### 2.8 Playbook: `setup-master.yml`

- [ ] Orchestriert alle obigen Rollen in der richtigen Reihenfolge
- [ ] pre_tasks: globale Config laden
- [ ] Reihenfolge: base → netbird → pocketid → tinyauth → vaultwarden → credentials → semaphore → caddy

### 2.9 Hetzner-Caddy-Konfiguration

- [ ] Playbook/Rolle für den Caddy auf Daniels Hetzner (*.loco.ollornog.de → Netbird → Master)
- [ ] Oder: Dokumentation für manuelle Einrichtung (falls der Hetzner nicht von Ansible verwaltet wird)

**Ergebnis Phase 2:** `setup-master.yml` richtet den Master-LXC komplett ein. Alle Admin-Dienste erreichbar unter `*.loco.ollornog.de`.

---

## Phase 3: Kunden-Onboarding (Cloud-Only)

**Ziel:** Erster Kunde komplett automatisiert deployen (einfachste Variante).

### 3.1 Netbird-Automation (`roles/netbird_client/` erweitern)

- [ ] `tasks/api.yml` — Netbird REST-API Integration:
  - Kundengruppe erstellen
  - Policies erstellen (intern, admin→kunde, backup→kunde)
  - Setup-Key generieren
- [ ] Idempotenz: Gruppe/Policy nur erstellen wenn nicht vorhanden

### 3.2 Playbook: `onboard-customer.yml` (Cloud-Only)

- [ ] Netbird-Gruppe + Policies + Setup-Key (API)
- [ ] Base-Rolle auf Kunden-Hetzner
- [ ] Netbird-Client auf Kunden-Hetzner
- [ ] PocketID deployen (id.firma.de)
- [ ] Admin-User in PocketID anlegen (API)
- [ ] Tinyauth deployen (auth.firma.de)
- [ ] Caddy deployen + Caddyfile generieren
- [ ] Credentials in Vaultwarden speichern
- [ ] Smoke-Test (HTTP-Checks auf Subdomains)

### 3.3 Playbook: `site.yml`

- [ ] Full-Deploy: Base + Auth-Stack + alle Apps aus `apps_enabled`
- [ ] Idempotent: Kann jederzeit erneut ausgeführt werden

### 3.4 User-Management Playbooks

- [ ] `add-user.yml` — PocketID API: User anlegen, Tinyauth Whitelist aktualisieren
- [ ] `remove-user.yml` — PocketID API: User deaktivieren, Tinyauth Whitelist aktualisieren

### 3.5 Script: `new-customer.sh` implementieren

- [ ] Inventar-Verzeichnis aus Template erstellen
- [ ] Interaktive Abfrage: Name, Domain, Variante, Apps
- [ ] vault.yml Grundgerüst (verschlüsselt)

**Ergebnis Phase 3:** `bash scripts/new-customer.sh` + `onboard-customer.yml` = funktionierender Kunde mit Auth-Stack (noch ohne Apps).

---

## Phase 4: App-Rollen (MVP)

**Ziel:** Die drei Kern-Apps deployen. Danach ist das MVP komplett.

### 4.1 App-Template-Rolle (`roles/apps/_template/`)

- [ ] Vorlage für neue App-Rollen (copy-paste-Basis)
- [ ] Standard-Tasks: deploy.yml, oidc.yml, remove.yml
- [ ] Standard-Templates: docker-compose.yml.j2, env.j2

### 4.2 Nextcloud (`roles/apps/nextcloud/`)

- [ ] Docker Compose: Nextcloud + MariaDB + Redis
- [ ] OIDC via PocketID API (user_oidc)
- [ ] occ-Befehle für Ersteinrichtung (trusted_domains, OIDC-Config)
- [ ] Public Paths: /s/*, /index.php/s/*
- [ ] HSTS-Fix (security.conf Volume-Mount)
- [ ] `--send-id-token-hint=0` für Single Logout

### 4.3 Paperless-NGX (`roles/apps/paperless/`)

- [ ] Docker Compose: Paperless + PostgreSQL + Redis + Gotenberg + Tika
- [ ] OIDC via PocketID API
- [ ] DISABLE_REGULAR_LOGIN, ACCOUNT_ALLOW_SIGNUPS=false
- [ ] PostgreSQL 18: Mount auf `/var/lib/postgresql`

### 4.4 Vaultwarden Kunde (`roles/apps/vaultwarden/`)

- [ ] Docker Compose: Vaultwarden (SQLite)
- [ ] OIDC via PocketID API (SSO)
- [ ] Admin-Token generieren + in Admin-VW speichern

### 4.5 Watchtower (`roles/apps/watchtower/`)

- [ ] Docker Compose: Label-basiert, Schedule 04:00
- [ ] E-Mail-Benachrichtigung bei Updates
- [ ] Wird auf jedem Server deployt (kein eigener Eintrag in apps_enabled)

### 4.6 Playbooks für App-Management

- [ ] `add-app.yml` — App zu bestehendem Kunden hinzufügen
- [ ] `remove-app.yml` — App entfernen (Daten archivieren)
- [ ] `update-app.yml` — Image-Tag aktualisieren, Container neu starten
- [ ] `update-caddy.yml` — Caddyfile regenerieren + restart

**Ergebnis Phase 4:** Ein Cloud-Only-Kunde mit Nextcloud, Paperless und Vaultwarden. Vollständig automatisiert, OIDC-SSO, Credentials in Vaultwarden. **Das ist das MVP.**

---

## Phase 5: Proxmox + LXC (Hybrid/Lokal)

**Ziel:** Hybrid- und Lokal-Only-Deployments ermöglichen.

### 5.1 LXC-Create-Rolle (`roles/lxc_create/`)

- [ ] LXC-Template herunterladen (pveam download, idempotent)
- [ ] LXC erstellen (community.general.proxmox)
- [ ] TUN-Device konfigurieren (für Netbird)
- [ ] LXC starten
- [ ] Bootstrap via pct exec:
  - SSH-Key injizieren
  - Netbird installieren + joinen
  - Netbird-IP ermitteln
- [ ] hosts.yml dynamisch aktualisieren (neue Netbird-IP)

### 5.2 Onboarding erweitern für Hybrid

- [ ] `onboard-customer.yml` um Proxmox-Logik erweitern
- [ ] Ablauf: Netbird-Setup → LXC erstellen → Bootstrap → Base → Apps
- [ ] Caddy auf Hetzner: Routen zu Netbird-IPs der lokalen LXCs

### 5.3 Onboarding für Lokal-Only

- [ ] Gateway-LXC erstellen (Caddy + PocketID + Tinyauth)
- [ ] Port-Forward-Dokumentation für Kunden-Router
- [ ] DynDNS-Integration (Master übernimmt DNS-Updates)

### 5.4 `add-app.yml` erweitern (lxc_per_app)

- [ ] Neuen LXC erstellen + bootstrappen
- [ ] App deployen auf neuem LXC
- [ ] Caddyfile auf Entry-Point aktualisieren (neue Netbird-IP)

**Ergebnis Phase 5:** Alle drei Deployment-Varianten funktionieren. Cloud-Only, Hybrid und Lokal-Only.

---

## Phase 6: Monitoring, Backup, Wartung

**Ziel:** Produktionsbetrieb absichern.

### 6.1 Monitoring-Rolle (`roles/monitoring/`)

- [ ] Zabbix Server auf Master deployen (Docker Compose)
- [ ] Zabbix Agent Rolle (auf jedem Kunden-Server)
- [ ] TLS-PSK Konfiguration
- [ ] Standard-Checks: CPU, RAM, Disk, Docker, HTTP-Status, Netbird, Backup
- [ ] Health-Checks auf Backend-Ports (nicht öffentliche URL!)

### 6.2 Uptime-Kuma-Rolle (`roles/apps/uptime-kuma/`)

- [ ] Optionale Kunden-App (status.firma.de)
- [ ] Docker Compose Template
- [ ] Hinter Tinyauth

### 6.3 Backup-Rolle (`roles/backup/`)

- [ ] Restic installieren + Repo initialisieren
- [ ] Pre-Backup: DB-Dumps (pg_dump, mysqldump)
- [ ] Backup-Ziele aus Kunden-Inventar (SFTP via Netbird, Storage Box, etc.)
- [ ] Cron-Job für inkrementelle Backups
- [ ] Retention-Policy anwenden
- [ ] Encryption-Key in Vaultwarden speichern

### 6.4 Restore-Playbook

- [ ] `restore.yml` — Snapshot auswählen, App-Daten wiederherstellen
- [ ] `backup-now.yml` — Sofortiges Backup auslösen

### 6.5 Wartungs-Playbooks

- [ ] `update-all.yml` — OS-Updates auf allen Servern eines Kunden
- [ ] `offboard-customer.yml` — Gestuft: Archivieren oder Löschen

**Ergebnis Phase 6:** Automatische Backups, zentrales Monitoring, Restore-Fähigkeit, Offboarding.

---

## Phase 7: Hardening, Docs, Public-Readiness

**Ziel:** Repo ist production-ready und kann public gehen.

### 7.1 Weitere App-Rollen (nach Bedarf)

- [ ] Documenso, Pingvin Share, HedgeDoc, Outline, Gitea, Cal.com, Listmonk
- [ ] Jede App nach `new-app-checklist.md`

### 7.2 Dokumentation vervollständigen

- [x] `docs/SETUP.md` — Master-Server Setup Anleitung
- [x] `docs/ONBOARDING.md` — Neukunden-Prozess Schritt für Schritt
- [x] `docs/APP-DEVELOPMENT.md` — Wie man eine neue App-Rolle erstellt
- [x] `docs/TROUBLESHOOTING.md` — Bekannte Probleme + Lösungen
- [x] `README.md` — Englisch, Quick Start, Architektur-Überblick
- [x] `docs/SEMAPHORE.md` — Semaphore-Templates pro Kunde

### 7.3 Security-Review

- [x] Keine Secrets im Repo (grep nach Passwörtern, Tokens, Keys)
- [x] Alle .env-Dateien chmod 600
- [x] UFW-Regeln korrekt auf allen Server-Rollen
- [x] Fail2ban aktiv
- [x] SSH Key-Only überall
- [x] `.ansible-lint` + `.yamllint` Konfiguration

### 7.4 Idempotenz-Tests

- [x] Code-Review: Alle Rollen verwenden idempotente Module (state: present, template, file)
- [x] Jede Rolle einzeln testbar mit Tags
- [ ] Jedes Playbook 2x hintereinander ausführen → keine Änderungen beim 2. Lauf (manuell auf Infra testen)

### 7.5 Semaphore-Templates

- [x] Alle Playbooks als Semaphore-Templates dokumentiert (`docs/SEMAPHORE.md`)
- [x] Anleitung: Semaphore-Projekte pro Kunde einrichten

**Ergebnis Phase 7:** Repo ist public-fähig. Dokumentation vollständig. Alles getestet.

---

## Abhängigkeiten & Reihenfolge

```
Phase 1 ──► Phase 2 ──► Phase 3 ──► Phase 4 = MVP
                              │
                              ▼
                         Phase 5 (Proxmox/LXC)
                              │
                              ▼
                         Phase 6 (Monitoring/Backup)
                              │
                              ▼
                         Phase 7 (Polish/Release)
```

**Kritischer Pfad zum MVP:** Phase 1 → 2 → 3 → 4

Phase 5–7 können teilweise parallel bearbeitet werden (z.B. Backup-Rolle während App-Rollen gebaut werden).

---

## Phasen-Zusammenfassung

| Phase | Was | Ergebnis |
|-------|-----|----------|
| **1** | Repo-Skelett + Base-Rolle | Ansible-Projekt funktioniert, Server härten möglich |
| **2** | Master-Server komplett | Admin-Infrastruktur steht (PocketID, Tinyauth, VW, Semaphore) |
| **3** | Kunden-Onboarding Cloud-Only | Erster Kunde mit Auth-Stack, automatisiert |
| **4** | App-Rollen (NC, Paperless, VW) | **MVP: Kompletter Kunde mit Apps** |
| **5** | Proxmox + LXC | Hybrid + Lokal-Only Deployments |
| **6** | Monitoring + Backup | Produktionsbetrieb abgesichert |
| **7** | Docs + Security + Polish | Public-Release-Qualität |
