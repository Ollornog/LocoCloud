# CLAUDE.md — LocoCloud Arbeitsanweisungen

**LocoCloud** — Ansible-basiertes Deployment-System für schlüsselfertige Self-Hosted-Infrastruktur (kleine Firmen, 5–50 MA).
Repo: `github.com/Ollornog/LocoCloud` | Referenz: `docs/KONZEPT.md` | Details: `.claude/rules/`

---

## Repo-Struktur

```
LocoCloud/
├── Claude.md
├── ansible.cfg
├── requirements.yml
├── config/
│   ├── lococloudd.yml           ← GITIGNORED, betreiberspezifisch
│   └── lococloudd.yml.example
├── inventories/
│   ├── master/
│   ├── _template/
│   └── kunde-*/
├── .ansible-lint                  ← Lint-Konfiguration
├── .yamllint                      ← YAML-Lint-Konfiguration
├── roles/
│   ├── base/                    ✓ OS-Hardening, Docker, UFW, Fail2ban
│   ├── caddy/                   ✓ Reverse Proxy (master + customer Caddyfile)
│   ├── pocketid/                ✓ OIDC Provider
│   ├── tinyauth/                ✓ Forward Auth (+ OIDC-Registration)
│   ├── netbird_client/          ✓ VPN (install + join, optional)
│   ├── gocryptfs/               ✓ Verschlüsselung /mnt/data + Auto-Mount
│   ├── grafana_stack/           ✓ Grafana + Prometheus + Loki (Master)
│   ├── alloy/                   ✓ Grafana Alloy Agent (Kundenserver)
│   ├── baserow/                 ✓ Berechtigungskonzept (Master)
│   ├── credentials/             ✓ Vaultwarden API (store + folders)
│   ├── backup/                  ✓ Restic + Pre-Backup-Hooks + Restore-Tests
│   ├── key_backup/              ✓ gocryptfs Key-Backup Server
│   ├── compliance/              ✓ TOM, VVT, Löschkonzept (Jinja2-Templates)
│   ├── watchtower/              ✓ Auto-Update (nur Kunden-Apps)
│   ├── lxc_create/              ✓ Proxmox LXC-Erstellung + Bootstrap
│   ├── monitoring/              ✓ Wrapper → delegiert an alloy
│   └── apps/
│       ├── _template/           ✓ Kopiervorlage für neue Apps
│       ├── vaultwarden/         ✓ Credential Manager
│       ├── semaphore/           ✓ Ansible Web-UI
│       ├── nextcloud/           ✓ Cloud Storage (MariaDB + Redis)
│       ├── paperless/           ✓ Dokumenten-Management (PostgreSQL)
│       ├── stirling_pdf/        ✓ PDF-Tool
│       ├── uptime_kuma/         ✓ Status-Page
│       ├── documenso/           ✓ Digitale Signaturen (PostgreSQL)
│       ├── pingvin_share/       ✓ File Sharing
│       ├── hedgedoc/            ✓ Collaborative Markdown (PostgreSQL)
│       ├── outline/             ✓ Wiki/Knowledge Base (PostgreSQL + Redis)
│       ├── gitea/               ✓ Git Hosting (PostgreSQL)
│       ├── calcom/              ✓ Terminplanung (PostgreSQL)
│       └── listmonk/            ✓ Newsletter/Mailing (PostgreSQL)
├── playbooks/
│   ├── setup-master.yml         ← Master-Server einrichten (inkl. Grafana Stack, Baserow)
│   ├── onboard-customer.yml     ← Neukunden-Onboarding (Auth + gocryptfs + Alloy + Compliance)
│   ├── add-server.yml           ← Frischen Server zum Kunden hinzufügen (IP/User/Pass)
│   ├── site.yml                 ← Full Deploy (idempotent)
│   ├── add-app.yml              ← App hinzufügen
│   ├── remove-app.yml           ← App entfernen (archivieren)
│   ├── update-app.yml           ← App aktualisieren (Image pull + recreate)
│   ├── update-caddy.yml         ← Caddy-Konfiguration regenerieren
│   ├── add-user.yml             ← Benutzer anlegen
│   ├── remove-user.yml          ← Benutzer entfernen
│   ├── update-all.yml           ← OS-Updates
│   ├── backup-now.yml           ← Sofort-Backup
│   ├── restore.yml              ← Restore aus Backup
│   ├── restore-test.yml         ← Monatlicher Restore-Test
│   ├── generate-docs.yml        ← Compliance-Dokumente regenerieren
│   └── offboard-customer.yml    ← Kunden-Offboarding
├── scripts/
│   ├── vault-pass.sh            ← Ansible-Vault-Passwort aus Vaultwarden
│   ├── new-customer.sh          ← Kunden-Inventar aus Template generieren
│   ├── pre-backup.sh            ← DB-Dumps vor Restic-Backup
│   └── gocryptfs-mount.sh       ← Auto-Mount nach Reboot
├── docs/
│   ├── KONZEPT.md               ← DIE WAHRHEIT (Architektur-Referenz, v5.0)
│   ├── FAHRPLAN.md              ← Implementierungs-Reihenfolge
│   ├── SETUP.md                 ← Master-Server Setup-Anleitung
│   ├── ONBOARDING.md            ← Neukunden-Prozess Schritt für Schritt
│   ├── APP-DEVELOPMENT.md       ← Neue App-Rolle erstellen
│   ├── TROUBLESHOOTING.md       ← Bekannte Probleme + Lösungen
│   └── SEMAPHORE.md             ← Semaphore-Templates pro Kunde
└── .claude/rules/               ← Detail-Regeln für Claude Code
```

