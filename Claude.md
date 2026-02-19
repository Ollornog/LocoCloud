# CLAUDE.md — Arbeitsanweisungen für Claude Code

> Diese Datei ist die zentrale Kontextdatei für Claude Code im LocoCloud-Repository.
> Sie wird bei jeder Sitzung automatisch gelesen und MUSS aktuell gehalten werden.

---

## Projekt-Überblick

**LocoCloud** ist ein Ansible-basiertes Deployment-System für schlüsselfertige Self-Hosted-Infrastruktur für kleine Firmen (5–50 Mitarbeiter). Das Repo wird auf einem Master-Server geklont und deployt von dort aus Kunden-Infrastrukturen.

- **Repo:** `github.com/Ollornog/LocoCloud` (privat, Ziel: public)
- **Sprache:** Ansible (YAML/Jinja2), Bash, Caddyfile, Docker Compose
- **Konzept-Dokument:** `docs/KONZEPT.md` — DAS Referenzdokument. Lies es bei Unklarheiten.
- **Betreiber:** Daniel (ollornog.de)

---

## Goldene Regeln

1. **Konzept-Dokument ist die Wahrheit.** Jede Implementierung muss konform zu `docs/KONZEPT.md` sein. Wenn du abweichst, MUSS das Konzept zuerst aktualisiert werden.
2. **Kein Müll.** Nach jedem Task: Testdateien löschen, Debug-Output entfernen, temporäre Dateien aufräumen, auskommentierter Code raus.
3. **Dokumentation ist Pflicht.** Jede Änderung an Rollen, Playbooks oder Architektur wird in der zugehörigen Doku reflektiert.
4. **Diese Datei pflegen.** Wenn sich das Projekt weiterentwickelt (neue Rollen, geänderte Architektur, gelöste Entscheidungen), wird diese CLAUDE.md aktualisiert.
5. **Repo muss public-fähig bleiben.** Keine hardcodierten Domains, E-Mails, IPs, Passwörter. Alles über `config/lococloudd.yml` oder Inventar-Variablen.

---

## Repo-Struktur

```
LocoCloud/
├── CLAUDE.md                    ← DU BIST HIER
├── README.md
├── LICENSE
├── .gitignore
├── ansible.cfg
├── requirements.yml
├── config/
│   ├── lococloudd.yml           ← GITIGNORED, betreiberspezifisch
│   └── lococloudd.yml.example   ← Committed, Template
├── inventories/
│   ├── master/                  ← Master-Server
│   ├── _template/               ← Template für neue Kunden
│   └── kunde-*/                 ← Pro Kunde
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
│       ├── _template/           ← Basis für neue App-Rollen
│       ├── nextcloud/
│       ├── paperless/
│       └── ...
├── playbooks/
│   ├── site.yml                 ← Full Deploy
│   ├── setup-master.yml         ← Master-Setup
│   ├── add-app.yml
│   ├── remove-app.yml
│   └── ...
├── scripts/
└── docs/
    ├── KONZEPT.md               ← Architektur-Referenz (die Wahrheit)
    ├── SETUP.md
    ├── ONBOARDING.md
    ├── APP-DEVELOPMENT.md
    └── TROUBLESHOOTING.md
```

---

## Architektur-Kurzreferenz

Lies `docs/KONZEPT.md` für die vollständige Architektur. Hier die Essenz:

### Trennung Privat vs. LocoCloud

Daniels privates Setup (ollornog.de) und LocoCloud sind **komplett getrennt**. Einziger Berührungspunkt: Der Netbird-Manager (`netbird.ollornog.de`), isoliert über Gruppen/Policies.

LocoCloud hat EIGENE Instanzen von: PocketID, Tinyauth, Vaultwarden, Caddy, Semaphore, Zabbix — alles auf dem Master-Server unter `*.loco.ollornog.de`.

### Deployment-Varianten

| Variante | Entry-Point | App-Server |
|----------|-------------|------------|
| Cloud-Only | Hetzner vServer | Selber Hetzner |
| Hybrid | Hetzner vServer | Proxmox-LXCs beim Kunden (via Netbird) |
| Lokal-Only | Gateway-LXC auf Proxmox | Weitere LXCs auf Proxmox (via Netbird) |

### Netzwerk-Prinzip

- **Netbird überall.** Jeder LXC hat seinen eigenen Netbird-Client und eigene Netbird-IP.
- **Keine Proxmox-Bridge** für Inter-LXC-Kommunikation. Alles über Netbird.
- **Kunden-Hetzner ist der Gateway** (bei Hybrid/Cloud). Caddy dort routet über Netbird an App-LXCs.
- **Kein TLS auf App-LXCs** — Netbird-Tunnel ist WireGuard-verschlüsselt.

