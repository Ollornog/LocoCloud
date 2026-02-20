# CLAUDE.md — LocoCloud Arbeitsanweisungen

**LocoCloud** — Ansible-basiertes Deployment-System für schlüsselfertige Self-Hosted-Infrastruktur (kleine Firmen, 5–50 MA).
Repo: `github.com/Ollornog/LocoCloud` | Referenz: `docs/KONZEPT.md` | Details: `.claude/rules/`

---

## Repo-Struktur

```
LocoCloud/
├── CLAUDE.md
├── ansible.cfg
├── requirements.yml
├── config/
│   ├── lococloudd.yml           ← GITIGNORED, betreiberspezifisch
│   └── lococloudd.yml.example
├── inventories/
│   ├── master/
│   ├── _template/
│   └── kunde-*/
├── roles/
│   ├── base/                    ← OS-Hardening, Docker, UFW, Fail2ban
│   ├── caddy/                   ← Reverse Proxy
│   ├── pocketid/                ← OIDC Provider
│   ├── tinyauth/                ← Forward Auth
│   ├── netbird-client/          ← VPN
│   ├── monitoring/              ← Zabbix Agent
│   ├── backup/                  ← Restic
│   ├── credentials/             ← Vaultwarden API
│   ├── lxc-create/              ← Proxmox LXC-Erstellung
│   └── apps/
│       ├── _template/
│       ├── nextcloud/
│       ├── paperless/
│       └── ...
├── playbooks/
│   ├── site.yml                 ← Full Deploy
│   ├── setup-master.yml
│   ├── onboard-customer.yml
│   └── ...
├── scripts/
│   └── vault-pass.sh            ← Ansible-Vault-Passwort aus Vaultwarden
├── docs/
│   ├── KONZEPT.md               ← DIE WAHRHEIT (Architektur-Referenz)
│   └── FAHRPLAN.md              ← Implementierungs-Reihenfolge (7 Phasen)
└── .claude/rules/               ← Detail-Regeln für Claude Code
```

---

## Architektur-Essenz

- **Netbird überall.** Jeder LXC eigener Netbird-Client + eigene IP. Keine Proxmox-Bridge.
- **PocketID + Tinyauth pro Kunde.** Eigene Instanzen, kein Sharing. Tinyauth reicht (nur OIDC, kein Brute-Force-Risiko), austauschbar auf Authelia. PocketID REST-API für User/Gruppen/OIDC-Client-Automation via `uri`-Modul.
- **Caddy als Entry-Point.** Default: alles blockiert. Öffentliche Pfade explizit gewhitelistet.
- **Port-Binding:** Entry-Point `127.0.0.1:PORT`, App-LXCs `0.0.0.0:PORT` + UFW auf `wt0`.
- **Secrets:** Ansible Vault für Repo-Encryption, Vaultwarden als Credential-Store. `community.general.bitwarden` Lookup-Plugin für Laufzeit-Secrets. `scripts/vault-pass.sh` holt Vault-Passwort aus Vaultwarden.
- **Backup:** Restic über SFTP (via Netbird oder direkt). Ziel dynamisch pro Kunde konfigurierbar.
- **Deployment-Varianten:** Cloud-Only (Hetzner), Hybrid (Hetzner + Proxmox), Lokal-Only (Proxmox + Gateway-LXC).
- **Monitoring:** Zabbix auf Master (Infra). Uptime Kuma optional pro Kunde (`status.firma.de`).
- **DynDNS (Lokal-Only):** Master-Server (Hetzner) übernimmt DNS-Updates für lokale Kunden.
- **Admin sudo:** NOPASSWD — SSH nur über Netbird + Key-Only.
- **Admin-Infra:** `*.loco.ollornog.de` → Caddy auf Hetzner (46.225.165.213) → Netbird → Master-LXC.

---

## Commands

```bash
# Playbook ausführen
ansible-playbook playbooks/site.yml -i inventories/kunde-abc/

# Globale Config wird per pre_tasks geladen:
pre_tasks:
  - include_vars:
      file: "{{ playbook_dir }}/../config/lococloudd.yml"
      name: loco

# Neuer Kunde
bash scripts/new-customer.sh kunde-abc "Firma ABC" "firma-abc.de" "hybrid"

# Ansible Vault (Passwort kommt automatisch via vault-pass.sh)
ansible-vault encrypt inventories/kunde-abc/group_vars/vault.yml
```

---

## Harte Regeln

1. **`docs/KONZEPT.md` ist die Wahrheit.** Abweichung → Konzept zuerst aktualisieren.
2. **Kein Müll.** Nach jedem Task: Testdateien, Debug-Output, auskommentierter Code → weg.
3. **Doku pflegen.** Jede Architektur-Änderung → KONZEPT.md + zugehörige Doku.
4. **Diese Datei pflegen.** Neue Rollen → Baum updaten. Gelöste Entscheidungen → aufnehmen.
5. **Repo public-fähig.** Keine hardcodierten Domains, E-Mails, IPs, Passwörter. Alles über Config/Inventar.

---

## Detail-Regeln (in `.claude/rules/`)

| Datei | Inhalt |
|-------|--------|
| `coding-standards.md` | Ansible, Jinja2, Docker Compose, Caddyfile, Secrets |
| `known-issues.md` | Bekannte Fallstricke + Lösungen |
| `documentation.md` | Wann wird was wo dokumentiert |
| `cleanup.md` | Aufräum-Regeln, verbotene Zustände |
| `new-app-checklist.md` | Checkliste für neue App-Rollen |