---

## Architektur-Essenz

- **Master zuerst.** Immer Master-Server installieren (alle Tools), dann Kunden hinzufügen, dann Server, dann Apps.
- **Netbird optional.** Netbird-Client auf Master und Kundenservern ist optional. Server können auch direkt per IP erreichbar sein.
- **PocketID + Tinyauth pro Kunde.** Eigene Instanzen, kein Sharing. PocketID REST-API für Automation.
- **Caddy als Entry-Point.** Default: alles blockiert. Öffentliche Pfade explizit gewhitelistet.
- **gocryptfs auf /mnt/data.** Jeder Kundenserver verschlüsselt. Keyfile nur auf Master + Key-Backup.
- **Grafana Stack statt Zabbix.** Grafana + Prometheus + Loki auf Master. Alloy als einziger Agent auf Kundenservern.
- **Baserow für Berechtigungskonzept.** Pro Kunde eine Tabelle: wer darf was.
- **Secrets:** Ansible Vault für Repo-Encryption, Vaultwarden als Credential-Store. `scripts/vault-pass.sh` holt Vault-Passwort.
- **Backup:** Restic + Pre-Backup-Hooks (DB-Dumps) + monatliche Restore-Tests. Ohne Backup-Ziel = kein Backup.
- **Server-Rollen:** `master`, `netbird_server`, `gateway`, `customer_master`, `app_server`, `backup_server`, `key_backup`, `proxmox`.
- **Compliance by Design.** TOM, VVT, Löschkonzept als Jinja2-Templates pro Kunde automatisch generiert.
- **DSGVO/GoBD-konforme Logs.** Loki 6 Monate Retention, journald FSS Sealing, automatische Löschung.
- **Server-Onboarding:** Frische Server mit IP/User/Passwort. Ansible bootstrappt alles (SSH-Key, base, gocryptfs, Alloy).
- **Port-Binding:** Entry-Point `127.0.0.1:PORT`, App-LXCs `0.0.0.0:PORT` + UFW auf `wt0`.
- **Admin-Infra:** `*.admin.example.com` → Caddy → Master (Grafana, Baserow, Semaphore, Vaultwarden, PocketID).

---

## Betriebsablauf

```
1. Master installieren    → setup-master.yml (Grafana Stack, Baserow, Vaultwarden, Semaphore, Auth)
2. Kunde hinzufügen       → scripts/new-customer.sh (Inventar aus Template)
3. Server hinzufügen      → add-server.yml (IP/User/Pass → Bootstrap: SSH-Key, base, gocryptfs, Alloy)
4. Apps konfigurieren     → Inventar editieren (Serverrolle, Apps, Backup-Ziel)
5. Deployment             → onboard-customer.yml (Auth + Apps + Monitoring + Backup + Compliance-Docs)
```

---

## Commands

```bash
# Master einrichten
ansible-playbook playbooks/setup-master.yml -i inventories/master/

# Neuer Kunde
bash scripts/new-customer.sh kunde-abc "Firma ABC" "firma-abc.de"

# Server zum Kunden hinzufügen
ansible-playbook playbooks/add-server.yml -i inventories/kunde-abc/ \
  -e "server_ip=203.0.113.10 server_user=root server_pass=xxx server_name=hauptserver"

# Full Deploy
ansible-playbook playbooks/site.yml -i inventories/kunde-abc/

# Compliance-Dokumente regenerieren
ansible-playbook playbooks/generate-docs.yml -i inventories/kunde-abc/

# Restore-Test manuell
ansible-playbook playbooks/restore-test.yml -i inventories/kunde-abc/
```

---

## Harte Regeln

1. **`docs/KONZEPT.md` ist die Wahrheit.** Abweichung → Konzept zuerst aktualisieren.
2. **Kein Müll.** Nach jedem Task: Testdateien, Debug-Output, auskommentierter Code → weg.
3. **Doku pflegen.** Jede Architektur-Änderung → KONZEPT.md + zugehörige Doku.
4. **Diese Datei pflegen.** Neue Rollen → Baum updaten. Gelöste Entscheidungen → aufnehmen.
5. **Repo public-fähig.** Keine hardcodierten Domains, E-Mails, IPs, Passwörter. Alles über Config/Inventar.
6. **Daten in /mnt/data/.** Alle App-Daten auf Kundenservern in `/mnt/data/` (gocryptfs-geschützt).

---

## Detail-Regeln (in `.claude/rules/`)

| Datei | Inhalt |
|-------|--------|
| `coding-standards.md` | Ansible, Jinja2, Docker Compose, Caddyfile, Secrets |
| `known-issues.md` | Bekannte Fallstricke + Lösungen |
| `documentation.md` | Wann wird was wo dokumentiert |
| `cleanup.md` | Aufräum-Regeln, verbotene Zustände |
| `new-app-checklist.md` | Checkliste für neue App-Rollen |