### Auth-Stack

- **PocketID** = OIDC-Provider (SSO, Passkeys). Eigene Instanz pro Kunde.
- **Tinyauth** = Forward-Auth-Proxy. Sitzt vor Caddy, prüft Auth.
- **Default: ALLES blockiert.** Öffentliche Pfade werden explizit gewhitelistet.

### Port-Binding

- **Entry-Point-Server** (Hetzner, Gateway-LXC): Docker bindet auf `127.0.0.1:PORT`
- **App-LXCs** (remote, per Netbird erreichbar): Docker bindet auf `0.0.0.0:PORT`, UFW sichert ab (App-Port nur auf `wt0`)

---

## Coding-Standards

### Ansible

- **Idempotenz ist Pflicht.** Jeder Task muss mehrfach ausführbar sein ohne Seiteneffekte. `state: present` statt `command: apt install`.
- **`docker compose` (V2 Plugin)**, NICHT `docker-compose` (V1 deprecated).
- **Keine rohen `command`/`shell`-Aufrufe** wenn ein Ansible-Modul existiert.
- **Handler-Pattern:** Änderung → notify Handler → Handler am Ende des Plays. Wenn sofort nötig: `meta: flush_handlers`.
- **Variablen-Herkunft:** Alles aus `config/lococloudd.yml` (global), `group_vars/all.yml` (pro Kunde), oder `defaults/main.yml` (pro Rolle). Niemals hardcoden.
- **Globale Config laden:** In jedem Playbook als `pre_tasks`:
  ```yaml
  pre_tasks:
    - name: Load global config
      include_vars:
        file: "{{ playbook_dir }}/../config/lococloudd.yml"
        name: loco
  ```
- **Tags verwenden** für granulare Ausführung: `tags: [base, hardening]`, `tags: [caddy, config]`, etc.

### Jinja2-Templates

- **Header in generierten Dateien:**
  ```
  # ============================================
  # GENERIERT DURCH ANSIBLE — NICHT MANUELL EDITIEREN
  # Kunde: {{ kunde_name }} ({{ kunde_domain }})
  # Generiert: {{ ansible_date_time.iso8601 }}
  # ============================================
  ```
- **Keine Logik in Templates** die in Rollen gehört. Templates rendern nur Variablen.

### Docker Compose

- **Immer `restart: unless-stopped`**
- **Immer expliziter `container_name`**
- **Port-Binding:** Siehe Port-Binding-Regeln oben (127.0.0.1 vs. 0.0.0.0 je nach Server-Rolle)
- **Volumes:** Explizite Host-Pfade, keine anonymen Volumes.
- **PostgreSQL 18:** Mount auf `/var/lib/postgresql` (NICHT `/var/lib/postgresql/data`)
- **.env-Dateien:** `chmod 600`

### Caddyfile

- **`import public`** auf jeder Domain (Security Headers)
- **`import auth`** als Default auf jedem geschützten Pfad
- **Öffentliche Pfade:** Spezifische `handle @matcher`-Blöcke VOR dem Fallback `handle {}`
- **CSP:** Nur für Apps OHNE eigenen CSP setzen. Vaultwarden, Nextcloud, PocketID, Paperless setzen ihren eigenen.
- **Nach Änderungen:** `docker restart caddy` (NICHT `caddy reload` — Inode-Problem bei Bind-Mounts)

### Secrets

- **NIEMALS Klartext in Git.** Weder in Variablen, noch in Kommentaren, noch in Beispielen.
- **`config/lococloudd.yml`** ist in `.gitignore` — nur `.example` wird committed.
- **Kunden-Secrets:** Ansible Vault (`group_vars/vault.yml`) oder Vaultwarden-API.
- **Generierte Passwörter:** `lookup('password', '/dev/null chars=ascii_letters,digits length=32')`
- **Alles in Vaultwarden speichern** über die `credentials`-Rolle.

---

## Bekannte Fallstricke

Diese Probleme sind aus dem Betrieb bekannt. IMMER beachten:

| Problem | Lösung |
|---------|--------|
| nano erstellt neuen Inode | `docker restart caddy` statt `caddy reload`. Ansible-Handler nutzen. |
| PostgreSQL 18 Mount-Pfad | `/var/lib/postgresql` NICHT `/var/lib/postgresql/data` |
| LXC Kernel-Parameter | `is_lxc`-Variable prüfen. In LXC: nur netzwerk-sysctl, kein `kernel.*`, `fs.*` |
| Nextcloud HSTS-Warning | Apache im Container setzt Header selbst via Volume-Mount `security.conf` |
| Nextcloud Single Logout | `--send-id-token-hint=0` in user_oidc setzen |
| Paperless ESC-Registrierung | `PAPERLESS_ACCOUNT_ALLOW_SIGNUPS: false` explizit setzen! |
| Caddy handle-Reihenfolge | Spezifische Matcher VOR Fallback `handle {}`. Sonst blockt Auth public Pfade. |
| PocketID /register | Per Caddy auf 403 blocken. PocketID kann Registrierung nicht nativ deaktivieren. |
| USB in LXC | NICHT deaktivieren in LXC (existiert nicht). `is_lxc`-Check. |
| Netbird DNS Konflikte | Custom DNS Zones NUR für interne Domains. Öffentliche Domains NICHT eintragen. |
| Tinyauth nicht prod-ready | Monitoring eng halten, Fallback-Plan auf Authelia dokumentiert. |
| Docker UFW-Bypass | Docker umgeht UFW standardmäßig! Für App-LXCs mit `0.0.0.0`-Bind: `DOCKER_IPTABLES=false` prüfen oder UFW-Docker-Integration nutzen. |

---

## Dokumentations-Pflichten

### Wann wird was dokumentiert

| Ereignis | Zu aktualisierende Datei(en) |
|----------|------------------------------|
| Neue Ansible-Rolle erstellt | `docs/APP-DEVELOPMENT.md`, Rolle `defaults/main.yml` mit Kommentaren |
| Architektur-Änderung | `docs/KONZEPT.md`, diese `CLAUDE.md` |
| Neues bekanntes Problem | `docs/TROUBLESHOOTING.md`, Fallstricke-Tabelle in dieser `CLAUDE.md` |
| Offene Entscheidung getroffen | `docs/KONZEPT.md` Kapitel 21 aktualisieren, Entscheidung als gelöst markieren |
| Neue Konfigurationsoption | `config/lococloudd.yml.example` aktualisieren |
| Playbook hinzugefügt/geändert | `docs/SETUP.md` oder `docs/ONBOARDING.md` je nach Kontext |
| Security-Änderung | `docs/KONZEPT.md` Kapitel 16, diese `CLAUDE.md` Fallstricke-Tabelle |

### Dokumentations-Format

- **Deutsch** für alle Projektdokumentation (Konzept, Troubleshooting, Onboarding)
- **Englisch** für `README.md` und Code-Kommentare (Repo soll public-fähig sein)
- **Inline-Kommentare in YAML:** Kurz, erklären das WARUM, nicht das WAS
- **Keine TODO-Kommentare** im Code lassen. Wenn etwas offen ist → in `docs/KONZEPT.md` Kapitel 21 oder als GitHub Issue

---

## Aufräum-Regeln

### Nach jedem Task

- [ ] Temporäre Testdateien gelöscht (keine `test.yml`, `debug.yml`, `tmp_*` etc.)
- [ ] Debug-Tasks entfernt (`debug: msg=...` die nur zum Testen waren)
- [ ] Auskommentierter Code entfernt (kein `# - name: old task that we dont use`)
- [ ] Keine leeren Dateien oder Platzhalter-Verzeichnisse ohne Inhalt
- [ ] Keine doppelten/widersprüchlichen Konfigurationen

### Nach Fehlerbehebung

- [ ] Workaround dokumentiert in `docs/TROUBLESHOOTING.md`
- [ ] Falls Architektur-relevant: `docs/KONZEPT.md` aktualisiert
- [ ] Falls neuer Fallstrick: Diese `CLAUDE.md` Fallstricke-Tabelle aktualisiert
- [ ] Temporäre Fix-Versuche entfernt (keine `_backup`, `_old`, `_fix` Dateien)
- [ ] Git-History sauber: Aussagekräftige Commit-Messages, kein "test", "fix", "wip"

### Nach Konzeptänderung

- [ ] `docs/KONZEPT.md` ist die ERSTE Datei die geändert wird
- [ ] Alle betroffenen Rollen/Playbooks/Templates angepasst
- [ ] `config/lococloudd.yml.example` aktualisiert falls neue Config-Optionen
- [ ] Diese `CLAUDE.md` aktualisiert (Architektur-Kurzreferenz, Fallstricke)
- [ ] Inventar-Templates (`inventories/_template/`) aktualisiert
- [ ] Keine verwaisten Referenzen auf alte Konzepte/Variablen/Dateien

