# LocoCloud — Managed Self-Hosted Infrastructure

## Konzept & Bauplan für das GitHub-Repository

**Repo:** `github.com/Ollornog/LocoCloud`
**Version:** 5.0 — Februar 2026

---

## Inhaltsverzeichnis

1. [Systemübersicht & Philosophie](#1-systemübersicht--philosophie)
2. [Server-Rollen & Architektur](#2-server-rollen--architektur)
3. [Admin-Infrastruktur (Master-Server)](#3-admin-infrastruktur-master-server)
4. [Deployment-Szenarien](#4-deployment-szenarien)
5. [Isolation: Docker vs. LXC pro App](#5-isolation-docker-vs-lxc-pro-app)
6. [Netzwerk-Architektur (Netbird)](#6-netzwerk-architektur-netbird)
7. [Authentifizierung & Autorisierung](#7-authentifizierung--autorisierung)
8. [Caddy Reverse Proxy System](#8-caddy-reverse-proxy-system)
9. [App-Template-System](#9-app-template-system)
10. [Credential-Management (Vaultwarden)](#10-credential-management-vaultwarden)
11. [Backup-Architektur](#11-backup-architektur)
12. [Verschlüsselung (gocryptfs)](#12-verschlüsselung-gocryptfs)
13. [Monitoring, Logging & Alerting (Grafana Stack)](#13-monitoring-logging--alerting-grafana-stack)
14. [Compliance & Dokumentation (DSGVO/GoBD)](#14-compliance--dokumentation-dsgvogobd)
15. [Repo-Struktur & Konfiguration](#15-repo-struktur--konfiguration)
16. [Semaphore-Konfiguration](#16-semaphore-konfiguration)
17. [Deployment-Abläufe](#17-deployment-abläufe)
18. [Sicherheits-Hardening](#18-sicherheits-hardening)
19. [Wartung & Updates](#19-wartung--updates)
20. [Kunden-Inventar-System](#20-kunden-inventar-system)
21. [Repo Public-Readiness](#21-repo-public-readiness)
22. [Bekannte Fallstricke & Lessons Learned](#22-bekannte-fallstricke--lessons-learned)
23. [Offene Design-Entscheidungen](#23-offene-design-entscheidungen)

---

## 1. Systemübersicht & Philosophie

### Was LocoCloud ist

Ein Ansible-basiertes Deployment-System in einem Git-Repository, das schlüsselfertige Self-Hosted-Infrastruktur für kleine Firmen (5–50 Mitarbeiter) bereitstellt. Das Repo wird auf einem Master-Server geklont und von dort aus werden beliebig viele Kunden-Infrastrukturen deployt, gewartet und überwacht.

### Kernprinzipien

1. **Alles ist öffentlich erreichbar** — Kein VPN für Endbenutzer, nur Browser nötig
2. **Alles ist hinter Auth** — Default: blockiert. Öffentliche Pfade werden explizit gewhitelistet
3. **PocketID + Tinyauth pro Kunde** — Eigene Instanzen, kein Sharing zwischen Kunden
4. **Netbird nur für Admin & Infrastruktur** — Endbenutzer bekommen kein VPN (Netbird ist optional bei der Master-Installation)
5. **Ein Repo, viele Kunden** — Monorepo mit Inventar-Trennung
6. **Credentials automatisch in Vaultwarden** — Bei jedem Deploy/Update
7. **Der Betreiber ist überall Admin** — PocketID-Admin auf jeder Kundeninstanz
8. **Kunden vollständig isoliert** — Kein Kunde sieht einen anderen
9. **Repo-Agnostik** — Alles Spezifische (Domain, E-Mail, Netbird-URL) ist konfigurierbar. Das Repo soll public-fähig sein
10. **Daten immer verschlüsselt** — `/mnt/data` auf jedem Kundenserver mit gocryptfs gesichert, Keyfile auf dem Master
11. **Compliance by Design** — TOM-Dokumentation, Verarbeitungsverzeichnis und Löschkonzept als Ansible-Templates pro Kunde
12. **Nachweisbare Sicherheit** — Backup-Restore-Tests monatlich automatisiert, Audit-Logs für alle Apps, zentrale Log-Sammlung

### Was LocoCloud NICHT ist

- Kein SaaS — Jeder Kunde hat eigene Server, eigene Instanzen, eigene Daten
- Kein Shared Hosting — Keine geteilte Infrastruktur zwischen Kunden
- Kein Cloud-Provider — Kunden besitzen ihre Server (oder mieten sie selbst)

---

## 2. Server-Rollen & Architektur

### 2.1 Server-Rollen

LocoCloud definiert folgende Server-Rollen. Jeder Host im Inventar bekommt eine oder mehrere Rollen als Liste (`server_roles`). Rollen können auf einem Host kombiniert werden.

| Rolle | Zweck | Typische Dienste |
|-------|-------|------------------|
| `master` | Betreiber-Administration | Ansible, PocketID, Tinyauth, Vaultwarden, Semaphore, Grafana Stack, Baserow, gocryptfs Key-Store |
| `netbird_server` | VPN-Management (optional, kann extern sein) | Netbird Management + Relay + Signal |
| `gateway` | Öffentlicher Entry-Point pro Kunde | Caddy (TLS-Terminierung), Reverse Proxy |
| `customer_master` | Kunden-Auth & -Verwaltung | PocketID, Tinyauth (+ optional Vaultwarden) |
| `app_server` | Kunden-Applikationen | Nextcloud, Paperless, etc. + Datenbanken |
| `backup_server` | Backup-Ziel | Restic-Repos (übergreifend oder kundenspezifisch) |
| `key_backup` | Backup der gocryptfs-Schlüssel | Redundante Kopie aller Encryption-Keys vom Master |
| `proxmox` | Hypervisor (nur API-Zugang, kein Deployment) | LXC-Erstellung via Proxmox API |

### 2.2 Multi-Role per Host

Ein Host kann mehrere Rollen gleichzeitig haben:

```yaml
# Beispiel: Gateway + Kunden-Auth auf einem Server
server_roles: [gateway, customer_master]

# Beispiel: Alles auf einem Server
server_roles: [gateway, customer_master, app_server]
```

Playbooks prüfen Rollen mit:
```yaml
when: "'gateway' in server_roles"
when: "'customer_master' in server_roles"
```

### 2.3 Hosting-Typ

Jeder Host hat einen `hosting_type`, der bestimmt wo er läuft:

| Typ | Bedeutung |
|-----|-----------|
| `cloud` | Cloud-Server / VPS (eigene öffentliche IP) |
| `proxmox_lxc` | LXC-Container auf einem Proxmox-Host |

### 2.4 Architektur-Übersicht

```
┌─────────────────────────────────────────────────────────────┐
│  Master-Server (Betreiber)                                   │
│  ├── Ansible + Git (LocoCloud-Repo)                          │
│  ├── PocketID (Admin-SSO)                                    │
│  ├── Tinyauth (Admin Forward-Auth)                           │
│  ├── Vaultwarden (Admin-Credentials, alle Kunden)            │
│  ├── Semaphore (Ansible Web-UI)                              │
│  ├── Grafana Stack (Monitoring + Logging + Alerting)         │
│  │   ├── Grafana (Web-UI + Alerting)                         │
│  │   ├── Prometheus (Metriken)                               │
│  │   └── Loki (Logs)                                         │
│  ├── Baserow (Berechtigungskonzept pro Kunde)                │
│  ├── gocryptfs Key-Store (/opt/lococloudd/keys/)             │
│  └── Netbird Client (optional)                               │
│                                                              │
│  Netbird-Server (optional self-hosted oder extern)           │
│  └── Netbird Management + Relay + Signal                     │
│                                                              │
│  Key-Backup-Server (optional, für gocryptfs-Schlüssel)       │
│  └── Redundante Kopie aller Encryption-Keys                  │
│                                                              │
│  Backup-Server(s) (übergreifend oder pro Kunde)              │
│  └── Restic-Repos                                            │
└──────────────────────────────────────────────────────────────┘
           │ Netbird VPN
┌──────────▼──────────────────────────────────────────────────┐
│  Pro Kunde:                                                  │
│                                                              │
│  Gateway-Server (öffentlicher Entry-Point)                   │
│  ├── Caddy (TLS-Terminierung)                                │
│  └── Netbird Client                                          │
│                                                              │
│  Customer-Master-Server (Kunden-Auth)                        │
│  ├── PocketID (Kunden-SSO)                                   │
│  ├── Tinyauth (Kunden Forward-Auth)                          │
│  └── Netbird Client                                          │
│      (oft kombiniert mit Gateway auf einem Host)             │
│                                                              │
│  App-Server(s) (ein oder mehrere)                            │
│  ├── App-Container (Nextcloud, Paperless, etc.)              │
│  ├── Datenbanken                                             │
│  └── Netbird Client                                          │
└──────────────────────────────────────────────────────────────┘
```

> **Gateway und Customer-Master** werden in der Praxis oft auf demselben Host kombiniert (`server_roles: [gateway, customer_master]`). Bei Bedarf können sie aber getrennt werden.

### 2.5 Netbird-Server

Der Netbird-Server kann **extern betrieben** (Default) oder **self-hosted** werden:

- **Extern:** Nur URL + API-Token in `config/lococloudd.yml` konfigurieren. Keine Ansible-Rolle nötig.
- **Self-Hosted:** Optionale Rolle `netbird_server` deployt einen eigenen Netbird-Management-Server. Kann auf dem Master, dem Gateway oder einem eigenen Server laufen.

---

## 3. Admin-Infrastruktur (Master-Server)

### 3.1 Master-Server

Dedizierter Server oder LXC für die Betreiber-Administration.

**Empfohlene Spezifikationen:**
- **OS:** Debian 13 (Trixie), unprivileged LXC mit nesting=1 (oder VM/VPS)
- **RAM:** 8192 MB (Semaphore + Grafana Stack + Baserow + Vaultwarden + PocketID + Ansible)
- **CPU:** 4 Cores
- **Disk:** 64 GB

### 3.2 Dienste auf dem Master

Alle Dienste laufen als Docker Container auf `127.0.0.1`. Caddy terminiert TLS.

| Dienst | Subdomain | Port (intern) | Zweck |
|--------|-----------|---------------|-------|
| Caddy | — | Host Network | Reverse Proxy für alle Admin-Dienste |
| PocketID | id.admin.example.com | 127.0.0.1:1411 | OIDC-Provider für Admin-Dienste |
| Tinyauth | auth.admin.example.com | 127.0.0.1:9090 | Forward-Auth für Admin-Dienste |
| Vaultwarden | vault.admin.example.com | 127.0.0.1:8222 | Credential-Management (alle Kunden) |
| Semaphore | deploy.admin.example.com | 127.0.0.1:3000 | Ansible Web-UI |
| Grafana | grafana.admin.example.com | 127.0.0.1:3100 | Monitoring-Dashboard + Alerting |
| Prometheus | — | 127.0.0.1:9091 | Metriken-Speicherung (intern, kein externer Zugang) |
| Loki | — | 127.0.0.1:3110 | Log-Speicherung (intern, kein externer Zugang) |
| Baserow | permissions.admin.example.com | 127.0.0.1:8231 | Berechtigungskonzept pro Kunde (Tabellen) |
| Ansible | — | — | Direkt installiert (apt/pip) |
| Git | — | — | LocoCloud-Repo (geklont) |
| msmtp | — | — | Alert-Mails |
| Netbird Client | — | — | VPN zu allen Kunden (optional) |

### 3.3 Subdomain-Schema

Alle Admin-Dienste laufen unter einer konfigurierbaren Admin-Subdomain (`admin.subdomain` in `lococloudd.yml`):

```
admin.example.com              → Landingpage / Dashboard (optional)
id.admin.example.com           → PocketID (Admin-SSO)
auth.admin.example.com         → Tinyauth (Admin Forward-Auth)
vault.admin.example.com        → Vaultwarden (Admin-Credentials)
deploy.admin.example.com       → Semaphore (Ansible-UI)
grafana.admin.example.com      → Grafana (Monitoring + Logging + Alerting)
permissions.admin.example.com  → Baserow (Berechtigungskonzept)
```

**DNS-Setup:**
- Wildcard A-Record: `*.admin.example.com → <Gateway-IP>`

**Traffic-Flow:** Der Master muss öffentlich erreichbar sein, entweder direkt (eigene IP) oder über einen Gateway-Server (Caddy leitet via Netbird weiter):

```
Internet → Gateway-Caddy (öffentliche IP) → Netbird → Master-Server
```

### 3.4 TLS für Master-Dienste

- Caddy auf dem öffentlichen Gateway terminiert TLS
- Leitet über Netbird an den Master weiter (HTTP, kein TLS nötig im Tunnel)
- Master-Caddy lauscht auf HTTP und fügt Header hinzu

### 3.5 Repo auf dem Master & Betriebsablauf

Das Repo ist öffentlich auf GitHub. Der Master-Server ist IMMER der erste Schritt — alles beginnt hier.

**Setup-Flow für den Master:**

```bash
# 1. Repo klonen (öffentlich, kein Key nötig für read-only)
git clone https://github.com/YourUser/LocoCloud.git /opt/lococloudd

# 2. Config aus Example erstellen und anpassen
cd /opt/lococloudd
cp config/lococloudd.yml.example config/lococloudd.yml
nano config/lococloudd.yml  # Domain, E-Mail, Tokens ausfüllen

# 3. Master-Inventar anpassen
nano inventories/master/hosts.yml         # Server-IP eintragen
nano inventories/master/group_vars/all.yml  # SSH-Keys, Netbird (optional)

# 4. Vault-Datei für Secrets erstellen
ansible-vault create inventories/master/group_vars/vault.yml

# 5. Setup ausführen (Netbird optional, alle Tools + Grafana Stack + Baserow)
ansible-playbook playbooks/setup-master.yml -i inventories/master/
```

**Danach — Betriebsablauf in 4 Schritten:**

```
Schritt 1: Kunde hinzufügen
  → Input: Kundenadmin-Name, Kunden-URL (Domain)
  → bash scripts/new-customer.sh kunde-abc "Firma ABC" "firma-abc.de"
  → Erzeugt Inventar aus Template

Schritt 2: Server zum Kunden hinzufügen
  → Input: Servername, Beschreibung, IP, User, Passwort
  → Frisch installierte Server (Debian) — kein Netbird/Docker nötig
  → Ansible bootstrappt den Server (base-Rolle, Docker, optional Netbird)

Schritt 3: Serverrolle & App-Auswahl konfigurieren
  → Serverrolle: gateway, app_server, backup_server (oder Kombination)
  → App-Auswahl mit Konfiguration (URL, Subdomains)
  → Backup-Ziel wählen (ohne Ziel = kein Backup)

Schritt 4: Deployment
  → ansible-playbook playbooks/onboard-customer.yml -i inventories/kunde-abc/
  → gocryptfs auf /mnt/data, Keyfile vom Master
  → Apps + Auth + Monitoring + Backup
```

Für Push-Zugriff (Änderungen vom Master aus committen) wird ein Deploy-Key oder SSH-Key benötigt:
```bash
GIT_SSH_COMMAND="ssh -i /root/.ssh/github-deploy-key" git pull origin main
```

Änderungen werden primär lokal gemacht, gepusht, und auf dem Master per `git pull` aktualisiert (manuell oder per Semaphore-Task).

### 3.6 gocryptfs Key-Store auf dem Master

Der Master-Server speichert alle gocryptfs-Schlüsseldateien zentral:

```
/opt/lococloudd/keys/
├── kunde-abc/
│   ├── abc-server.key       ← gocryptfs Keyfile für den Server
│   └── abc-nextcloud.key    ← gocryptfs Keyfile für Nextcloud-LXC
├── kunde-xyz/
│   └── xyz-server.key
└── ...
```

**Zugriffskontrolle:**
- Verzeichnis: `chmod 700 /opt/lococloudd/keys/`
- Dateien: `chmod 600 /opt/lococloudd/keys/**/*.key`
- Nur root auf dem Master hat Zugriff

**Key-Backup:** Siehe Kapitel 12 (Verschlüsselung) für die `key_backup`-Server-Rolle.

### 3.7 Baserow für Berechtigungskonzept

Baserow läuft auf dem Master-Server und dient der dokumentierten Zugriffskontrolle pro Kunde.

**Tabellenstruktur pro Kunde:**

| Spalte | Typ | Beschreibung |
|--------|-----|-------------|
| Benutzer | Text | Name des Mitarbeiters |
| E-Mail | E-Mail | Login-E-Mail (PocketID) |
| Rolle | Single Select | Admin, Standard, Readonly |
| Nextcloud | Boolean | Zugriff ja/nein |
| Paperless | Boolean | Zugriff ja/nein |
| Vaultwarden | Boolean | Zugriff ja/nein |
| Weitere Apps... | Boolean | Zugriff ja/nein |
| Gültig ab | Datum | Start der Berechtigung |
| Gültig bis | Datum | Ende (leer = unbefristet) |
| Anmerkungen | Long Text | Sonderregelungen |

**Zweck:**
- Dokumentiertes Berechtigungskonzept für TOM-Dokumentation
- Nachweis für Behörden (wer darf was)
- Wird bei Kunden-Audits als Referenz verwendet
- Kein automatischer Sync mit PocketID — Baserow ist die Dokumentation, PocketID die Umsetzung

### 3.8 Backup-Server

Dedizierter Server oder LXC für Kunden-Backups. Kann übergreifend oder kundenspezifisch sein.

| Option | Beschreibung |
|--------|-------------|
| Backup-LXC auf Proxmox | Lokales Backup-Ziel auf eigener Hardware |
| Cloud Storage Box | Off-Site-Backup bei einem Provider (z.B. Storage Box) |
| Eigener Cloud-Server | Dedizierter VPS als Backup-Ziel |

Backup-Ziele sind **dynamisch pro Kunde und pro App/Dienst** konfigurierbar. Mehrere Ziele gleichzeitig möglich.

---

## 4. Deployment-Szenarien

Es gibt keine festen "Varianten" mehr. Stattdessen definiert der Betreiber im Inventar frei, welche Server welche Rollen übernehmen. Hier typische Szenarien als Orientierung:

### 4.1 Szenario: Alles auf einem Server

```
Internet (HTTPS)
    │
    ▼
Cloud-Server (firma.de)
    server_roles: [gateway, customer_master, app_server]
    ├── Caddy (TLS, forward_auth → Tinyauth)
    ├── PocketID (id.firma.de)
    ├── Tinyauth (auth.firma.de)
    ├── Alle Apps (Docker Container)
    ├── Alle Datenbanken (Docker Container)
    ├── Netbird Client (Admin-Zugang, optional)
    └── Grafana Alloy Agent
```

**Einfachstes Setup.** Ein Server mit allen Rollen kombiniert.

### 4.2 Szenario: Cloud-Gateway + lokale App-Server

```
Internet (HTTPS)
    │
    ▼
Cloud-Server (firma.de)
    server_roles: [gateway, customer_master]
    ├── Caddy (TLS, forward_auth → Tinyauth)
    ├── PocketID (id.firma.de)
    ├── Tinyauth (auth.firma.de)
    ├── Netbird Client
    │
    │   Netbird VPN Tunnel (WireGuard-verschlüsselt)
    │
    ├──► LXC "nextcloud" (100.x.x.1:8080)   ← Eigener Netbird-Client
    ├──► LXC "paperless" (100.x.x.2:8081)    ← Eigener Netbird-Client
    └──► LXC "vaultwarden" (100.x.x.3:8222)  ← Eigener Netbird-Client
         (alle auf Proxmox beim Kunden)
```

**Kein lokaler Caddy, kein Gateway-LXC, keine Proxmox-Bridge!** Der Gateway-Caddy routet direkt über Netbird an jeden einzelnen App-Server. Jeder hat seinen eigenen Netbird-Client.

**Traffic-Flow:**
1. Mitarbeiter → HTTPS → Gateway-Server
2. Caddy: TLS-Terminierung + `forward_auth` → Tinyauth
3. Lokale Apps: `reverse_proxy` direkt an Netbird-IP des jeweiligen App-Servers
4. Apps auf dem Gateway: `reverse_proxy` auf `127.0.0.1:PORT`

**Kein TLS auf den lokalen Servern nötig!** Caddy auf dem Gateway terminiert TLS, Netbird-Tunnel ist WireGuard-verschlüsselt.

**Bei `single_lxc`-Modus:** Nur ein LXC mit allem, ein Netbird-Client, ein Peer. Gateway-Caddy routet alles an eine einzige Netbird-IP.

### 4.3 Szenario: Komplett lokal

```
Internet (HTTPS)
    │
    ▼
Kunden-Router (Port-Forward 80/443, optional DynDNS)
    │
    ▼
Proxmox beim Kunden
    ├── LXC "gateway"
    │   server_roles: [gateway, customer_master]
    │   ├── Docker: Caddy (TLS via Let's Encrypt)
    │   ├── Docker: PocketID (id.firma.de)
    │   ├── Docker: Tinyauth (auth.firma.de)
    │   └── Netbird Client (100.x.x.0)
    │
    │   Netbird-Tunnel (lokal, trotzdem verschlüsselt)
    │
    ├── LXC "nextcloud"  [app_server] + Netbird (100.x.x.1)
    ├── LXC "paperless"  [app_server] + Netbird (100.x.x.2)
    └── LXC "infra"      [app_server] + Netbird (100.x.x.3)
```

**Voraussetzung:** Feste IP oder DynDNS + Port-Forward. Optional kann der Gateway auch auf einem externen Server laufen.

### 4.4 Der öffentliche Einstiegspunkt

**Immer ist der Host mit der `gateway`-Rolle der Single-Entry-Point.** Der Caddy auf diesem Server routet zu allen anderen Servern über Netbird.

---

## 5. Isolation: Docker vs. LXC pro App

### 5.1 Das Problem

Auf Cloud-Servern (Gateway/All-in-One): **Alles Docker.** Kein Proxmox, kein LXC. Einfach, bewährt.

Auf dem lokalen Proxmox beim Kunden gibt es zwei Ansätze:

### 5.2 Option 1: Ein LXC, alles Docker (wie auf Cloud-Servern)

```
Proxmox
└── LXC "apps" (Debian 13, nesting=1)
    ├── Docker: Nextcloud
    ├── Docker: Paperless
    ├── Docker: MariaDB
    ├── Docker: PostgreSQL
    ├── Docker: Redis
    └── Netbird Client (100.114.x.1)
```

**Vorteile:**
- Einheitlich mit Cloud-Server-Setup (selbe Ansible-Rollen)
- Einfacheres Ansible (ein Host = ein Inventar-Eintrag)
- Docker Compose verwaltet Abhängigkeiten
- Nur ein Netbird-Peer nötig

**Nachteile:**
- Weniger Isolation zwischen Apps
- Ein kompromittierter Container kann potenziell auf andere zugreifen
- Resource-Limits nur über Docker (weniger granular als LXC)

### 5.3 Option 2: LXC pro App (bessere Isolation) — Empfohlen

```
Proxmox
├── LXC "nextcloud"
│   ├── Docker: Nextcloud + MariaDB + Redis
│   └── Netbird Client (100.114.x.1)
├── LXC "paperless"
│   ├── Docker: Paperless + PostgreSQL + Gotenberg + Tika
│   └── Netbird Client (100.114.x.2)
├── LXC "vaultwarden"
│   ├── Docker: Vaultwarden
│   └── Netbird Client (100.114.x.3)
└── LXC "infra"
    ├── Grafana Alloy Agent
    ├── Restic Backup
    └── Netbird Client (100.114.x.4)
```

**Jeder LXC bekommt seinen eigenen Netbird-Client** und damit eine eigene Netbird-IP. Es gibt KEINEN Gateway-LXC auf dem Proxmox — der Gateway-Server ist der Entry-Point!

**Traffic-Flow (Hybrid):**
```
Internet → Cloud-Server (Caddy + Auth)
               │
               ├── Netbird → 100.114.x.1:8080  (LXC: Nextcloud)
               ├── Netbird → 100.114.x.2:8081  (LXC: Paperless)
               └── Netbird → 100.114.x.3:8222  (LXC: Vaultwarden)
```

**Traffic-Flow (Lokal-Only):**
```
Internet → Kunden-Router (Port-Forward)
               │
               ▼
           LXC "gateway" (Caddy + PocketID + Tinyauth)
               │ Netbird Client (100.114.x.0)
               │
               ├── Netbird → 100.114.x.1:8080  (LXC: Nextcloud)
               ├── Netbird → 100.114.x.2:8081  (LXC: Paperless)
               └── Netbird → 100.114.x.3:8222  (LXC: Vaultwarden)
```

> **Bei komplett lokaler Installation** braucht man einen Gateway-LXC mit Caddy, weil es keinen externen Cloud-Server gibt. Dieser Gateway-LXC hat auch einen Netbird-Client und routet über Netbird an die App-LXCs.

**Vorteile:**
- Echte Prozess-Isolation auf Kernel-Ebene (LXC-Namespaces)
- Granulare Resource-Limits pro App (RAM, CPU, Disk via Proxmox)
- Ein kompromittierter LXC kann nicht auf andere zugreifen
- Snapshots pro App möglich (Proxmox LXC Snapshots)
- Sauberere Backup-Granularität
- Konsistentes Netzwerk: Alles über Netbird, keine zweite Netzwerkebene
- Ansible/Master hat direkten SSH-Zugang zu jedem LXC (über Netbird)
- Kein Single Point of Failure — wenn ein LXC hängt, laufen die anderen weiter

**Nachteile:**
- Mehr Netbird-Peers (bei 5 Apps = 5 LXCs = 5 Peers pro Kunde, kein Problem für Netbird)
- Mehr Ansible-Komplexität (mehrere Hosts pro Kunde im Inventar)
- Mehr RAM-Verbrauch (Basis-OS + Netbird pro LXC: ~200-400 MB)
- Jeder LXC braucht TUN-Device für Netbird

### 5.4 Warum KEIN Gateway-LXC / KEINE Proxmox-Bridge

Wenn ein externer Gateway-Server existiert, übernimmt dieser die TLS-Terminierung und leitet über Netbird direkt an die einzelnen App-LXCs. Das bedeutet:

- **Keine Proxmox-Bridge nötig** — kein vmbr1, kein internes Subnetz, kein Routing
- **Kein zusätzlicher Caddy auf dem Proxmox** — der Gateway-Caddy macht alles
- **Kein Single Point of Failure** auf Proxmox-Seite — jeder LXC ist eigenständig erreichbar
- **Direkter Ansible-Zugriff** — Master-Server erreicht jeden LXC direkt über Netbird (kein SSH-Hopping über Gateway)

Wenn kein externer Gateway existiert (komplett lokal), wird ein Gateway-LXC auf dem Proxmox erstellt.

### 5.5 Konfigurierbare Isolation im Inventar

```yaml
# inventories/kunde-abc/group_vars/all.yml
isolation_mode: "single_lxc"  # "single_lxc" | "lxc_per_app"
```

- `single_lxc`: Alles in einem LXC/Server (wie Cloud-Only, ein Netbird-Peer)
- `lxc_per_app`: Separater LXC pro App (jeweils eigener Netbird-Client + Peer)

Das Playbook und die Rollen verhalten sich je nach `isolation_mode` unterschiedlich:
- Bei `single_lxc`: Ein Host im Inventar, alle Apps über Docker Compose
- Bei `lxc_per_app`: Mehrere Hosts im Inventar, pro LXC eine App-Rolle

### 5.6 LXC-Erstellung (Ansible + Proxmox API)

Ansible erstellt LXCs auf Proxmox über das `community.general.proxmox`-Modul:

```yaml
- name: Create app LXC
  community.general.proxmox:
    vmid: "{{ lxc_id }}"
    hostname: "{{ kunde_id }}-{{ app_name }}"
    node: "{{ proxmox_node }}"
    api_host: "{{ proxmox_api_host }}"
    api_user: "{{ proxmox_api_user }}"
    api_token_id: "{{ proxmox_api_token_id }}"
    api_token_secret: "{{ proxmox_api_token_secret }}"
    ostemplate: "local:vztmpl/debian-13-standard_13.0-1_amd64.tar.zst"
    storage: "local-lvm"
    disk: "{{ app_disk_size | default('16') }}"
    cores: "{{ app_cores | default(2) }}"
    memory: "{{ app_memory | default(2048) }}"
    swap: 512
    net:
      net0: "name=eth0,bridge=vmbr0,ip=dhcp"
    features:
      - nesting=1
    unprivileged: true
    state: present
```

> **Voraussetzung:** Proxmox API-Token mit LXC-Erstellungsrechten. Wird beim Kunden-Onboarding einmalig konfiguriert.

**LXC-Template sicherstellen:**

Ansible stellt vor der LXC-Erstellung sicher, dass das benötigte Template auf dem Proxmox vorhanden ist:

```yaml
- name: Download LXC template if missing
  command: >
    pveam download local debian-13-standard_13.0-1_amd64.tar.zst
  args:
    creates: /var/lib/vz/template/cache/debian-13-standard_13.0-1_amd64.tar.zst
  delegate_to: "{{ proxmox_host }}"
```

> **Hinweis:** `pveam download` ist idempotent wenn man `creates:` nutzt. Falls eine neuere Template-Version nötig wird, kann die Variable `lxc_template` im Inventar überschrieben werden.

**Nach LXC-Erstellung — Bootstrap via `pct exec`:**

Frisch erstellte LXCs haben weder SSH-Key noch Netbird. Ansible bootstrappt sie über den Proxmox-Host mittels `pct exec` (Proxy-Zugang über Netbird):

```
Master-LXC ──Netbird──► Proxmox-Host ──pct exec──► Neuer LXC
```

**Bootstrap-Sequenz:**

```yaml
# Phase 1: Bootstrap via pct exec (auf dem Proxmox-Host, delegiert)
- name: Install SSH key in new LXC
  command: >
    pct exec {{ lxc_vmid }} -- bash -c
    "mkdir -p /root/.ssh && echo '{{ master_ssh_pubkey }}' >> /root/.ssh/authorized_keys && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys"
  delegate_to: "{{ proxmox_host }}"

- name: Install Netbird in new LXC
  command: >
    pct exec {{ lxc_vmid }} -- bash -c
    "curl -fsSL https://pkgs.netbird.io/install.sh | bash && netbird up --setup-key {{ netbird_setup_key }} --management-url {{ loco.netbird.manager_url }}"
  delegate_to: "{{ proxmox_host }}"

- name: Wait for Netbird connection
  command: >
    pct exec {{ lxc_vmid }} -- netbird status --json
  delegate_to: "{{ proxmox_host }}"
  register: nb_status
  until: nb_status.stdout | from_json | json_query('ip') != ""
  retries: 30
  delay: 5

- name: Register Netbird IP
  set_fact:
    new_lxc_netbird_ip: "{{ (nb_status.stdout | from_json).ip | regex_replace('/.*', '') }}"

# Phase 2: Direkte SSH-Verbindung über Netbird-IP
- name: Run base role on new LXC
  include_role:
    name: base
  delegate_to: "{{ new_lxc_netbird_ip }}"

- name: Deploy app on new LXC
  include_role:
    name: "apps/{{ app_name }}"
  delegate_to: "{{ new_lxc_netbird_ip }}"
```

1. **Phase 1 (via `pct exec`):** SSH-Key + Netbird installieren — Ansible delegiert Befehle an den Proxmox-Host, der sie per `pct exec` im LXC ausführt
2. **Phase 2 (direkte SSH-Verbindung):** Sobald Netbird läuft, verbindet sich Ansible direkt über die Netbird-IP zum LXC für base-Rolle, Docker, App-Deployment
3. TUN-Device konfigurieren: `lxc.cgroup2.devices.allow: c 10:200 rwm` + `lxc.mount.entry: /dev/net/tun` — wird VOR dem LXC-Start in der Proxmox-Config gesetzt

> **Warum `pct exec`?** Zuverlässiger als Cloud-Init (nicht alle Templates unterstützen es) und flexibler als der `pubkey`-Parameter des Proxmox-Moduls (der nur SSH-Keys kann, kein Netbird-Install).

### 5.7 Netzwerk-Übersicht bei LXC-pro-App

```
┌─────────────────────────────────────────────────────────────┐
│ Gateway-Server (firma.de)                                    │
│ server_roles: [gateway, customer_master]                     │
│ ├── Caddy (TLS, forward_auth → Tinyauth)                    │
│ ├── PocketID (id.firma.de)                                   │
│ ├── Tinyauth (auth.firma.de)                                 │
│ └── Netbird Client (100.x.x.0)                              │
│         │                                                    │
│         │ Netbird WireGuard Tunnel (verschlüsselt)           │
└─────────┼────────────────────────────────────────────────────┘
          │
          ├───────────────────────────────────────────────┐
          │                                               │
┌─────────▼─────────────┐  ┌──────────────▼──────────────┐
│ App-Server (LXC)      │  │                             │
│                       │  │  App-Server (LXC)           │
│ LXC: nextcloud        │  │  LXC: paperless             │
│ ├── Netbird (x.1)     │  │  ├── Netbird (x.2)          │
│ ├── Docker: Nextcloud  │  │  ├── Docker: Paperless      │
│ ├── Docker: MariaDB   │  │  ├── Docker: PostgreSQL      │
│ └── Docker: Redis     │  │  ├── Docker: Gotenberg       │
│     Port: 8080        │  │  └── Docker: Tika            │
│                       │  │      Port: 8081              │
└───────────────────────┘  └──────────────────────────────┘

Caddyfile auf dem Gateway:
  cloud.firma.de → reverse_proxy 100.x.x.1:8080
  paper.firma.de → reverse_proxy 100.x.x.2:8081
```

**Kein TLS auf den App-Servern nötig** — Netbird-Tunnel ist WireGuard-verschlüsselt, Caddy auf dem Gateway terminiert TLS für den Endbenutzer.

**Kein lokaler Caddy nötig** — der Gateway-Caddy routet direkt an jeden App-Server.

**Alle Docker-Container binden auf 0.0.0.0** — Netbird-Traffic kommt über `wt0` Interface an. Absicherung über UFW: App-Port nur auf `wt0` erlauben.

---

## 6. Netzwerk-Architektur (Netbird)

### 6.1 Netbird-Server & Gruppenstruktur

Der Netbird-Server kann extern betrieben oder self-hosted werden (siehe Kap. 2.5). Die Isolation geschieht über Gruppen und Policies.

```
Netbird Manager
│
├── LOCOCLOUDD GRUPPEN
│   ├── Group: loco-admin      → Master-Server, Admin-Geräte
│   ├── Group: loco-backup     → Backup-Server
│   ├── Group: kunde-abc       → Alle Server von Kunde ABC
│   ├── Group: kunde-xyz       → Alle Server von Kunde XYZ
│   └── ...
│
├── LOCOCLOUDD POLICIES
│   ├── loco-admin → kunde-*        (Admin-Zugang zu allen Kunden)
│   ├── loco-admin → loco-backup    (Admin-Zugang zu Backup)
│   ├── loco-backup → kunde-*       (Backup-Pull von allen Kunden)
│   ├── kunde-abc → kunde-abc       (Intern: Gateway ↔ App-Server)
│   ├── kunde-xyz → kunde-xyz       (Intern)
│   └── KEINE Policy: kunde-abc ↔ kunde-xyz  (Isolation!)
│
└── Kunden sehen sich NICHT gegenseitig
```

### 6.2 Peer-Benennung

Konsistente Benennung für Übersichtlichkeit:

```
loco-master                    ← Master-Server
loco-backup                    ← Backup-Server
abc-gw                         ← Kunde ABC, Gateway-Server
abc-proxmox                    ← Kunde ABC, lokaler Proxmox
abc-apps                       ← Kunde ABC, Apps-Server
abc-nextcloud                  ← Kunde ABC, Nextcloud-LXC (bei lxc_per_app)
xyz-gw                         ← Kunde XYZ, Gateway
...
```

### 6.3 Netbird-Automation via API (vollautomatisch durch Ansible)

Ansible erstellt beim Kunden-Onboarding **alle Netbird-Ressourcen automatisch** über die Netbird REST-API (`{{ loco.netbird.manager_url }}/api`). Kein manueller Eingriff nötig.

**Schritt 1: Kundengruppe erstellen**
```yaml
- name: Create Netbird group for customer
  uri:
    url: "{{ loco.netbird.manager_url }}/api/groups"
    method: POST
    headers:
      Authorization: "Token {{ loco.netbird.api_token }}"
    body_format: json
    body:
      name: "kunde-{{ kunde_id }}"
    status_code: 200
  register: nb_group
```

**Schritt 2: Policies erstellen**
```yaml
- name: Create policy — customer internal
  uri:
    url: "{{ loco.netbird.manager_url }}/api/policies"
    method: POST
    headers:
      Authorization: "Token {{ loco.netbird.api_token }}"
    body_format: json
    body:
      name: "kunde-{{ kunde_id }}-internal"
      enabled: true
      rules:
        - name: "Internal traffic"
          enabled: true
          sources: ["{{ nb_group.json.id }}"]
          destinations: ["{{ nb_group.json.id }}"]
          bidirectional: true
          protocol: "all"
          action: "accept"

- name: Create policy — admin to customer
  uri:
    url: "{{ loco.netbird.manager_url }}/api/policies"
    method: POST
    headers:
      Authorization: "Token {{ loco.netbird.api_token }}"
    body_format: json
    body:
      name: "loco-admin-to-kunde-{{ kunde_id }}"
      enabled: true
      rules:
        - name: "Admin access"
          enabled: true
          sources: ["{{ loco_admin_group_id }}"]
          destinations: ["{{ nb_group.json.id }}"]
          bidirectional: true
          protocol: "all"
          action: "accept"
```

**Schritt 3: Setup-Keys generieren**
```yaml
- name: Create Netbird setup key for customer
  uri:
    url: "{{ loco.netbird.manager_url }}/api/setup-keys"
    method: POST
    headers:
      Authorization: "Token {{ loco.netbird.api_token }}"
    body_format: json
    body:
      name: "kunde-{{ kunde_id }}-onboarding"
      type: "reusable"
      auto_groups: ["{{ nb_group.json.id }}"]
      usage_limit: 20
      expires_in: 86400
    status_code: 200
  register: nb_setup_key
```

**Setup-Key Strategie:**
- `reusable: true` mit `usage_limit` für Onboarding (damit mehrere LXCs denselben Key nutzen können)
- Nach Onboarding: Key läuft automatisch ab (`expires_in: 86400` = 24h)
- Für spätere einzelne LXC-Erstellungen (`add-app.yml`): Einmal-Key generieren
- Alle Keys werden in Admin-Vaultwarden gespeichert

**Schritt 4: Backup-Policy erstellen (falls Backup-Server existiert)**
```yaml
- name: Create policy — backup to customer
  uri:
    url: "{{ loco.netbird.manager_url }}/api/policies"
    method: POST
    headers:
      Authorization: "Token {{ loco.netbird.api_token }}"
    body_format: json
    body:
      name: "loco-backup-to-kunde-{{ kunde_id }}"
      enabled: true
      rules:
        - name: "Backup pull"
          enabled: true
          sources: ["{{ loco_backup_group_id }}"]
          destinations: ["{{ nb_group.json.id }}"]
          bidirectional: false
          protocol: "all"
          action: "accept"
  when: backup.enabled | default(false)
```

### 6.4 DNS in Netbird

**NUR für interne Domains verwenden!**

Wenn der Gateway-Caddy an App-Server routen muss, braucht er die Netbird-IP. Diese wird als Ansible-Variable hinterlegt, NICHT als Netbird DNS Zone (verursacht Konflikte mit öffentlichem DNS).

---

## 7. Authentifizierung & Autorisierung

### 7.1 Zwei Auth-Ebenen

1. **Admin-Auth** (LocoCloud-Management): PocketID + Tinyauth auf der Admin-Domain
2. **Kunden-Auth** (pro Kunde): Eigene PocketID + Tinyauth auf der Kunden-Domain

Diese sind komplett getrennt — andere PocketID-Instanzen, andere Tinyauth-Instanzen, andere Secrets.

### 7.2 Auth-Architektur pro Kunde

```
Benutzer (Browser)
    │ HTTPS
    ▼
Caddy (TLS auf öffentlichem Server)
    │
    ├── Öffentliche Pfade → Direkt zur App
    │
    └── Geschützte Pfade → forward_auth → Tinyauth (auth.firma.de)
                                              │
                                              ▼
                                         PocketID (id.firma.de)
                                         OIDC Authorization Code Flow
```

### 7.3 PocketID pro Kunde

**Instanz:** Eigener Docker-Container pro Kunde auf dem Entry-Point-Server
**URL:** `id.firma.de`
**Admin:** Betreiber (generiertes Passwort → Admin-Vaultwarden)
**Registrierung:** Blockiert per Caddy (`/register` → 403)
**Settings:** Hinter Tinyauth (`/settings` → `import auth`)

**Konfiguration (Ansible-Template):**
```yaml
services:
  pocketid:
    image: ghcr.io/pocket-id/pocket-id-monolith:latest
    container_name: pocketid
    restart: unless-stopped
    ports:
      - "127.0.0.1:{{ pocketid_port | default(1411) }}:80"
    volumes:
      - {{ pocketid_data_path }}/data:/data
    environment:
      - TRUST_PROXY=true
```

### 7.4 Tinyauth pro Kunde

**Instanz:** Eigener Docker-Container pro Kunde
**URL:** `auth.firma.de`

**Konfiguration (Ansible-Template):**
```yaml
services:
  tinyauth:
    image: ghcr.io/steveiliop56/tinyauth:latest
    container_name: tinyauth
    restart: unless-stopped
    ports:
      - "127.0.0.1:{{ tinyauth_port | default(9090) }}:3000"
    environment:
      - SECRET={{ tinyauth_secret }}
      - APP_URL=https://auth.{{ kunde_domain }}
      - OAUTH_WHITELIST={{ admin_email }},{{ kunden_emails | join(',') }}
      - SESSION_EXPIRY=86400
      - OAUTH_PROVIDERS=pocketid
      - POCKETID_CLIENT_ID={{ tinyauth_oidc_client_id }}
      - POCKETID_CLIENT_SECRET={{ tinyauth_oidc_client_secret }}
      - POCKETID_ISSUER_URL=https://id.{{ kunde_domain }}
```

### 7.5 App-SSO-Integration (OIDC)

Jede App die OIDC unterstützt wird direkt mit der Kunden-PocketID verbunden:

| App | OIDC-Redirect-Path | Besonderheiten |
|-----|-------------------|----------------|
| Nextcloud | `/apps/user_oidc/code` | `user_oidc` App installieren, lokalen Login deaktivieren, `--send-id-token-hint=0` |
| Paperless-NGX | `/accounts/oidc/callback/` | `DISABLE_REGULAR_LOGIN=true`, `ACCOUNT_ALLOW_SIGNUPS=false` |
| Vaultwarden | `/identity/connect/authorize` | SSO via OIDC |
| Documenso | `/api/auth/callback/oidc` | — |
| Outline | `/auth/oidc.callback` | — |
| Gitea/Forgejo | `/-/auth/oidc/callback` | — |
| HedgeDoc | `/auth/oauth2/callback` | — |

Apps OHNE OIDC (Uptime Kuma, Listmonk etc.) werden ausschließlich durch Tinyauth Forward-Auth geschützt.

### 7.6 PocketID REST-API

**PocketID hat eine REST-API mit API-Token-Authentifizierung.** Ansible kann über das `uri`-Modul direkt:
- **User anlegen:** `POST /api/users` (username, email, first_name, last_name)
- **Gruppen erstellen und User zuweisen:** `POST /api/user-groups`
- **OIDC-Clients erstellen:** `POST /api/oidc/clients` (Name, Callback-URLs, Scopes)

API-Endpoints: `https://id.firma.de/api/...` mit Bearer-Token-Auth (`Authorization: Bearer <api-token>`).

### 7.7 Benutzer-Management (automatisiert via API)

**Workflow "Neuer Mitarbeiter":**
1. Ansible erstellt User in PocketID via API (`uri`-Modul)
2. PocketID sendet Setup-E-Mail an den User
3. User registriert seinen Passkey im Browser (manuell, kann nicht automatisiert werden)
4. E-Mail wird zur Tinyauth `OAUTH_WHITELIST` hinzugefügt
5. `docker restart tinyauth`
6. User kann sich bei allen Apps anmelden (automatische Provisionierung via OIDC)

**Workflow "Mitarbeiter entfernen":**
1. In PocketID deaktivieren/löschen (via API oder UI)
2. E-Mail aus `OAUTH_WHITELIST` entfernen
3. `docker restart tinyauth` → Session sofort ungültig

**Workflow "OIDC-Client für neue App":**
1. Ansible erstellt OIDC-Client in PocketID via API (Name, Callback-URL)
2. API gibt Client-ID und Client-Secret zurück
3. Ansible konfiguriert die App mit diesen Credentials
4. Credentials werden in Admin-Vaultwarden gespeichert (via `credentials`-Rolle)

### 7.8 Berechtigungskonzept (Baserow)

Pro Kunde wird in Baserow auf dem Master-Server eine Berechtigungstabelle gepflegt (siehe Kap. 3.7). Diese Tabelle dokumentiert:

- Welcher Benutzer Zugriff auf welche Apps hat
- Welche Rolle (Admin/Standard/Readonly) zugewiesen ist
- Zeitliche Befristungen

Die Tabelle ist die **Soll-Dokumentation** — PocketID + Tinyauth sind die **Ist-Umsetzung**. Bei Kunden-Audits (DSGVO Art. 5 Abs. 1 lit. f) kann die Baserow-Tabelle als Nachweis exportiert werden.

### 7.9 Tinyauth-Warnung

> **Entschieden: PocketID + Tinyauth.** Tinyauth wird ausschließlich als OIDC-Forward-Auth genutzt (Login nur über PocketID Passkeys). Brute-Force-Schutz ist irrelevant, da kein direkter Login stattfindet. Im Produktivbetrieb bewährt — kein Fallback nötig.

---

## 8. Caddy Reverse Proxy System

### 8.1 Prinzip

**Default: ALLES blockiert.** Öffentliche Pfade werden explizit gewhitelistet.

Pro öffentlich erreichbarem Server ein Caddy. Der Gateway-Caddy ist der Single-Entry-Point, KEIN Caddy auf den App-Servern nötig (Netbird-Tunnel ist verschlüsselt).

### 8.2 Snippets (global wiederverwendbar)

```caddyfile
(public) {
    header -Server
    header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    header X-Content-Type-Options "nosniff"
    header X-Frame-Options "SAMEORIGIN"
    header Referrer-Policy "strict-origin-when-cross-origin"
    header Permissions-Policy "camera=(), microphone=(), geolocation=()"
}

(auth) {
    forward_auth 127.0.0.1:{{ tinyauth_port | default(9090) }} {
        uri /api/auth/caddy
    }
}
```

### 8.3 Caddyfile-Template (Jinja2)

```caddyfile
# ==========================================================
# GENERIERT DURCH ANSIBLE — NICHT MANUELL EDITIEREN
# Kunde: {{ kunde_name }} ({{ kunde_domain }})
# Generiert: {{ ansible_facts.date_time.iso8601 }}
# ==========================================================

(public) {
    header -Server
    header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    header X-Content-Type-Options "nosniff"
    header X-Frame-Options "SAMEORIGIN"
    header Referrer-Policy "strict-origin-when-cross-origin"
    header Permissions-Policy "camera=(), microphone=(), geolocation=()"
}

(auth) {
    forward_auth 127.0.0.1:{{ tinyauth_port }} {
        uri /api/auth/caddy
    }
}

# --- PocketID (OIDC Provider) ---
id.{{ kunde_domain }} {
    import public
    @blocked path /register*
    handle @blocked {
        respond "Access Denied" 403
    }
    @admin path /settings*
    handle @admin {
        import auth
        reverse_proxy 127.0.0.1:{{ pocketid_port }}
    }
    handle {
        reverse_proxy 127.0.0.1:{{ pocketid_port }}
    }
}

# --- Tinyauth Login Portal ---
auth.{{ kunde_domain }} {
    import public
    reverse_proxy 127.0.0.1:{{ tinyauth_port }} {
        header_down Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'self'; base-uri 'self'; form-action 'self' https://id.{{ kunde_domain }}"
    }
}

# --- Apps ---
{% for app in apps_enabled %}
{{ app.subdomain }}.{{ kunde_domain }} {
    import public

{% if app.public_paths is defined and app.public_paths | length > 0 %}
    # Öffentliche Pfade
{% for path in app.public_paths %}
    @pub_{{ loop.index }} path {{ path }}
    handle @pub_{{ loop.index }} {
{% if app.target == 'lokal' %}
        reverse_proxy {{ app.netbird_ip }}:{{ app.port }}
{% else %}
        reverse_proxy 127.0.0.1:{{ app.port }}
{% endif %}
    }
{% endfor %}
{% endif %}

    # Geschützter Bereich
    handle {
        import auth
{% if app.target == 'lokal' %}
        reverse_proxy {{ app.netbird_ip }}:{{ app.port }}
{% else %}
        reverse_proxy 127.0.0.1:{{ app.port }}
{% endif %}
    }
}

{% endfor %}
# --- Catch-All ---
:80, :443 {
    respond "Access Denied" 403
    header -Server
}
```

### 8.4 CSP-Strategie

**Apps mit eigenem CSP (NICHT überschreiben):** Vaultwarden, Nextcloud, PocketID, Paperless

**Apps ohne eigenen CSP:** Tinyauth, statische Seiten → CSP über `header_down` in Caddy setzen

### 8.5 Caddy-Handler-Reihenfolge

**KRITISCH:** Bei Apps mit gemischtem Auth (öffentliche + geschützte Pfade) müssen spezifische `handle @matcher`-Blöcke VOR dem Fallback `handle {}` stehen. Caddy evaluiert von oben nach unten und nimmt den ersten Match.

Besonders wichtig bei Netbird (falls als App deployed): gRPC, API, Relay, WebSocket MÜSSEN auth-frei bleiben.

### 8.6 Caddy-Neustart nach Änderungen

Ansible-Handler:
```yaml
handlers:
  - name: restart caddy
    community.docker.docker_compose_v2:
      project_src: "{{ caddy_stack_path }}"
    # ODER einfach:
    # command: docker restart caddy
```

> **NICHT `caddy reload` verwenden** wenn das Caddyfile als Bind-Mount vorliegt und durch Ansible (Template-Modul) geschrieben wurde — neuer Inode, alter Mount. Immer `docker restart caddy`.

---

## 9. App-Template-System

### 9.1 App-Definition im Kunden-Inventar

Jede App wird als Eintrag in `apps_enabled` definiert:

```yaml
apps_enabled:
  - name: "Nextcloud"
    subdomain: "cloud"
    port: 8080
    image: "nextcloud:latest"
    target: "lokal"              # lokal | online
    netbird_ip: "100.114.x.1"   # Netbird-IP des LXC (bei lxc_per_app: eigene IP pro App)
    oidc_enabled: true
    oidc_redirect_path: "/apps/user_oidc/code"
    needs_db: true
    db_type: "mariadb"
    needs_redis: true
    redis_db: 0                  # Redis DB-Nummer (Isolation bei shared Redis)
    public_paths:
      - "/index.php/s/*"
      - "/s/*"
    backup_paths:
      - "/mnt/data/nextcloud"
    env_extra:
      NEXTCLOUD_TRUSTED_DOMAINS: "cloud.{{ kunde_domain }}"
```

> **`netbird_ip`-Logik:**
> - Bei `single_lxc`: Alle Apps haben die gleiche `netbird_ip` (ein LXC = ein Peer)
> - Bei `lxc_per_app`: Jede App hat eine eigene `netbird_ip` (ein LXC pro App = ein Peer pro App)
> - Bei `target: online`: `netbird_ip` wird ignoriert, Caddy routet auf `127.0.0.1`

### 9.2 Ansible-Rolle pro App

```
roles/apps/nextcloud/
├── defaults/main.yml          # Default-Werte
├── tasks/
│   ├── main.yml               # Dispatcher (deploy/remove/configure)
│   ├── deploy.yml             # Docker Compose + starten
│   ├── configure.yml          # App-spezifisch (occ, etc.)
│   ├── oidc.yml               # OIDC-Client via PocketID API registrieren
│   └── remove.yml             # Aufräumen
├── templates/
│   ├── docker-compose.yml.j2
│   └── env.j2
└── handlers/main.yml
```

**OIDC-Registrierung (`oidc.yml`)** nutzt die PocketID REST-API:
```yaml
- name: Create OIDC client in PocketID
  uri:
    url: "https://id.{{ kunde_domain }}/api/oidc/clients"
    method: POST
    headers:
      X-API-Key: "{{ pocketid_api_token }}"
    body_format: json
    body:
      name: "{{ app_name }}"
      callbackURLs:
        - "https://{{ app_subdomain }}.{{ kunde_domain }}{{ app_oidc_redirect_path }}"
    status_code: [200, 201]
  register: oidc_result

# PocketID v2: Secret muss separat generiert werden
- name: Generate OIDC client secret
  uri:
    url: "https://id.{{ kunde_domain }}/api/oidc/clients/{{ oidc_result.json.id }}/secret"
    method: POST
    headers:
      X-API-Key: "{{ pocketid_api_token }}"
    status_code: 200
  register: secret_result

- name: Store OIDC credentials in Vaultwarden
  include_role:
    name: credentials
  vars:
    credential_name: "{{ kunde_name }} — {{ app_name }} OIDC"
    credential_username: "{{ oidc_result.json.id }}"
    credential_password: "{{ secret_result.json.secret }}"
```

### 9.3 Redis-Strategie (durch `isolation_mode` implizit gelöst)

**Bei `single_lxc`:** Ein Redis-Container, mehrere Apps. Isolation über DB-Nummern:

```yaml
# Nextcloud
REDIS_HOST: redis
REDIS_PORT: 6379
REDIS_DB: 0

# Paperless
REDIS_HOST: redis
REDIS_PORT: 6379
REDIS_DB: 1
```

**Bei `lxc_per_app`:** Jeder LXC hat seinen eigenen Redis-Container. Keine DB-Nummern nötig — die Isolation geschieht auf LXC-Ebene.

> **Keine offene Entscheidung mehr** — das Verhalten ist durch `isolation_mode` determiniert.

### 9.4 PostgreSQL 18 Mount-Pfad

```yaml
# ACHTUNG: PG 18 erwartet Mount auf /var/lib/postgresql (NICHT /data!)
volumes:
  - {{ data_path }}/db/postgres:/var/lib/postgresql
```

### 9.5 App hinzufügen / entfernen / bearbeiten

**Hinzufügen (bei `single_lxc` oder `target: online`):**
1. App zu `apps_enabled` im Inventar hinzufügen
2. Playbook `add-app.yml` ausführen
3. Generiert Credentials → Vaultwarden
4. Deployed Docker Container
5. Registriert OIDC-Client in PocketID via API
6. Regeneriert Caddyfile + restart
7. Registriert Grafana-Monitoring (Alloy Agent auf dem Host)

**Hinzufügen (bei `lxc_per_app` mit `target: lokal`) — erweiterter Workflow:**

Bei `lxc_per_app` muss `add-app.yml` einen komplett neuen LXC erstellen und bootstrappen, bevor die App deployt werden kann:

```
┌─ add-app.yml ─────────────────────────────────────────────────┐
│                                                                │
│  1. Netbird-Setup-Key generieren (Netbird API)                 │
│     └── Einmal-Key für die Kundengruppe                        │
│                                                                │
│  2. LXC erstellen (Proxmox API via Netbird → Proxmox-Host)    │
│     └── community.general.proxmox Modul                        │
│     └── TUN-Device konfigurieren (für Netbird)                 │
│     └── LXC starten                                            │
│                                                                │
│  3. Bootstrap via pct exec (delegiert an Proxmox-Host)         │
│     ├── SSH-Key injizieren                                     │
│     ├── Netbird installieren + joinen                          │
│     └── Netbird-IP ermitteln + registrieren                    │
│                                                                │
│  4. hosts.yml aktualisieren (neuen Host hinzufügen)            │
│     └── ansible_host: <neue Netbird-IP>                        │
│     └── server_roles: [app_server]                             │
│     └── app_name: <app>                                        │
│                                                                │
│  5. Base-Rolle (via direkte SSH über Netbird-IP)               │
│     └── Hardening, Docker, UFW                                 │
│                                                                │
│  6. App deployen                                               │
│     ├── Docker Compose + .env                                  │
│     ├── OIDC-Client via PocketID API                           │
│     └── Credentials → Vaultwarden                              │
│                                                                │
│  7. Caddyfile auf Entry-Point regenerieren + restart            │
│     └── Neue Route: subdomain.domain → Netbird-IP:Port         │
│                                                                │
│  8. Grafana Alloy Agent deployen                               │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

> **Chicken-and-Egg gelöst:** Die Netbird-IP ist erst nach dem Join bekannt (Schritt 3). Deshalb wird `hosts.yml` dynamisch in Schritt 4 aktualisiert. Ab Schritt 5 verbindet sich Ansible direkt über die neue Netbird-IP.

**Entfernen:**
1. Playbook `remove-app.yml` mit `app_name`
2. Stoppt Container, archiviert Daten
3. Entfernt OIDC-Client
4. Regeneriert Caddyfile + restart
5. Entfernt Grafana-Monitoring (Alloy Agent)

**Bearbeiten** (z.B. öffentliche Pfade ändern):
1. Inventar-YAML editieren
2. `update-caddy.yml` ausführen → Caddyfile regenerieren + restart
3. Falls App-Config geändert: `update-app.yml` → .env + Docker Compose regenerieren

---

## 10. Credential-Management (Ansible Vault + Vaultwarden)

### 10.1 Zwei-Schichten-Strategie

**Ansible Vault und Vaultwarden ergänzen sich — beides wird eingesetzt:**

| Was | Wo | Wie |
|-----|-----|-----|
| Kunden-Inventar-Secrets (Netbird-Keys, Tokens) | Ansible Vault (`group_vars/vault.yml`, verschlüsselt im Repo) | `ansible-vault encrypt` |
| Ansible-Vault-Passwort selbst | Admin-Vaultwarden (vault.admin.example.com) | Shell-Script `vault-pass.sh` holt es via `bw` CLI |
| Generierte App-Credentials (DB-Passwörter, OIDC-Secrets) | Admin-Vaultwarden via API | `credentials`-Rolle speichert nach Deploy |
| SSH-Keys | Admin-Vaultwarden | Bitwarden SSH-Agent |
| Laufzeit-Secrets lesen | Vaultwarden via `community.general.bitwarden` Lookup-Plugin | `lookup('community.general.bitwarden', 'name', field='password')` |

**Ansible-Vault-Passwort aus Vaultwarden:**
```bash
#!/bin/bash
# scripts/vault-pass.sh — wird von ansible.cfg als vault_password_file referenziert
_bw_session="$(bw unlock --raw)"
bw get password "lococloudd-ansible-vault" --session "${_bw_session}" --raw
```

In `ansible.cfg`:
```ini
[defaults]
vault_password_file = scripts/vault-pass.sh
```

So muss man sich nur das Vaultwarden-Master-Passwort merken. Alles andere ist verschlüsselt oder in Vaultwarden.

### 10.2 Eigene Vaultwarden-Instanz auf Master-Server

`vault.admin.example.com` — dedizierte Admin-Instanz für alle Kunden-Credentials.

### 10.3 Ordnerstruktur

```
LocoCloud Organisation/
├── Infrastruktur/
│   ├── Master-LXC SSH Key
│   ├── GitHub Deploy Key
│   ├── Netbird API Credentials
│   ├── Grafana Admin
│   ├── Baserow Admin
│   └── Master PocketID Admin
├── Kunde ABC (firma-abc.de)/
│   ├── Server/
│   │   ├── Cloud-Server SSH Key
│   │   ├── Proxmox LXC SSH Key
│   │   └── Proxmox API Token
│   ├── Auth/
│   │   ├── PocketID Admin Account (generiertes PW)
│   │   ├── Tinyauth Secret
│   │   └── Tinyauth OIDC Credentials
│   ├── Apps/
│   │   ├── Nextcloud DB Credentials
│   │   ├── Nextcloud OIDC Client Secret
│   │   ├── Paperless DB Credentials
│   │   └── ...
│   ├── Backup/
│   │   └── Restic Encryption Key
│   └── Netbird/
│       └── Setup-Keys
├── Kunde XYZ/
│   └── ...
```

### 10.4 Ansible-Integration

```yaml
# Credential generieren
- name: Generate credentials
  set_fact:
    app_db_password: "{{ lookup('password', '/dev/null chars=ascii_letters,digits length=32') }}"
    app_oidc_secret: "{{ lookup('password', '/dev/null chars=ascii_letters,digits length=48') }}"
    app_oidc_client_id: "{{ lookup('pipe', 'python3 -c \"import uuid; print(uuid.uuid4())\"') }}"

# In Admin-Vaultwarden speichern
- name: Store in Vaultwarden
  uri:
    url: "https://{{ loco_vaultwarden_url }}/api/ciphers"
    method: POST
    headers:
      Authorization: "Bearer {{ loco_vaultwarden_api_token }}"
    body_format: json
    body:
      type: 1
      name: "{{ kunde_name }} — {{ app_name }}"
      login:
        username: "{{ app_db_user }}"
        password: "{{ app_db_password }}"
        uris:
          - uri: "https://{{ app_subdomain }}.{{ kunde_domain }}"
      notes: |
        OIDC Client ID: {{ app_oidc_client_id }}
        OIDC Secret: {{ app_oidc_secret }}
        Deployed: {{ ansible_facts.date_time.iso8601 }}
      folderId: "{{ kunde_folder_id }}"
      organizationId: "{{ loco_org_id }}"
```

### 10.5 Vaultwarden API Token

Gespeichert auf Master-LXC: `/root/.loco-vaultwarden-token` (chmod 600)

---

## 11. Backup-Architektur

### 11.1 Übersicht

```
Kunden-Server
    │ Restic via SFTP über Netbird (oder direkt per SFTP)
    ▼
Backup-Ziel (pro Kunde konfigurierbar)
    ├── Option 1: Eigener Backup-Server via Netbird
    ├── Option 2: Cloud Storage Box
    └── Option 3: Off-Site auf Betreiber-Infrastruktur via Netbird
```

Das Backup-Ziel ist **pro Kunde konfigurierbar**, nicht eine globale Entscheidung. Alle Ziele sind über Netbird oder direkt per SFTP erreichbar. Restic verschlüsselt client-seitig — der Backup-Server sieht nur verschlüsselte Blobs.

**Ohne Backup-Ziel = kein Backup.** Wenn im Inventar kein `backup.targets` definiert ist, wird kein Backup konfiguriert. Der Betreiber entscheidet bewusst pro Kunde, ob und wohin gesichert wird.

### 11.2 Was wird gesichert

1. Docker Volumes aller Apps (aus `/mnt/data/`)
2. Datenbank-Dumps (Pre-Backup-Hooks, siehe 11.4)
3. PocketID Daten (SQLite + Config)
4. Tinyauth Config
5. Caddy Caddyfile
6. Docker Compose + .env Files
7. gocryptfs-Konfiguration (nicht die Keyfiles — die liegen auf dem Master)

### 11.3 Konfiguration im Inventar

```yaml
backup:
  enabled: true
  targets:
    # Option 1: Eigener Backup-Server via Netbird
    - type: "sftp"
      host: "{{ backup_server_netbird_ip }}"
      user: "backup"
      path: "/backup/{{ kunde_id }}"

    # Option 2: Cloud Storage Box
    - type: "sftp"
      host: "uXXXXX.your-storagebox.de"
      port: 23
      user: "uXXXXX"
      path: "/backup/{{ kunde_id }}"

    # Option 3: Off-Site auf Betreiber-Infrastruktur via Netbird
    - type: "sftp"
      host: "{{ loco.backup_netbird_ip }}"
      user: "backup"
      path: "/backup/{{ kunde_id }}"
  schedule:
    incremental: "0 */6 * * *"
  retention:
    keep_daily: 7
    keep_weekly: 4
    keep_monthly: 6
  restore_test:
    enabled: true
    schedule: "0 3 1 * *"  # Monatlich am 1. um 03:00
```

### 11.4 Pre-Backup-Hooks (Datenbank-Dumps)

Vor jedem Restic-Backup werden automatisch Datenbank-Dumps erstellt. Der Cron-Job ruft ein Wrapper-Script auf:

```bash
#!/bin/bash
# /opt/lococloudd/scripts/pre-backup.sh
# Wird vor jedem Restic-Backup ausgeführt

DUMP_DIR="/mnt/data/db-dumps"
mkdir -p "$DUMP_DIR"

# PostgreSQL-Dumps (für Paperless, etc.)
for db in $(docker exec postgres psql -U postgres -t -c "SELECT datname FROM pg_database WHERE datistemplate=false AND datname != 'postgres'"); do
  docker exec postgres pg_dump -U postgres "$db" | gzip > "$DUMP_DIR/${db}_$(date +%Y%m%d_%H%M%S).sql.gz"
done

# MariaDB/MySQL-Dumps (für Nextcloud, etc.)
if docker ps --format '{{.Names}}' | grep -q mariadb; then
  docker exec mariadb mysqldump -u root --all-databases | gzip > "$DUMP_DIR/mariadb_all_$(date +%Y%m%d_%H%M%S).sql.gz"
fi

# Alte Dumps aufräumen (nur letzte 3 behalten)
find "$DUMP_DIR" -name "*.sql.gz" -mtime +3 -delete
```

**Ansible konfiguriert den Cron-Job:**
```yaml
- name: Configure backup cron with pre-hook
  cron:
    name: "restic-backup-{{ kunde_id }}"
    minute: "0"
    hour: "*/6"
    job: "/opt/lococloudd/scripts/pre-backup.sh && /opt/lococloudd/scripts/restic-backup.sh"
    user: root
```

### 11.5 Monatlicher Restore-Test

**Die Behörde will sehen, dass Restores funktionieren.** Der Restore-Test wird als Ansible-Playbook automatisiert und monatlich per Cron (oder Semaphore-Schedule) ausgeführt:

```
┌─ restore-test.yml ──────────────────────────────────────────┐
│                                                              │
│  1. Letzten Restic-Snapshot identifizieren                   │
│  2. Restore in temporäres Verzeichnis (/tmp/restore-test/)   │
│  3. Prüfungen:                                               │
│     ├── Dateien vorhanden? (Mindestanzahl pro App)           │
│     ├── DB-Dump lesbar? (gunzip + Integrity-Check)           │
│     ├── Docker Compose valide? (docker compose config)       │
│     └── Dateigröße plausibel? (nicht 0 Bytes)                │
│  4. Ergebnis loggen + Alert bei Fehler                       │
│  5. Temporäres Verzeichnis aufräumen                         │
│                                                              │
│  → Ergebnis wird in Grafana als Metrik sichtbar              │
│  → Bei Fehlschlag: E-Mail-Alert an Betreiber                 │
└──────────────────────────────────────────────────────────────┘
```

**Nachweis:** Jeder Restore-Test wird mit Timestamp und Ergebnis in einer Log-Datei protokolliert (`/var/log/lococloudd/restore-tests.log`). Diese Datei kann bei Audits vorgelegt werden.

---

## 12. Verschlüsselung (gocryptfs)

### 12.1 Prinzip

Alle Kundendaten auf jedem Server werden mit gocryptfs verschlüsselt. Das verschlüsselte Verzeichnis ist `/mnt/data` — dort liegen alle Docker-Volumes, Datenbank-Dateien und App-Daten.

```
Kundenserver:
/mnt/data/                    ← gocryptfs-Mountpoint (entschlüsselt)
/mnt/data.encrypted/          ← Cipher-Verzeichnis (verschlüsselt auf Disk)

Master-Server:
/opt/lococloudd/keys/kunde-abc/server.key  ← Keyfile (nur auf Master)
```

**Vorteile:**
- Daten auf dem Kundenserver sind im Ruhezustand verschlüsselt (Disk-Diebstahl, Server-Rückgabe)
- Ohne Keyfile vom Master sind die Daten nicht lesbar
- gocryptfs ist FUSE-basiert — keine Kernel-Patches nötig, läuft in LXC
- Transparent für alle Apps (Dateisystem-Ebene)

### 12.2 Setup pro Server (Ansible)

```yaml
- name: Install gocryptfs
  apt:
    name: gocryptfs
    state: present

- name: Create encrypted directory
  file:
    path: /mnt/data.encrypted
    state: directory
    mode: '0700'

- name: Create mountpoint
  file:
    path: /mnt/data
    state: directory
    mode: '0755'

- name: Initialize gocryptfs (only if not yet initialized)
  command: >
    gocryptfs -init -passfile /tmp/gocryptfs.key /mnt/data.encrypted
  args:
    creates: /mnt/data.encrypted/gocryptfs.conf

- name: Store keyfile on master
  fetch:
    src: /tmp/gocryptfs.key
    dest: "/opt/lococloudd/keys/{{ kunde_id }}/{{ inventory_hostname }}.key"
    flat: yes
  delegate_to: localhost

- name: Remove keyfile from server
  file:
    path: /tmp/gocryptfs.key
    state: absent

- name: Mount encrypted filesystem
  command: >
    gocryptfs -passfile /dev/stdin /mnt/data.encrypted /mnt/data
  args:
    stdin: "{{ lookup('file', '/opt/lococloudd/keys/' + kunde_id + '/' + inventory_hostname + '.key') }}"
```

### 12.3 Automatische Entschlüsselung nach Reboot

Solange der Master-Server erreichbar ist, entschlüsselt sich der Kundenserver nach dem Reboot automatisch. Ein Systemd-Service holt das Keyfile temporär vom Master:

```ini
# /etc/systemd/system/gocryptfs-mount.service
[Unit]
Description=Mount gocryptfs encrypted data
After=network-online.target
Wants=network-online.target
Before=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/opt/lococloudd/scripts/gocryptfs-mount.sh
ExecStop=/bin/fusermount -u /mnt/data

[Install]
WantedBy=multi-user.target
```

```bash
#!/bin/bash
# /opt/lococloudd/scripts/gocryptfs-mount.sh
MASTER_IP="{{ master_server_ip }}"
KUNDE_ID="{{ kunde_id }}"
HOSTNAME="$(hostname)"
KEY_PATH="/opt/lococloudd/keys/${KUNDE_ID}/${HOSTNAME}.key"

# Keyfile vom Master holen (SSH-Key-Auth)
MAX_RETRIES=30
RETRY_DELAY=10
for i in $(seq 1 $MAX_RETRIES); do
  scp -o ConnectTimeout=5 root@${MASTER_IP}:${KEY_PATH} /tmp/gocryptfs.key && break
  sleep $RETRY_DELAY
done

if [ ! -f /tmp/gocryptfs.key ]; then
  echo "ERROR: Could not retrieve keyfile from master after ${MAX_RETRIES} attempts"
  exit 1
fi

# Mount
gocryptfs -passfile /tmp/gocryptfs.key /mnt/data.encrypted /mnt/data

# Keyfile sofort löschen
rm -f /tmp/gocryptfs.key
```

**Reihenfolge:** `gocryptfs-mount.service` startet VOR `docker.service` — so sind die Daten entschlüsselt bevor Container starten.

### 12.4 Key-Backup-Server

Für den Fall dass der Master-Server ausfällt, können die gocryptfs-Schlüssel auf einen Key-Backup-Server repliziert werden.

**Server-Rolle:** `key_backup` — kann per Ansible ausgerollt werden.

```yaml
# Im Master-Inventar oder separatem Inventar:
key_backup_server:
  ansible_host: "100.114.x.x"   # Netbird-IP oder öffentliche IP
  server_roles: [key_backup]
```

**Sync-Mechanismus (Ansible-Rolle `key_backup`):**
```yaml
- name: Sync keys to backup server
  synchronize:
    src: /opt/lococloudd/keys/
    dest: /opt/lococloudd/keys/
    mode: push
    rsync_opts:
      - "--delete"
      - "--chmod=D700,F600"
  delegate_to: "{{ master_host }}"

- name: Schedule periodic key sync
  cron:
    name: "sync-gocryptfs-keys"
    minute: "0"
    hour: "*/4"
    job: "rsync -az --delete /opt/lococloudd/keys/ root@{{ key_backup_ip }}:/opt/lococloudd/keys/"
    user: root
  delegate_to: "{{ master_host }}"
```

**Disaster Recovery:** Wenn der Master ausfällt, kann der Key-Backup-Server als neuer Keyfile-Quelle konfiguriert werden (IP im Systemd-Service anpassen oder neuen Master aufsetzen und Keys rückkopieren).

### 12.5 Sicherheitshinweise

- **Keyfiles NIEMALS im Git-Repo** — sie liegen nur auf dem Master und optional auf dem Key-Backup-Server
- **Keyfiles NIEMALS im Restic-Backup** — sonst wäre die Verschlüsselung sinnlos (verschlüsselte Daten + Schlüssel am selben Ort)
- **SSH-Zugang zum Master** ist die kritischste Berechtigung — wer den Master kontrolliert, hat Zugang zu allen Daten
- **Master und Key-Backup physisch trennen** — nicht auf demselben Proxmox-Host

---

## 13. Monitoring, Logging & Alerting (Grafana Stack)

### 13.1 Architektur-Übersicht

Zabbix ist aus dem Stack gestrichen. Stattdessen kommt der Grafana-Stack:

```
┌─────────────────────────────────────────────────────────────┐
│  Master-Server                                                │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐     │
│  │  Grafana (grafana.admin.example.com)                  │     │
│  │  ├── Dashboards pro Kunde (Labels/Filter)             │     │
│  │  ├── Alerting (E-Mail)                                │     │
│  │  └── Data Sources: Prometheus + Loki                  │     │
│  └──────────────────────────────────────────────────────┘     │
│                                                               │
│  ┌──────────────┐  ┌──────────────┐                           │
│  │  Prometheus   │  │  Loki        │                           │
│  │  (Metriken)   │  │  (Logs)      │                           │
│  │  :9091        │  │  :3110       │                           │
│  └──────┬────────┘  └──────┬───────┘                          │
│         │                  │                                   │
│         │  Scrape/Push     │  Push                             │
└─────────┼──────────────────┼───────────────────────────────────┘
          │                  │
          │   Netbird / SSH  │
          │                  │
┌─────────┴──────────────────┴───────────────────────────────────┐
│  Kundenserver (jeder Server / jeder LXC)                       │
│                                                                │
│  ┌──────────────────────────────────────────────────────┐      │
│  │  Grafana Alloy (einziger Agent)                       │      │
│  │  ├── node_exporter (integriert) → Metriken            │      │
│  │  ├── cAdvisor (integriert) → Container-Metriken       │      │
│  │  ├── journald → Logs                                  │      │
│  │  └── Docker Logs → Logs                               │      │
│  └──────────────────────────────────────────────────────┘      │
└────────────────────────────────────────────────────────────────┘
```

**Ein Agent für alles:** Grafana Alloy ersetzt Zabbix Agent, node_exporter und separate Log-Shipper. Es sammelt Metriken UND Logs und schickt sie an Prometheus bzw. Loki auf dem Master.

### 13.2 Was wird überwacht (Alerting)

| Check | Methode | Alert-Schwellwert |
|-------|---------|-------------------|
| Disk-Auslastung | Alloy → Prometheus | > 85% |
| RAM-Auslastung | Alloy → Prometheus | > 90% |
| CPU-Auslastung (sustained) | Alloy → Prometheus | > 90% für > 5 Min |
| Container-Health | Alloy cAdvisor → Prometheus | Container nicht running |
| HTTP-Status Apps | Grafana Synthetic Monitoring / Blackbox | Status != 200 (über Backend-Port, NICHT öffentliche URL!) |
| SSL-Zertifikat-Ablauf | Blackbox Exporter | < 14 Tage |
| Backup-Status | Custom Metrik aus Restic-Script | Letzter Snapshot > 24h alt |
| Restore-Test-Ergebnis | Custom Metrik | Letzter Test fehlgeschlagen |
| SSH-Logins | Loki (journald) | Ungewöhnliche Logins (root, neue IP) |
| Netbird Peer | Custom Metrik | Peer offline |
| gocryptfs Mount | Custom Metrik | `/mnt/data` nicht gemountet |

### 13.3 Grafana Alloy auf Kundenservern

Alloy wird auf jedem Kundenserver/-LXC als Docker-Container deployt:

```yaml
services:
  alloy:
    image: grafana/alloy:latest
    container_name: alloy
    restart: unless-stopped
    volumes:
      - /opt/alloy/config.alloy:/etc/alloy/config.alloy:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /var/log:/var/log:ro
      - /:/host:ro
    command: run /etc/alloy/config.alloy
    network_mode: host
    pid: host
    # KEIN Watchtower-Label — Updates nur über Ansible
```

**Alloy-Konfiguration (Auszug):**
```hcl
// Metriken sammeln (node_exporter-kompatibel)
prometheus.exporter.unix "default" {
  set_collectors = ["cpu", "diskstats", "filesystem", "loadavg", "meminfo", "netdev"]
}

// Container-Metriken (cAdvisor-kompatibel)
discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
}

// Metriken an Prometheus auf dem Master senden
prometheus.remote_write "master" {
  endpoint {
    url = "http://{{ master_ip }}:9091/api/v1/write"
    basic_auth {
      username = "{{ kunde_id }}"
      password = "{{ alloy_push_token }}"
    }
  }
  external_labels = {
    kunde = "{{ kunde_id }}",
    server = "{{ inventory_hostname }}",
  }
}

// Logs aus journald
loki.source.journal "system" {
  forward_to = [loki.write.master.receiver]
  labels = {
    kunde = "{{ kunde_id }}",
    server = "{{ inventory_hostname }}",
    source = "journald",
  }
}

// Docker-Container-Logs
loki.source.docker "containers" {
  host = "unix:///var/run/docker.sock"
  targets = discovery.docker.containers.targets
  forward_to = [loki.write.master.receiver]
  labels = {
    kunde = "{{ kunde_id }}",
    server = "{{ inventory_hostname }}",
    source = "docker",
  }
}

// Logs an Loki auf dem Master senden
loki.write "master" {
  endpoint {
    url = "http://{{ master_ip }}:3110/loki/api/v1/push"
    basic_auth {
      username = "{{ kunde_id }}"
      password = "{{ alloy_push_token }}"
    }
  }
}
```

### 13.4 DSGVO- und GoBD-konforme Logs

**Personenbezogene Daten minimieren:**
- Keine Passwörter in Logs (Alloy Filter-Pipeline)
- IP-Adressen: Minimale Retention (werden nach 6 Monaten gelöscht)
- Benutzernamen nur in Audit-Logs der Apps (nicht in System-Logs)

**Aufbewahrung:**
- Loki Retention: 6 Monate (`retention_period: 4320h`)
- journald: `MaxRetentionSec=6month` in `/etc/systemd/journald.conf`
- Nach Ablauf: Automatische Löschung (kein manuelles Eingreifen)

**Manipulationsschutz:**
- journald FSS (Forward Secure Sealing) aktivieren: `Seal=yes` in `journald.conf`
- Zentrale Log-Sammlung in Loki macht lokale Manipulation nachweisbar

**GoBD-Relevanz bei Paperless:**
- Löschschutz aktivieren: `PAPERLESS_CONSUMER_DELETE_DUPLICATES: false`
- PDF/A-Archivierung: `PAPERLESS_OCR_OUTPUT_TYPE: pdfa`
- Audit-Trail: Paperless loggt alle Dokumentzugriffe nativ

### 13.5 App-spezifisches Audit-Logging

Alle Apps werden bei Deployment automatisch so konfiguriert, dass Audit-Logging aktiviert ist:

| App | Audit-Logging | Konfiguration |
|-----|--------------|---------------|
| Nextcloud | Activity App + Audit-Log App | `occ app:enable activity && occ app:enable admin_audit` |
| Paperless-NGX | Eingebaut | Loggt Zugriffe nativ, kein Extra-Setup |
| Kimai | Eingebaut | Aktiviert per Default |
| Invoice Ninja | Eingebaut | Aktiviert per Default |
| Vaultwarden | Event-Log | Aktiviert per Default |

### 13.6 Kunden-Sichtbarkeit

**Kunden sehen KEINE Logs direkt** in Grafana. Stattdessen:

- **App-eigene Audit-Feeds:** Nextcloud Activity, Paperless Logs (in der jeweiligen App-UI)
- **Uptime Kuma Status-Page:** `status.kunde.de` — optionale Kunden-App für Service-Status
- **Der Admin sieht alles zentral in Grafana**, gefiltert nach Kunde via Labels (`kunde = "abc"`)

### 13.7 Uptime Kuma (optionale Kunden-App)

`status.firma.de` — optionales Status-Dashboard pro Kunde. Zeigt Kunden ob ihre Dienste online sind.

- **Kein Agent nötig:** Prüft HTTP/Ping von innen (läuft auf dem Kunden-LXC)
- **Kein OIDC:** Geschützt durch Tinyauth Forward-Auth
- **Port:** 8229
- **Optional:** Wird nur deployt wenn `uptime_kuma_enabled: true` im Kunden-Inventar
- **Status-Page:** Kann eine öffentliche Status-Seite generieren (konfigurierbar)

> Uptime Kuma ersetzt NICHT Grafana. Grafana = Admin-Monitoring (Infra, Logs, Alerting). Uptime Kuma = Kunden-Dashboard ("Sind meine Dienste online?").

---

## 14. Compliance & Dokumentation (DSGVO/GoBD)

### 14.1 Übersicht

Pro Kunde werden automatisch drei Compliance-Dokumente als Ansible-Templates generiert:

| Dokument | Rechtsgrundlage | Zweck |
|----------|----------------|-------|
| **TOM-Dokumentation** | Art. 32 DSGVO | Technische und organisatorische Maßnahmen |
| **Verarbeitungsverzeichnis** | Art. 30 DSGVO | Welche Daten werden wie verarbeitet |
| **Löschkonzept** | Art. 17 DSGVO / GoBD | Wann werden welche Daten gelöscht |

**Prinzip:** Einmal schreiben, pro Kunde die Variablen austauschen. Die Templates leben im Repo unter `roles/compliance/templates/`.

### 14.2 TOM-Dokumentation (Art. 32 DSGVO)

Die TOM-Dokumentation wird als Jinja2-Template generiert und beschreibt alle technischen und organisatorischen Maßnahmen:

```
roles/compliance/templates/tom.md.j2
```

**Inhalt (automatisch aus Variablen befüllt):**

| TOM-Kategorie | Maßnahme (aus LocoCloud) |
|---------------|--------------------------|
| **Zutrittskontrolle** | Server in Rechenzentrum (Provider-Verantwortung) / On-Premise (Kunden-Verantwortung) |
| **Zugangskontrolle** | SSH Key-Only + Netbird VPN, Fail2ban, UFW Firewall |
| **Zugriffskontrolle** | PocketID SSO + Tinyauth Forward-Auth, Berechtigungskonzept in Baserow |
| **Weitergabekontrolle** | TLS überall (Caddy Let's Encrypt), Netbird WireGuard-Tunnel |
| **Eingabekontrolle** | Audit-Logs (Nextcloud Activity, Paperless nativ), zentrale Logs in Loki |
| **Auftragskontrolle** | Isolierte Kunden-Infrastruktur, kein Sharing |
| **Verfügbarkeitskontrolle** | Restic-Backup mit Restore-Tests, Monitoring via Grafana |
| **Trennungsgebot** | Kunden vollständig isoliert (Netbird-Gruppen, separate Container, separate Auth) |
| **Verschlüsselung** | gocryptfs auf `/mnt/data`, Restic-Backup client-seitig verschlüsselt |

**Generierung:**
```yaml
- name: Generate TOM documentation
  template:
    src: tom.md.j2
    dest: "/opt/lococloudd/docs/kunden/{{ kunde_id }}/TOM-{{ kunde_name }}.md"
    mode: '0644'
```

### 14.3 Verarbeitungsverzeichnis (Art. 30 DSGVO)

Pro Kunde ein Verarbeitungsverzeichnis das beschreibt welche personenbezogenen Daten in welcher App verarbeitet werden:

```
roles/compliance/templates/vvt.md.j2
```

**Automatisch befüllte Felder:**
- Verantwortlicher: `{{ kunde_name }}` (aus Inventar)
- Auftragsverarbeiter: `{{ loco.operator.name }}`
- Verarbeitungstätigkeiten: Dynamisch aus `apps_enabled[]`
- Kategorien betroffener Personen: Mitarbeiter (`{{ kunden_users }}`)
- Kategorien personenbezogener Daten: Pro App definiert (Dateien, Dokumente, Zugangsdaten)
- Löschfristen: Aus Löschkonzept (Kap. 14.4)
- TOM-Verweis: Link auf die TOM-Dokumentation

**Beispiel-Verarbeitungstätigkeit (Nextcloud):**
```markdown
### Verarbeitungstätigkeit: Cloud-Speicher (Nextcloud)
- **Zweck:** Dateispeicherung und -freigabe für Mitarbeiter
- **Rechtsgrundlage:** Art. 6 Abs. 1 lit. b DSGVO (Vertragserfüllung)
- **Betroffene:** Mitarbeiter von {{ kunde_name }}
- **Datenarten:** Dateien, Metadaten (Dateiname, Größe, Änderungsdatum), Benutzernamen
- **Empfänger:** Keine Weitergabe an Dritte
- **Drittland-Transfer:** Nein (Self-Hosted)
- **Löschfrist:** Nach Kündigung + 90 Tage Archivierung
- **TOM:** Siehe TOM-Dokumentation {{ kunde_name }}
```

### 14.4 Löschkonzept

Das Löschkonzept definiert Aufbewahrungsfristen und automatische Löschung:

```
roles/compliance/templates/loeschkonzept.md.j2
```

| Datenkategorie | Aufbewahrungsfrist | Löschmethode |
|----------------|-------------------|--------------|
| App-Daten (Dateien, Dokumente) | Bis Kündigung + 90 Tage | Restic-Backup-Retention, dann `offboard-customer.yml` |
| Logs (System, Access) | 6 Monate | Loki Retention (`retention_period: 4320h`) + journald `MaxRetentionSec` |
| Audit-Logs (App-intern) | 6 Monate | App-spezifische Retention-Settings |
| Backup-Snapshots | 6 Monate (Restic Retention) | `restic forget --keep-monthly 6 --prune` |
| Benutzerkonten | Sofort bei Entfernung | `remove-user.yml` (PocketID + Tinyauth) |
| Kunden-Credentials | Archivierung bei Offboarding | Vaultwarden Ordner "[ARCHIV]" |
| gocryptfs-Keyfiles | Bis Kündigung + Archiv-Frist | Manuelles Löschen nach Offboarding + Bestätigung |
| DB-Dumps (Pre-Backup) | 3 Tage lokal | `find -mtime +3 -delete` im Pre-Backup-Script |

**GoBD-Relevanz:**
- Paperless-Dokumente mit Löschschutz: `PAPERLESS_CONSUMER_DELETE_DUPLICATES: false`
- PDF/A-Archivierung: `PAPERLESS_OCR_OUTPUT_TYPE: pdfa`
- Dokumente die unter GoBD fallen (Rechnungen, Belege) dürfen NICHT vor Ablauf der handelsrechtlichen Aufbewahrungsfrist (10 Jahre) gelöscht werden — das Löschkonzept verweist darauf, die Umsetzung liegt beim Kunden (Paperless-Tags für Aufbewahrungsfristen)

### 14.5 Ansible-Rolle `compliance`

```
roles/compliance/
├── defaults/main.yml          # Fristen, Kontaktdaten
├── tasks/
│   ├── main.yml               # Dispatcher
│   ├── generate-tom.yml       # TOM generieren
│   ├── generate-vvt.yml       # VVT generieren
│   └── generate-loeschkonzept.yml  # Löschkonzept generieren
├── templates/
│   ├── tom.md.j2              # TOM-Template
│   ├── vvt.md.j2              # Verarbeitungsverzeichnis-Template
│   └── loeschkonzept.md.j2    # Löschkonzept-Template
└── handlers/main.yml
```

**Wann wird generiert:**
- Bei `onboard-customer.yml` (erstmalig)
- Bei `add-app.yml` / `remove-app.yml` (VVT aktualisieren)
- Bei `add-user.yml` / `remove-user.yml` (VVT aktualisieren)
- Manuell per `ansible-playbook playbooks/generate-docs.yml -i inventories/kunde-abc/`

**Output:**
```
/opt/lococloudd/docs/kunden/
├── kunde-abc/
│   ├── TOM-Firma-ABC-GmbH.md
│   ├── VVT-Firma-ABC-GmbH.md
│   └── Loeschkonzept-Firma-ABC-GmbH.md
├── kunde-xyz/
│   └── ...
```

---

## 15. Repo-Struktur & Konfiguration

### 15.1 Vollständige Struktur

```
LocoCloud/
├── README.md
├── LICENSE
├── .gitignore
├── ansible.cfg
├── requirements.yml
│
├── config/
│   └── lococloudd.yml               # ← GLOBALE KONFIGURATION (Domain, E-Mail, URLs)
│
├── inventories/
│   ├── master/                       # Master-Server selbst
│   │   ├── hosts.yml
│   │   └── group_vars/all.yml
│   ├── _template/                    # Template für neue Kunden
│   │   ├── hosts.yml.j2
│   │   └── group_vars/all.yml.j2
│   ├── kunde-abc/
│   │   ├── hosts.yml
│   │   └── group_vars/all.yml
│   └── ...
│
├── roles/
│   ├── base/                         # OS-Hardening, Docker, UFW, Fail2ban
│   ├── caddy/                        # Reverse Proxy + TLS
│   ├── pocketid/                     # OIDC Provider
│   ├── tinyauth/                     # Forward Auth
│   ├── netbird_client/               # Netbird Installation + Join (optional)
│   ├── gocryptfs/                    # Verschlüsselung /mnt/data + Auto-Mount
│   ├── grafana_stack/                # Grafana + Prometheus + Loki (Master)
│   ├── alloy/                        # Grafana Alloy Agent (Kundenserver)
│   ├── baserow/                      # Baserow (Master, Berechtigungskonzept)
│   ├── backup/                       # Restic + Pre-Backup-Hooks + Restore-Tests
│   ├── key_backup/                   # gocryptfs Key-Backup auf separatem Server
│   ├── credentials/                  # Vaultwarden API
│   ├── compliance/                   # TOM, VVT, Löschkonzept (Jinja2-Templates)
│   ├── lxc_create/                   # Proxmox LXC erstellen (bei LXC-pro-App)
│   └── apps/
│       ├── _template/
│       ├── nextcloud/
│       ├── paperless/
│       ├── vaultwarden/
│       ├── documenso/
│       ├── pingvin-share/
│       ├── hedgedoc/
│       ├── outline/
│       ├── gitea/
│       ├── calcom/
│       ├── uptime-kuma/
│       └── listmonk/
│
├── playbooks/
│   ├── site.yml                      # Full Deploy
│   ├── setup-master.yml              # Master-Server initial einrichten
│   ├── add-server.yml                # Frischen Server zum Kunden hinzufügen
│   ├── add-app.yml
│   ├── remove-app.yml
│   ├── update-app.yml
│   ├── update-caddy.yml
│   ├── add-user.yml
│   ├── remove-user.yml
│   ├── update-all.yml
│   ├── backup-now.yml
│   ├── restore.yml
│   ├── restore-test.yml              # Monatlicher Restore-Test
│   ├── generate-docs.yml             # Compliance-Dokumente regenerieren
│   ├── onboard-customer.yml
│   └── offboard-customer.yml
│
├── scripts/
│   ├── init-master.sh                # Bootstrap-Script für Master-Server
│   ├── new-customer.sh               # Inventar aus Template generieren
│   ├── pre-backup.sh                 # DB-Dumps vor Restic-Backup
│   └── gocryptfs-mount.sh            # Auto-Mount nach Reboot
│
└── docs/
    ├── SETUP.md                      # Master-Server Setup
    ├── ONBOARDING.md                 # Neukunden-Prozess
    ├── APP-DEVELOPMENT.md            # Neue App-Rolle erstellen
    └── TROUBLESHOOTING.md
```

### 15.2 Globale Konfiguration: `config/lococloudd.yml`

**ALLES Spezifische wird hier konfiguriert.** So kann das Repo public sein — keine persönlichen Daten im Code.

Die Datei `config/lococloudd.yml.example` zeigt die vollständige Struktur (siehe Kap. 15.4).

### 15.3 `.gitignore`

```gitignore
# Betreiber-spezifische Config (NIEMALS committen)
config/lococloudd.yml

# Kunden-Inventare mit Secrets
inventories/*/group_vars/vault.yml

# Lokale Keys/Tokens
*.key
*.pem
*.token

# Ansible retry files
*.retry

# Python
__pycache__/
*.pyc
.venv/
```

### 15.4 `config/lococloudd.yml.example`

Wird committed als Template:

```yaml
# config/lococloudd.yml.example
# Kopiere diese Datei nach config/lococloudd.yml und passe sie an.

operator:
  name: "Dein Name"
  email: "admin@example.com"
  domain: "example.com"

admin:
  subdomain: "admin"
  full_domain: "admin.example.com"

urls:
  pocketid: "id.admin.example.com"
  tinyauth: "auth.admin.example.com"
  vaultwarden: "vault.admin.example.com"
  semaphore: "deploy.admin.example.com"
  grafana: "grafana.admin.example.com"
  baserow: "permissions.admin.example.com"

netbird:
  enabled: false                               # true wenn Netbird verwendet wird
  manager_url: "https://netbird.example.com"
  api_token: ""

pocketid:
  api_token: ""                              # PocketID REST-API Token

smtp:
  host: "smtp.example.com"
  port: 587
  starttls: true
  user: "user@example.com"
  from: "noreply@example.com"

repo:
  url: "git@github.com:YourUser/LocoCloud.git"
  branch: "main"
  deploy_key_path: "/root/.ssh/github-deploy-key"

vaultwarden:
  url: "https://vault.admin.example.com"
  api_token_path: "/root/.vaultwarden-token"
  organization_id: ""

bitwarden_cli:
  server_url: "https://vault.admin.example.com"
  vault_item_name: "lococloudd-ansible-vault"

admin_gateway:
  public_ip: ""                              # IP des Cloud-Servers fuer Admin-Routing
```

### 15.5 `ansible.cfg`

```ini
[defaults]
inventory = inventories/
roles_path = roles/
host_key_checking = False
retry_files_enabled = False
stdout_callback = yaml
vault_password_file = scripts/vault-pass.sh

[privilege_escalation]
become = True
become_method = sudo
become_user = root

[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
```

> **Hinweis:** Die globale Config muss über `include_vars` in den Playbooks geladen werden (`vars_files` in `ansible.cfg` funktioniert nicht direkt). Das Ansible-Vault-Passwort wird automatisch via `scripts/vault-pass.sh` aus Vaultwarden geholt.

**Empfohlener Ansatz:** In jedem Playbook als erstes:

```yaml
- hosts: all
  pre_tasks:
    - name: Load global config
      include_vars:
        file: "{{ playbook_dir }}/../config/lococloudd.yml"
        name: loco
```

---

## 16. Semaphore-Konfiguration

### 16.1 Zugang

`deploy.admin.example.com` — hinter Tinyauth (nur Betreiber)

### 16.2 Projekte

| Projekt | Inventar | Zweck |
|---------|----------|-------|
| Master | `master` | Master-Server Verwaltung |
| Kunde ABC | `kunde-abc` | Alles für Kunde ABC |
| Kunde XYZ | `kunde-xyz` | Alles für Kunde XYZ |
| Global | alle | Cross-Kunde-Updates |

### 16.3 Templates pro Kunde

| Template | Playbook | Extra-Variablen |
|----------|----------|-----------------|
| Full Deploy | `site.yml` | — |
| Onboard Customer | `onboard-customer.yml` | — (alles aus Inventar) |
| Offboard Customer | `offboard-customer.yml` | `offboard_mode` (`archivieren` / `loeschen`) |
| Add App | `add-app.yml` | `app_name`, `app_subdomain`, `app_port`, `app_target`, `app_public_paths` |
| Remove App | `remove-app.yml` | `app_name` |
| Update App | `update-app.yml` | `app_name` (Image-Tag aus Inventar) |
| Add User | `add-user.yml` | `username`, `email`, `display_name` |
| Remove User | `remove-user.yml` | `username` |
| Update Caddy | `update-caddy.yml` | — |
| Backup Now | `backup-now.yml` | — |
| Restore | `restore.yml` | `app_name`, `snapshot_id` |
| Update All | `update-all.yml` | — |

### 16.4 Öffentliche Pfade in Semaphore editieren

Da die öffentlichen Pfade im Inventar (`apps_enabled[].public_paths`) definiert sind, können sie über Semaphore geändert werden:

1. Im Semaphore-Projekt → Environment → Inventar-Datei editieren
2. `public_paths` anpassen
3. Template "Update Caddy" ausführen → Caddyfile wird regeneriert

---

## 17. Deployment-Abläufe

### 17.1 Master-Server erstmalig einrichten

```bash
# 1. LXC auf Proxmox erstellen (manuell oder per Script)
# 2. SSH-Zugang einrichten (Admin-Key)
# 3. Bootstrap-Script ausführen:
ssh root@<master-lxc-ip>
curl -sSL https://raw.githubusercontent.com/Ollornog/LocoCloud/main/scripts/init-master.sh | bash
# ODER: Repo klonen und script ausführen
git clone git@github.com:Ollornog/LocoCloud.git /opt/lococloudd
cd /opt/lococloudd
cp config/lococloudd.yml.example config/lococloudd.yml
nano config/lococloudd.yml  # Anpassen
bash scripts/init-master.sh
# 4. Playbook für Master-Setup:
ansible-playbook playbooks/setup-master.yml -i inventories/master/
```

**`setup-master.yml` macht:**
1. base-Rolle (Hardening, Docker, UFW)
2. Netbird-Client installieren + joinen (optional, Gruppe: `loco-admin`)
3. PocketID deployen (`id.admin.example.com`)
4. Tinyauth deployen (`auth.admin.example.com`)
5. Vaultwarden deployen (`vault.admin.example.com`)
6. Semaphore deployen (`deploy.admin.example.com`)
7. Grafana Stack deployen (Grafana + Prometheus + Loki auf `grafana.admin.example.com`)
8. Baserow deployen (`permissions.admin.example.com`)
9. gocryptfs Key-Store einrichten (`/opt/lococloudd/keys/`)
10. Caddy deployen mit Admin-Caddyfile
11. Alle Credentials in Vaultwarden speichern

### 17.2 Neuer Kunde (Schritt 1: Kunde anlegen)

```bash
# Input: Kundenadmin-Name, Kunden-Domain
bash scripts/new-customer.sh kunde-abc "Firma ABC GmbH" "firma-abc.de"
```

**Was passiert:**
1. Inventar-Verzeichnis `inventories/kunde-abc/` wird aus Template erstellt
2. `hosts.yml` und `group_vars/all.yml` werden generiert
3. Vault-Datei `group_vars/vault.yml` wird initialisiert
4. Berechtigungstabelle in Baserow wird angelegt (Kap. 3.7)

### 17.3 Server zum Kunden hinzufügen (Schritt 2)

**Frische Server werden mit IP, User und Passwort hinzugefügt.** Kein Netbird, kein Docker — nur ein frisches Debian.

```yaml
# inventories/kunde-abc/hosts.yml — Server hinzufügen
all:
  hosts:
    abc-server:
      ansible_host: "203.0.113.10"        # Öffentliche IP oder LAN-IP
      ansible_user: "root"                 # Initialer User
      ansible_ssh_pass: "{{ vault_abc_server_password }}"  # Initiales Passwort (nur für Bootstrap)
      server_name: "Hauptserver"
      server_description: "Cloud-VPS bei Provider X"
      server_roles: [gateway, customer_master, app_server]  # Serverrolle zuweisen
```

**Ansible bootstrappt den frischen Server:**

```
┌─ add-server.yml ─────────────────────────────────────────────┐
│                                                                │
│  Input: Servername, Beschreibung, IP, User, Passwort           │
│                                                                │
│  1. SSH-Verbindung mit Passwort (erster Zugriff)               │
│  2. SSH-Key deployen (Master → Server)                         │
│  3. Passwort-Auth deaktivieren                                 │
│  4. base-Rolle: Hardening, Docker, UFW, Fail2ban              │
│  5. Netbird-Client installieren + joinen (optional)            │
│     └── Wenn aktiviert: Netbird-IP in Inventar eintragen       │
│  6. gocryptfs installieren + /mnt/data verschlüsseln           │
│     ├── Keyfile generieren                                     │
│     ├── Keyfile auf Master speichern (keys/kunde-abc/)         │
│     ├── Keyfile vom Server löschen                             │
│     └── Auto-Mount Systemd-Service einrichten                  │
│  7. Grafana Alloy Agent installieren                           │
│     └── Metriken + Logs → Master (Prometheus/Loki)             │
│                                                                │
│  → Server ist jetzt bereit für App-Deployment                  │
└────────────────────────────────────────────────────────────────┘
```

### 17.4 App-Auswahl & Konfiguration (Schritt 3)

Nach dem Server-Bootstrap werden Apps und Konfiguration festgelegt:

```yaml
# inventories/kunde-abc/group_vars/all.yml
apps_enabled:
  - name: "Nextcloud"
    subdomain: "cloud"         # → cloud.firma-abc.de
    port: 8080
    # ... (App-Konfiguration wie bisher)

# Serverrolle und Backup-Ziel
backup:
  enabled: true                # Ohne Backup-Ziel: kein Backup
  targets:
    - type: "sftp"
      host: "{{ backup_server_ip }}"
      user: "backup"
      path: "/backup/{{ kunde_id }}"
```

**Deployment:**
```bash
ansible-playbook playbooks/onboard-customer.yml -i inventories/kunde-abc/
```

### 17.5 Onboarding-Ablauf (Schritt 4 — automatisiert)

```
┌─ onboard-customer.yml ────────────────────────────────────────┐
│                                                                │
│  1. Netbird-Gruppe + Policies erstellen (falls Netbird aktiv)  │
│  2. Server vorbereiten (falls nicht schon per add-server.yml)  │
│     ├── base-Rolle (Hardening, Docker, UFW)                    │
│     ├── gocryptfs auf /mnt/data                                │
│     └── Grafana Alloy Agent                                    │
│  3. Entry-Point konfigurieren (Gateway-Server):                │
│     ├── PocketID deployen (id.firma.de)                        │
│     ├── Tinyauth deployen (auth.firma.de)                      │
│     └── Admin-User in PocketID anlegen (API)                   │
│  4. Pro App: Deploy + OIDC-Client (PocketID API)               │
│     └── Credentials → Vaultwarden                              │
│  5. Caddy → Caddyfile generieren + restart                     │
│  6. Monitoring → Grafana Alloy auf jedem Host                  │
│  7. Backup → Restic Setup + Pre-Backup-Hooks + initiales Backup│
│  8. Compliance-Dokumente generieren (TOM, VVT, Löschkonzept)  │
│  9. Smoke-Test → HTTP-Checks auf alle Subdomains               │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

> **Proxmox-Onboarding** (Hybrid/Lokal-Only mit `lxc_per_app`): Wie bisher — Proxmox braucht nur Netbird + API-Token. Ansible erstellt LXC-Container remote über die Proxmox API und `pct exec`, bootstrappt sie (inkl. gocryptfs), und verbindet sich dann direkt für alles Weitere.

### 17.6 Benutzer hinzufügen

### 17.6 Benutzer hinzufügen

```yaml
# Aufruf: ansible-playbook add-user.yml -i inventories/kunde-abc/ \
#         -e "username=m.mueller email=m.mueller@firma-abc.de display_name='Max Müller'"

# Was passiert:
# 1. Benutzer in PocketID anlegen via REST-API (POST /api/users)
# 2. PocketID sendet Setup-E-Mail → User registriert Passkey (manuell)
# 3. E-Mail zur OAUTH_WHITELIST in Tinyauth hinzufügen
# 4. docker restart tinyauth
# 5. Inventar-YAML aktualisieren (kunden_users Liste)
```

### 17.7 Kunde offboarden

**`offboard-customer.yml`** — gestufter Prozess mit Sicherheitsabfragen.

**Zwei Modi:**
- **Archivieren** (Standard): Daten sichern, Dienste stoppen, Infrastruktur aus Admin entfernen, Server behalten
- **Komplett löschen**: Wie Archivieren + Daten und LXCs vernichten

```
┌─ offboard-customer.yml ───────────────────────────────────────┐
│                                                                │
│  Modus: archivieren | loeschen                                 │
│                                                                │
│  1. Finales Backup aller App-Daten (Restic)                    │
│     └── Backup verifizieren (restic check)                     │
│                                                                │
│  2. Docker Container stoppen (alle Apps)                       │
│     └── Pro App: docker compose down                           │
│                                                                │
│  3. OIDC-Clients aus PocketID entfernen (API)                  │
│     └── Alle Clients für diese Kunden-Domain                   │
│                                                                │
│  4. Netbird aufräumen                                          │
│     ├── Alle Peers der Kundengruppe entfernen (API)            │
│     ├── Policies entfernen (API)                               │
│     └── Kundengruppe entfernen (API)                           │
│                                                                │
│  5. Grafana-Monitoring aufräumen                               │
│     └── Alloy Agent deaktivieren, Dashboards entfernen         │
│                                                                │
│  6. Credentials in Vaultwarden archivieren                     │
│     └── Kunden-Ordner umbenennen: "[ARCHIV] Firma ABC"         │
│     └── Credentials bleiben für Audit-Trail erhalten           │
│                                                                │
│  7. Semaphore-Projekt entfernen                                │
│     └── Kunden-Projekt in Semaphore löschen                    │
│                                                                │
│  ── Nur bei Modus "loeschen": ────────────────────────────     │
│                                                                │
│  8. App-Daten löschen                                          │
│     └── Docker Volumes entfernen                               │
│     └── Daten-Verzeichnisse löschen                            │
│                                                                │
│  9. LXCs auf Proxmox vernichten (bei lxc_per_app)              │
│     └── community.general.proxmox: state=absent                │
│                                                                │
│  ── Ende ──────────────────────────────────────────────────    │
│                                                                │
│  10. Inventar-Verzeichnis archivieren oder löschen              │
│      └── mv inventories/kunde-abc inventories/_archived/abc    │
│      └── Oder: rm -rf inventories/kunde-abc                    │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

> **Cloud-Server wird NICHT automatisch gelöscht.** Das muss der Betreiber manuell über das Provider-Dashboard tun — zu riskant für Automation. Das Playbook gibt am Ende eine Zusammenfassung aus mit Hinweis: "Cloud-Server XYZ kann jetzt manuell gelöscht werden."

> **DNS-Records** müssen ebenfalls manuell entfernt werden (A-Record + Wildcard der Kunden-Domain).

---

## 18. Sicherheits-Hardening

### 18.1 Ansible-Rolle `base`

Identisch für alle Server (Master + Kunden):

| Maßnahme | Details |
|----------|---------|
| SSH | Key-only, `PermitRootLogin no`, `PasswordAuthentication no` |
| SSH auf Netbird | UFW: Port 22 nur auf `wt0` |
| Firewall (UFW) Entry-Point | 80/443 öffentlich, 22 nur wt0, default deny incoming |
| Firewall (UFW) App-LXCs | App-Port (z.B. 8080) nur auf `wt0`, 22 nur auf `wt0`, default deny incoming. So sind Docker-Ports trotz `0.0.0.0`-Bind nicht im LAN exponiert |
| Kernel-Hardening | sysctl (rp_filter, syncookies, etc.) — **LXC-kompatible Params beachten!** |
| Fail2ban | SSH (10 Versuche, 3600s Ban) |
| Unattended-upgrades | Automatische Sicherheitsupdates |
| Watchtower | Docker-Image-Patches täglich 04:00 — NUR Kunden-Apps (Label-basiert, Major gepinnt). Infra-Container OHNE Label, Updates nur über Ansible |
| USB deaktiviert | Nur auf physischen Servern (`is_lxc`-Check!) |
| .env chmod 600 | Alle Secrets-Files |
| Docker Port-Bind | Entry-Point: `127.0.0.1:PORT` / App-LXCs: `0.0.0.0:PORT` + UFW auf wt0 |

### 18.2 LXC-spezifisch

Variable `is_lxc: true/false` in der Rolle steuert:
- Kernel-Parameter: Nur netzwerkbezogene sysctl (LXC kann `kernel.*` und `fs.*` nicht setzen)
- USB: Nicht deaktivieren in LXC
- TUN-Device: Für Netbird in LXC nötig (`lxc.cgroup2.devices.allow: c 10:200 rwm`)

### 18.3 Admin-User pro Server

```yaml
admin_user: "srvadmin"     # Konfigurierbar pro Kunde
admin_user_nopasswd: true  # NOPASSWD für Ansible-Kompatibilität
```

---

## 19. Wartung & Updates

### 19.1 Grundregel: Alle Updates über Ansible

**Kein automatisches Update darf Infrastruktur kaputt machen.** Erfahrung: Watchtower hat den Netbird-Server automatisch aktualisiert → neuer Relay-Endpoint `/relay` (ohne Slash) → Caddy-Route `handle /relay/*` hat nicht mehr gematcht → VPN-Tunnel weg → alle Dienste unerreichbar.

**Konsequenz:** Updates werden in zwei Kategorien eingeteilt:

| Kategorie | Automatisch? | Methode |
|-----------|-------------|---------|
| OS-Sicherheitspatches | Ja | `unattended-upgrades` (apt, niedrig-riskant) |
| Backup | Ja | Restic Cron |
| Health-Checks | Ja | Grafana Alerting |
| SSL-Erneuerung | Ja | Caddy (ACME) |
| **Infrastruktur-Container** (Netbird, Caddy, PocketID, Tinyauth, Semaphore, Grafana, Alloy) | **NEIN** | **Nur über Ansible** (`update-all.yml` / `update-app.yml`) |
| **Kunden-App-Container** (Nextcloud, Paperless, Vaultwarden, etc.) | Ja (Patches) | Watchtower (Label-basiert, Major-Version gepinnt) |

### 19.2 Watchtower-Strategie: Nur Kunden-Apps, nie Infrastruktur

**Watchtower darf NUR Kunden-App-Container updaten.** Infrastruktur-Container (alles was Netzwerk, Auth oder Routing betrifft) bekommen KEIN Watchtower-Label.

**Container OHNE Watchtower-Label (Updates nur über Ansible):**
- Caddy
- Netbird (Server + Client via apt)
- PocketID
- Tinyauth
- Semaphore
- Grafana, Prometheus, Loki (Master)
- Grafana Alloy (Kundenserver)
- Baserow (Master)
- Watchtower selbst

**Container MIT Watchtower-Label (Patches automatisch):**
- Nextcloud (gepinnt auf Major: `nextcloud:29`)
- Paperless-NGX (gepinnt auf Major: `ghcr.io/paperless-ngx/paperless-ngx:2`)
- Vaultwarden (Kunden-Instanz)
- Uptime Kuma
- Weitere Kunden-Apps

```yaml
# Docker Compose Template für Kunden-Apps:
services:
  app:
    image: "nextcloud:29"          # Pinned auf Major-Version, Patches automatisch
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
```

**Image-Tag-Strategie:**
- `nextcloud:29` → bekommt automatisch 29.0.1, 29.0.2, etc. (Patches)
- `nextcloud:30` → manuell via `update-app.yml` wenn getestet (Major-Update)
- Container ohne Label werden von Watchtower ignoriert

**Major-Updates** (die was kaputt machen können) werden ausschließlich über Semaphore/`update-app.yml` gemacht:
1. Image-Tag im Inventar ändern (z.B. `nextcloud_version: "30"`)
2. `update-app.yml` ausführen → neues Image pullen, Container neu starten
3. Post-Update-Checks (Health-Check, DB-Migration prüfen)

### 19.3 Manuell (Semaphore)

| Task | Playbook |
|------|----------|
| Infra-Updates (Netbird, Caddy, PocketID, etc.) | `update-all.yml` — kontrolliertes Ansible-Rollout |
| Major App-Updates | `update-app.yml` — Image-Tag im Inventar ändern, dann ausführen |
| Full OS-Update | `update-all.yml` |
| Backup-Test | `backup-test.yml` |
| Mitarbeiter anlegen/entfernen | `add-user.yml` / `remove-user.yml` |

---

## 20. Kunden-Inventar-System

### 20.1 Grundprinzip

Jeder Host im Kunden-Inventar bekommt:
- **`server_roles`**: Liste von Rollen (siehe Kap. 2.1)
- **`hosting_type`**: `cloud` oder `proxmox_lxc`
- **`is_lxc`**: `true`/`false`

Es gibt keine festen Deployment-Varianten. Der Betreiber definiert frei, welche Rollen auf welchem Host laufen. Rollen können kombiniert werden (siehe Kap. 2.2).

### 20.2 Beispiel: Alles-auf-einem-Server (Cloud)

Ein einzelner Cloud-Server übernimmt alle Rollen.

```yaml
# inventories/kunde-abc/hosts.yml
all:
  hosts:
    abc-server:
      ansible_host: "100.114.a.0"      # Netbird-IP
      ansible_user: srvadmin
      server_roles: [gateway, customer_master, app_server]
      hosting_type: cloud
      public_ip: "203.0.113.10"
      is_lxc: false
```

### 20.3 Beispiel: Cloud-Gateway + lokale App-Server (ein LXC)

Cloud-Server als Entry-Point, eine lokale Proxmox-LXC für alle Apps.

```yaml
# inventories/kunde-abc/hosts.yml
all:
  hosts:
    abc-gw:
      ansible_host: "100.114.a.0"      # Netbird-IP
      ansible_user: srvadmin
      server_roles: [gateway, customer_master]
      hosting_type: cloud
      public_ip: "203.0.113.10"
      is_lxc: false
    abc-apps:
      ansible_host: "100.114.a.1"      # Netbird-IP (ein LXC für alle Apps)
      ansible_user: srvadmin
      server_roles: [app_server]
      hosting_type: proxmox_lxc
      is_lxc: true
  children:
    proxmox:
      hosts:
        abc-proxmox:
          ansible_host: "100.114.a.99" # Netbird-IP des Proxmox-Hosts
          ansible_user: root
          server_roles: [proxmox]
          is_lxc: false
          proxmox_node: "pve"
          proxmox_api_host: "100.114.a.99"
          proxmox_api_token_id: "ansible@pam!loco"
          proxmox_api_token_secret: "{{ vault_proxmox_token }}"
          lxc_template: "local:vztmpl/debian-13-standard_13.0-1_amd64.tar.zst"
```

> **Der Proxmox-Host** hat `server_roles: [proxmox]`. Er wird NICHT wie ein App-Server gehärtet (kein Docker, andere UFW-Regeln). Er dient nur als Ziel für LXC-Erstellung via Proxmox API und `pct exec`-Bootstrap. Netbird auf dem Proxmox-Host wird beim Kunden-Onboarding manuell installiert (einmaliger Schritt).

### 20.4 Beispiel: Cloud-Gateway + lokale App-Server (LXC pro App)

Cloud-Server als Entry-Point, separate LXCs pro App auf Proxmox.

```yaml
# inventories/kunde-abc/hosts.yml
all:
  hosts:
    abc-gw:
      ansible_host: "100.114.a.0"      # Netbird-IP
      ansible_user: srvadmin
      server_roles: [gateway, customer_master]
      hosting_type: cloud
      public_ip: "203.0.113.10"
      is_lxc: false
    abc-nextcloud:
      ansible_host: "100.114.a.1"      # Eigene Netbird-IP
      ansible_user: srvadmin
      server_roles: [app_server]
      hosting_type: proxmox_lxc
      app_name: nextcloud
      is_lxc: true
    abc-paperless:
      ansible_host: "100.114.a.2"      # Eigene Netbird-IP
      ansible_user: srvadmin
      server_roles: [app_server]
      hosting_type: proxmox_lxc
      app_name: paperless
      is_lxc: true
  children:
    proxmox:
      hosts:
        abc-proxmox:
          ansible_host: "100.114.a.99" # Netbird-IP des Proxmox-Hosts
          ansible_user: root
          server_roles: [proxmox]
          is_lxc: false
          proxmox_node: "pve"
          proxmox_api_host: "100.114.a.99"
          proxmox_api_token_id: "ansible@pam!loco"
          proxmox_api_token_secret: "{{ vault_proxmox_token }}"
          lxc_template: "local:vztmpl/debian-13-standard_13.0-1_amd64.tar.zst"
```

> **Jeder LXC hat seine eigene Netbird-IP.** Ansible erreicht jeden einzelnen direkt über Netbird — kein SSH-Hopping, kein Gateway. Der Proxmox-Host wird nur für LXC-Erstellung und Bootstrap benötigt.

### 20.5 Beispiel: Komplett lokal (LXC pro App)

Kein Cloud-Server. Ein Gateway-LXC auf Proxmox übernimmt den öffentlichen Zugang (via Port-Forward oder DynDNS).

```yaml
# inventories/kunde-abc/hosts.yml
all:
  hosts:
    abc-gw:
      ansible_host: "100.114.a.0"      # Netbird-IP
      ansible_user: srvadmin
      server_roles: [gateway, customer_master]
      hosting_type: proxmox_lxc
      public_ip: ""                     # Via DynDNS oder Port-Forward
      is_lxc: true
    abc-nextcloud:
      ansible_host: "100.114.a.1"      # Eigene Netbird-IP
      ansible_user: srvadmin
      server_roles: [app_server]
      hosting_type: proxmox_lxc
      app_name: nextcloud
      is_lxc: true
    abc-paperless:
      ansible_host: "100.114.a.2"      # Eigene Netbird-IP
      ansible_user: srvadmin
      server_roles: [app_server]
      hosting_type: proxmox_lxc
      app_name: paperless
      is_lxc: true
  children:
    proxmox:
      hosts:
        abc-proxmox:
          ansible_host: "100.114.a.99" # Netbird-IP des Proxmox-Hosts
          ansible_user: root
          server_roles: [proxmox]
          is_lxc: false
          proxmox_node: "pve"
          proxmox_api_host: "100.114.a.99"
          proxmox_api_token_id: "ansible@pam!loco"
          proxmox_api_token_secret: "{{ vault_proxmox_token }}"
          lxc_template: "local:vztmpl/debian-13-standard_13.0-1_amd64.tar.zst"
```

> **Bei komplett lokaler Installation:** Der Gateway-LXC übernimmt die Rolle des Cloud-Servers (Caddy + Auth). Routing zu App-LXCs geht über Netbird — kein Unterschied zum Cloud-Gateway aus Sicht der App-Server.

### 20.6 group_vars/all.yml (Hauptkonfiguration)

```yaml
# =====================================================================
# KUNDEN-KONFIGURATION
# =====================================================================

kunde_name: "Firma ABC GmbH"
kunde_domain: "firma-abc.de"
kunde_id: "abc001"

isolation_mode: "lxc_per_app"           # single_lxc | lxc_per_app

# --- Netbird ---
netbird_setup_key: "{{ vault_netbird_setup_key }}"
netbird_group: "kunde-{{ kunde_id }}"

# --- Benutzer ---
kunden_users:
  - username: "m.mustermann"
    display_name: "Max Mustermann"
    email: "m.mustermann@firma-abc.de"
  - username: "e.beispiel"
    display_name: "Erika Beispiel"
    email: "e.beispiel@firma-abc.de"

kunden_emails: "{{ kunden_users | map(attribute='email') | list }}"

# --- Apps ---
apps_enabled:
  - name: "Nextcloud"
    subdomain: "cloud"
    port: 8080
    image: "nextcloud:latest"
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
    env_extra:
      NEXTCLOUD_TRUSTED_DOMAINS: "cloud.firma-abc.de"

  - name: "Paperless-NGX"
    subdomain: "paper"
    port: 8081
    image: "ghcr.io/paperless-ngx/paperless-ngx:latest"
    oidc_enabled: true
    oidc_redirect_path: "/accounts/oidc/callback/"
    needs_db: true
    db_type: "postgres"
    needs_redis: true
    redis_db: 1
    public_paths: []
    backup_paths:
      - "/mnt/data/paperless"
    env_extra:
      PAPERLESS_DISABLE_REGULAR_LOGIN: "true"
      PAPERLESS_REDIRECT_LOGIN_TO_SSO: "true"
      PAPERLESS_ACCOUNT_ALLOW_SIGNUPS: "false"

  - name: "Vaultwarden"
    subdomain: "vault"
    port: 8222
    image: "vaultwarden/server:latest"
    oidc_enabled: true
    oidc_redirect_path: "/identity/connect/authorize"
    needs_db: false
    public_paths: []
    backup_paths:
      - "/opt/stacks/vaultwarden/data"

# --- Backup ---
backup:
  enabled: true
  targets:
    - type: "sftp"
      host: "{{ loco.backup_netbird_ip }}"
      user: "backup"
      path: "/backup/{{ kunde_id }}"
  retention:
    keep_daily: 7
    keep_weekly: 4
    keep_monthly: 6

# --- DynDNS (optional, z.B. bei komplett lokaler Installation) ---
dyndns:
  enabled: false
  provider: "master"  # Master-Server aktualisiert DNS für lokale Kunden
```

> **Wichtige Änderungen zum alten Format:**
> - `variante` (hybrid/cloud_only/lokal_only) entfällt — die Architektur ergibt sich aus den `server_roles` im Inventar
> - `target` pro App entfällt — Apps laufen auf Hosts mit `server_roles: [app_server]`
> - `online_server` entfällt — der Gateway wird über `server_roles: [gateway]` identifiziert
> - `netbird_setup_keys.online/lokal` → ein `netbird_setup_key` pro Kundengruppe (Netbird-API erstellt Keys automatisch)

---

## 21. Repo Public-Readiness

### 21.1 Was NICHT ins Repo darf

| Typ | Wo stattdessen |
|-----|----------------|
| `config/lococloudd.yml` | `.gitignore`, nur `.example` committed |
| Kunden-Inventare mit echten IPs | Ansible Vault oder `.gitignore` |
| SSH-Keys, API-Tokens | Vaultwarden + lokale Dateien |
| Netbird Setup-Keys | Vaultwarden |
| Passwörter jeder Art | Vaultwarden |

### 21.2 Was ins Repo darf

- Alle Rollen, Playbooks, Templates
- `config/lococloudd.yml.example`
- `inventories/_template/`
- Dokumentation
- Scripts

### 21.3 Ansible Vault für sensible Inventar-Daten

Für Kunden-Inventare die nicht in `.gitignore` stehen sollen (z.B. wenn das Repo privat bleibt), können sensitive Werte mit Ansible Vault verschlüsselt werden:

```yaml
# inventories/kunde-abc/group_vars/vault.yml (verschlüsselt)
vault_netbird_key_online: "encrypted-value"
vault_netbird_key_primary: "encrypted-value"
```

### 21.4 README.md (Auszug)

```markdown
# LocoCloud

Managed self-hosted infrastructure for small businesses.
Deploys standardized, open-source IT solutions as alternatives to
Microsoft 365 / Google Workspace.

## Quick Start

1. Set up a Master server (Debian 13 LXC or VM)
2. Clone this repo: `git clone git@github.com:Ollornog/LocoCloud.git`
3. Copy and configure: `cp config/lococloudd.yml.example config/lococloudd.yml`
4. Run master setup: `ansible-playbook playbooks/setup-master.yml`
5. Create a customer: `bash scripts/new-customer.sh ...`
6. Deploy: `ansible-playbook playbooks/site.yml -i inventories/kunde-abc/`
```

---

## 22. Bekannte Fallstricke & Lessons Learned

### Allgemein

| Problem | Lösung | Wo relevant |
|---------|--------|-------------|
| **nano erstellt neuen Inode** | `docker restart caddy` statt `caddy reload`. Ansible: Handler mit restart. | Caddy |
| **PostgreSQL 18 Mount** | `/var/lib/postgresql` NICHT `/var/lib/postgresql/data` | Docker Compose |
| **rsync 3.2 vs 3.4** | `--no-compress`. Nur bei Cert-Sync relevant. | Falls Hybrid mit Pull-Modell |
| **Netbird DNS Konflikte** | Custom Zones NUR für interne Domains | Netbird |
| **Nextcloud HSTS** | Apache im Container setzt Header selbst | Nextcloud-Rolle |
| **Nextcloud Single Logout** | `--send-id-token-hint=0` | Nextcloud OIDC |
| **Paperless ESC-Registrierung** | `ACCOUNT_ALLOW_SIGNUPS: false` explizit! | Paperless |
| **LXC Kernel-Parameter** | `is_lxc`-Variable, nur netzwerk-sysctl | base-Rolle |
| **Docker Port-Binding** | **Auf Gateway-Servern**: `127.0.0.1:PORT:PORT` — Caddy ist lokal. **Auf App-Servern** (remote): `0.0.0.0:PORT:PORT` — Caddy sitzt auf dem Gateway und erreicht den App-Server über Netbird-IP. Absichern über UFW: App-Port nur auf `wt0` erlauben! | Alle Compose Files |
| **UFW auf App-LXCs** | Bei lxc_per_app: App-Ports (8080, 8081 etc.) nur auf Netbird-Interface `wt0` erlauben, SSH nur auf `wt0`. Default deny incoming. So sind die Docker-Ports trotz `0.0.0.0`-Bind nicht im LAN erreichbar. | base-Rolle + UFW |
| **Health-Check hinter Auth** | Backend-Ports (localhost) prüfen, nicht öffentliche URL | Monitoring |
| **Caddy handle-Reihenfolge** | Spezifische Matcher VOR Fallback `handle {}` | Caddyfile |
| **CSP per App** | Nicht global! VW, NC, PocketID setzen eigenen CSP | Caddyfile |
| **PocketID /register** | Per Caddy 403 blocken | Caddyfile |
| **Shared Redis** | Bei `single_lxc`: DB-Nummern nutzen (db=0, db=1). Bei `lxc_per_app`: Jeder LXC hat eigenen Redis → DB-Nummern nicht nötig | Docker Compose |
| **USB in LXC** | NICHT deaktivieren (existiert nicht) | base-Rolle |
| **Tinyauth nicht prod-ready** | Im Betrieb bewährt — nur OIDC-Forward-Auth, kein Brute-Force-Risiko | Architektur |
| **gocryptfs nach Reboot nicht gemountet** | Systemd-Service `gocryptfs-mount.service` prüfen. Muss VOR `docker.service` starten. Master erreichbar? SSH-Key gültig? | gocryptfs |
| **gocryptfs Keyfile auf Server vergessen** | SOFORT löschen! Keyfile darf nur auf Master + Key-Backup liegen. Neues Keyfile generieren, altes revoken. | gocryptfs |
| **Grafana Alloy hoher RAM-Verbrauch** | `--storage.path` auf `/tmp/alloy` setzen, WAL-Größe begrenzen. Auf kleinen LXCs (2GB): `--server.http.memory-limit-mb=256` | Monitoring |
| **Loki Retention greift nicht** | `compactor` muss in der Loki-Config aktiviert sein. Ohne Compactor werden alte Chunks nicht gelöscht. | Monitoring |

### Ansible-spezifisch

| Problem | Lösung |
|---------|--------|
| Idempotenz | `state: present`, keine rohen `command`-Aufrufe |
| Secrets in Git | NIEMALS Klartext. Ansible Vault oder Vaultwarden. |
| Handler-Reihenfolge | Laufen am Ende des Plays. `meta: flush_handlers` für sofort. |
| docker-compose V1 vs V2 | `docker compose` (V2 Plugin), NICHT `docker-compose` |
| become in LXC | Ansible braucht `become: true` für Docker als non-root |
| Globale Config laden | `include_vars` in pre_tasks, nicht `ansible.cfg` |

---

## 23. Offene Design-Entscheidungen

### Gelöste Entscheidungen (zur Referenz)

| Frage | Entscheidung | Siehe Kapitel |
|-------|-------------|---------------|
| Öffentliche IP für Admin-Domain | Gateway-Caddy leitet via Netbird an Master-Server weiter | Kap. 3.3 |
| PocketID User-Management | API-Automation via PocketID REST-API (Bearer-Token) | Kap. 7.6 |
| Backup Off-Site Ziel | Dynamisch pro Kunde konfigurierbar (SFTP via Netbird, Storage Box, oder Betreiber-Infra) | Kap. 11 |
| Ansible Vault vs. Vaultwarden | Beides komplementär: Vault für Repo-Encryption, Vaultwarden für Credential-Store + Lookup | Kap. 10.1 |
| Shared Redis | Implizit durch `isolation_mode` gelöst (single_lxc: DB-Nummern, lxc_per_app: eigener Container) | Kap. 9.3 |
| Isolation auf Proxmox | `lxc_per_app` empfohlen, `single_lxc` als Option | Kap. 5 |
| LXC-Bootstrap-Methode | `pct exec` via Proxmox-Host (SSH-Key + Netbird injizieren, dann direkte Verbindung) | Kap. 5.6 |
| Netbird-Gruppen/Keys/Policies | Vollautomatisch via Netbird REST-API durch Ansible (kein manueller Eingriff) | Kap. 6.3 |
| Watchtower-Strategie | NUR für Kunden-Apps (Label-basiert + gepinnte Major-Versionen). Infra-Container OHNE Label — Updates nur über Ansible. | Kap. 19.2 |
| LXC-Template auf Proxmox | Ansible lädt Template via `pveam download` automatisch herunter wenn fehlend | Kap. 5.6 |
| Offboarding-Strategie | Gestuft: Archivieren (Standard) oder komplett löschen. Server manuell beim Provider löschen. Credentials archiviert | Kap. 17.7 |
| Tinyauth als Forward-Auth | PocketID + Tinyauth — im Betrieb bewährt. Nur OIDC via PocketID (kein direkter Login, kein Brute-Force-Risiko) | Kap. 7.9 |
| DynDNS (komplett lokal) | Master-Server übernimmt DNS-Updates für lokale Kunden — immer online, kennt die Netbird-IPs | Kap. 20 |
| Admin sudo | NOPASSWD — SSH nur über Netbird (`wt0`) + Key-Only. Netbird ist die zweite Sicherheitsstufe | Kap. 18.3 |
| Monitoring | Grafana Stack auf Master (Grafana + Prometheus + Loki). Alloy als einziger Agent. Uptime Kuma als optionale Kunden-App | Kap. 13 |
| Verschlüsselung at Rest | gocryptfs auf `/mnt/data` auf jedem Kundenserver. Keyfile nur auf Master + Key-Backup. Auto-Mount nach Reboot via Systemd | Kap. 12 |
| Compliance-Dokumentation | TOM, VVT, Löschkonzept als Jinja2-Templates. Automatisch generiert pro Kunde bei Onboarding/App-Änderung | Kap. 14 |
| Berechtigungskonzept | Baserow auf Master-Server. Pro Kunde eine Tabelle mit Benutzern und App-Zugriff. Dokumentation, nicht automatischer Sync | Kap. 7.8, 3.7 |
| Server-Onboarding | Frische Server mit IP/User/Passwort. Ansible bootstrappt alles (SSH-Key, base-Rolle, gocryptfs, Alloy). Netbird optional | Kap. 17.3 |
| Backup-Pflicht | Ohne Backup-Ziel = kein Backup. Bewusste Entscheidung pro Kunde. Pre-Backup-Hooks für DB-Dumps. Monatlicher Restore-Test | Kap. 11 |
| Logging & DSGVO | Loki mit 6 Monate Retention. journald FSS Sealing. Personenbezogene Daten minimiert. Automatische Löschung | Kap. 13.4 |

### Noch offene Entscheidungen

Keine — alle Entscheidungen sind getroffen.

---

## Anhang A: Port-Zuordnung

| Port | Dienst |
|------|--------|
| 1411 | PocketID |
| 3000 | Semaphore (nur Master) |
| 3100 | Grafana (nur Master) |
| 3110 | Loki (nur Master, intern) |
| 8080 | Nextcloud |
| 8081 | Paperless-NGX |
| 8222 | Vaultwarden |
| 8223 | Documenso |
| 8224 | Pingvin Share |
| 8225 | HedgeDoc |
| 8226 | Outline |
| 8227 | Gitea/Forgejo |
| 8228 | Cal.com |
| 8229 | Uptime Kuma |
| 8230 | Listmonk |
| 8231 | Baserow (nur Master) |
| 9090 | Tinyauth |
| 9091 | Prometheus (nur Master, intern) |
| 12345 | Grafana Alloy (Kundenserver, intern) |

---

## Anhang B: Checkliste neue App-Rolle

- [ ] `defaults/main.yml` mit allen Variablen
- [ ] `docker-compose.yml.j2` — Port-Binding je nach Server-Rolle
- [ ] `.env.j2` — Secrets als Variablen
- [ ] `oidc.yml` — OIDC-Client via PocketID REST-API erstellen, Credentials in Vaultwarden speichern
- [ ] Public Paths definieren (oder leer = komplett geschützt)
- [ ] Backup-Pfade definieren (auf `/mnt/data/`)
- [ ] Pre-Backup-Hook: DB-Dump definieren falls DB vorhanden
- [ ] Health-Check: Port + Path für Grafana Monitoring
- [ ] Audit-Logging: Aktiviert und dokumentiert
- [ ] Handler: `docker restart caddy`
- [ ] PG 18: Mount `/var/lib/postgresql`
- [ ] Redis: DB-Nummer zuweisen (single_lxc) oder eigener Container (lxc_per_app)
- [ ] CSP: Nur setzen wenn App keinen eigenen hat
- [ ] `remove.yml`: Daten archivieren, nicht löschen
- [ ] Idempotenz testen (2x laufen lassen)
- [ ] Keine hardcodierten Domains/E-Mails (alles aus Config/Inventar)
- [ ] VVT-Eintrag: Verarbeitungstätigkeit im Template definiert
- [ ] Daten in `/mnt/data/` (gocryptfs-geschützt)

---

## Anhang C: Abhängigkeiten & Galaxy Requirements

```yaml
# requirements.yml
collections:
  - name: community.general      # Für Proxmox LXC-Erstellung + Bitwarden Lookup-Plugin
  - name: community.docker        # Für Docker Compose Management
  - name: ansible.posix           # Für sysctl, authorized_key etc.
```

> **Hinweis:** `community.general.bitwarden` Lookup-Plugin ist Teil der `community.general` Collection und benötigt die `bw` CLI auf dem Master-Server.