### Verbotene Zustände

- **Keine Dateien mit `_old`, `_backup`, `_test`, `_tmp`, `_copy` Suffix** im Repo
- **Keine `*.bak` Dateien**
- **Keine leeren `__init__.py` oder Platzhalter** die keinen Zweck erfüllen
- **Kein auskommentierter Code** der "für später" aufgehoben wird
- **Keine hardcodierten Werte** die in Config/Inventar gehören
- **Kein `ansible_host: 10.10.0.x`** (alte Proxmox-Bridge-IPs) — alles ist Netbird

---

## Pflege dieser Datei

### Wann diese CLAUDE.md aktualisiert werden MUSS

1. **Neue Rolle erstellt** → Repo-Struktur-Baum aktualisieren
2. **Architektur-Entscheidung getroffen** → Architektur-Kurzreferenz aktualisieren
3. **Neuer Fallstrick entdeckt** → Fallstricke-Tabelle erweitern
4. **Coding-Standard geändert** → Coding-Standards-Sektion aktualisieren
5. **Offene Entscheidung gelöst** → Aus Konzept entfernen, hier als feste Regel aufnehmen
6. **Neue Datei/Ordner die Claude kennen muss** → Repo-Struktur aktualisieren

### Format-Regeln für diese Datei

- Maximal **eine Scrollseite** pro Sektion — wenn es länger wird, gehört es in `docs/`
- **Tabellen** für Referenz-Material (Fallstricke, Doku-Pflichten)
- **Codeblöcke** nur für das Nötigste — vollständige Beispiele gehören ins Konzept oder in `docs/`
- **Keine Redundanz** mit `docs/KONZEPT.md` — hier steht die Kurzreferenz, dort die Details

---

## Offene Entscheidungen

> Sobald eine Entscheidung getroffen wird, wird sie aus dieser Liste entfernt und als feste Regel in die entsprechende Sektion oben aufgenommen.

| Frage | Optionen | Status |
|-------|----------|--------|
| Öffentliche IP für `*.loco.ollornog.de` | A) Route über privaten Hetzner, B) Neuer Hetzner | OFFEN |
| Tinyauth vs. Authelia | Tinyauth für Start, Authelia als Fallback | Tinyauth gewählt, beobachten |
| PocketID User-Management | Manuell UI vs. API | OFFEN — API-Fähigkeiten prüfen |
| Backup Off-Site Ziel | Hetzner Storage Box vs. BorgBase | OFFEN |
| Ansible Vault vs. Vaultwarden für Secrets | Vaultwarden primär, Vault als Fallback | OFFEN |

---

## Checkliste: Neue App-Rolle

Wenn eine neue App als Ansible-Rolle implementiert wird:

- [ ] `roles/apps/<appname>/defaults/main.yml` mit allen Variablen + Kommentaren
- [ ] `roles/apps/<appname>/templates/docker-compose.yml.j2` — Port-Binding je nach Server-Rolle
- [ ] `roles/apps/<appname>/templates/env.j2` — Secrets als Variablen
- [ ] `roles/apps/<appname>/tasks/deploy.yml` — idempotent
- [ ] `roles/apps/<appname>/tasks/oidc.yml` — OIDC-Client in PocketID registrieren (wenn unterstützt)
- [ ] `roles/apps/<appname>/tasks/remove.yml` — Daten archivieren, nicht löschen
- [ ] `roles/apps/<appname>/handlers/main.yml` — `docker restart caddy`
- [ ] Public Paths definiert (oder leer = komplett geschützt)
- [ ] Backup-Pfade definiert
- [ ] Health-Check definiert (Port + Path für Monitoring)
- [ ] Credentials über `credentials`-Rolle in Vaultwarden gespeichert
- [ ] PostgreSQL 18: Mount auf `/var/lib/postgresql`
- [ ] Redis: DB-Nummer zugewiesen (bei `single_lxc`) oder eigener Container (bei `lxc_per_app`)
- [ ] CSP: Nur setzen wenn App keinen eigenen hat
- [ ] Keine hardcodierten Domains/E-Mails
- [ ] Idempotenz getestet (Playbook 2x laufen lassen)
- [ ] `docs/APP-DEVELOPMENT.md` aktualisiert
- [ ] Repo-Struktur in dieser `CLAUDE.md` aktualisiert
