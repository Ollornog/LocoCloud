# LocoCloud — Managed Self-Hosted Infrastructure

## Konzept & Bauplan für das GitHub-Repository

**Repo:** `github.com/Ollornog/LocoCloud` (privat, Ziel: public)
**Version:** 3.3 — Februar 2026
**Autor:** Daniel (ollornog.de)

---

## Inhaltsverzeichnis

1. [Systemübersicht & Philosophie](#1-systemübersicht--philosophie)
2. [Abgrenzung: Privat vs. LocoCloud](#2-abgrenzung-privat-vs-lococloudd)
3. [Admin-Infrastruktur (Master-Server)](#3-admin-infrastruktur-master-server)
4. [Deployment-Varianten pro Kunde](#4-deployment-varianten-pro-kunde)
5. [Isolation: Docker vs. LXC pro App](#5-isolation-docker-vs-lxc-pro-app)
6. [Netzwerk-Architektur (Netbird)](#6-netzwerk-architektur-netbird)
7. [Authentifizierung & Autorisierung](#7-authentifizierung--autorisierung)
8. [Caddy Reverse Proxy System](#8-caddy-reverse-proxy-system)
9. [App-Template-System](#9-app-template-system)
10. [Credential-Management (Vaultwarden)](#10-credential-management-vaultwarden)
11. [Backup-Architektur](#11-backup-architektur)
12. [Monitoring & Alerting](#12-monitoring--alerting)
13. [Repo-Struktur & Konfiguration](#13-repo-struktur--konfiguration)
14. [Semaphore-Konfiguration](#14-semaphore-konfiguration)
15. [Deployment-Abläufe](#15-deployment-abläufe)
16. [Sicherheits-Hardening](#16-sicherheits-hardening)
17. [Wartung & Updates](#17-wartung--updates)
18. [Kunden-Inventar-System](#18-kunden-inventar-system)
19. [Repo Public-Readiness](#19-repo-public-readiness)
20. [Bekannte Fallstricke & Lessons Learned](#20-bekannte-fallstricke--lessons-learned)
21. [Offene Design-Entscheidungen](#21-offene-design-entscheidungen)

---

## 1. Systemübersicht & Philosophie

### Was LocoCloud ist

Ein Ansible-basiertes Deployment-System in einem Git-Repository, das schlüsselfertige Self-Hosted-Infrastruktur für kleine Firmen (5–50 Mitarbeiter) bereitstellt. Das Repo wird auf einem Master-Server geklont und von dort aus werden beliebig viele Kunden-Infrastrukturen deployt, gewartet und überwacht.

### Kernprinzipien

1. **Alles ist öffentlich erreichbar** — Kein VPN für Endbenutzer, nur Browser nötig
2. **Alles ist hinter Auth** — Default: blockiert. Öffentliche Pfade werden explizit gewhitelistet
3. **PocketID + Tinyauth pro Kunde** — Eigene Instanzen, kein Sharing zwischen Kunden
4. **Netbird nur für Admin & Infrastruktur** — Endbenutzer bekommen kein VPN
5. **Ein Repo, viele Kunden** — Monorepo mit Inventar-Trennung
6. **Credentials automatisch in Vaultwarden** — Bei jedem Deploy/Update
7. **Der Betreiber ist überall Admin** — PocketID-Admin auf jeder Kundeninstanz
8. **Kunden vollständig isoliert** — Kein Kunde sieht einen anderen
9. **Repo-Agnostik** — Alles Spezifische (Domain, E-Mail, Netbird-URL) ist konfigurierbar. Das Repo soll public-fähig sein

### Was LocoCloud NICHT ist

- Kein SaaS — Jeder Kunde hat eigene Server, eigene Instanzen, eigene Daten
- Kein Shared Hosting — Keine geteilte Infrastruktur zwischen Kunden
- Kein Cloud-Provider — Kunden besitzen ihre Server (oder mieten sie bei Hetzner etc.)

---

## 2. Abgrenzung: Privat vs. LocoCloud

### Komplett getrennte Welten

Daniels privates Setup (ollornog.de) und LocoCloud teilen sich **NICHTS** außer dem Netbird-Management-Server. Das ist die einzige Berührungsstelle.

```
┌─────────────────────────────────────────────────────────────┐
│                    DANIELS PRIVAT                            │
│                                                             │
│  Hetzner vServer (privat)         Proxmox Homeserver        │
│  ├── Caddy (ollornog.de)          ├── Cloud-LXC (110)       │
│  ├── PocketID (id.ollornog.de)    │   ├── Nextcloud         │
│  ├── Tinyauth (auth.ollornog.de)  │   └── Paperless         │
│  ├── Vaultwarden (vault)          └── Sonstige private LXCs │
│  ├── Documenso (sign)                                       │
│  ├── Pingvin (share)                                        │
│  ├── Website (ollornog.de)                                  │
│  └── *** Netbird Manager *** ←── EINZIGE BERÜHRUNG          │
│         (netbird.ollornog.de)                               │
└─────────────────────────────────────────────────────────────┘
           │
           │  Netbird VPN (geteilter Manager, aber getrennte Gruppen+Policies)
           │
┌──────────▼──────────────────────────────────────────────────┐
│                      LOCOCLOUDD                              │
│                                                             │
│  Master-Server (LXC auf Daniels Proxmox)                    │
│  ├── Caddy (loco.ollornog.de)        ← EIGENE Instanz      │
│  ├── PocketID (id.loco.ollornog.de)  ← EIGENE Instanz      │
│  ├── Tinyauth (auth.loco.ollornog.de)← EIGENE Instanz      │
│  ├── Vaultwarden (vault.loco.ollornog.de) ← EIGENE Instanz │
│  ├── Semaphore (deploy.loco.ollornog.de)                    │
│  ├── Zabbix (monitor.loco.ollornog.de)                      │
│  ├── Ansible + Git (LocoCloud Repo)                         │
│  └── Netbird Client                                         │
│                                                             │
│  Backup-Server (LXC oder Hetzner Storage Box)               │
│                                                             │
│  Pro Kunde:                                                 │
│  ├── Hetzner vServer (NEUER, separater Server)              │
│  ├── Proxmox beim Kunden (optional)                         │
│  └── ...                                                    │
└─────────────────────────────────────────────────────────────┘
```

### Was geteilt wird

| Komponente | Geteilt? | Details |
|------------|----------|---------|
| Netbird Manager | ✓ | `netbird.ollornog.de` — der einzige Berührungspunkt. Isolation über Gruppen/Policies |
| Hetzner vServer (privat) | ✗ | Kunden bekommen eigene Hetzner-Server |
| PocketID | ✗ | Eigene Instanz auf Master + eigene Instanz pro Kunde |
| Vaultwarden | ✗ | Eigene Instanz auf Master für Admin-Credentials |
| Tinyauth | ✗ | Eigene Instanz auf Master + eigene Instanz pro Kunde |
| Caddy | ✗ | Eigene Instanz auf Master + eigene Instanz pro Kunde/Server |
| Proxmox Homeserver | Physisch ja | Gleiche Hardware, aber LXCs sind isoliert (Master-LXC ≠ Cloud-LXC) |

### Warum der Netbird-Manager geteilt wird

Einen zweiten Netbird-Manager aufzusetzen wäre möglich, aber unnötig:
- Netbird-Gruppen + Policies isolieren zuverlässig
- Private und LocoCloud-Peers sehen sich nicht (keine Cross-Policy)
- Ein Manager = eine Verwaltung, weniger Overhead

---

## 3. Admin-Infrastruktur (Master-Server)

### 3.1 Master-Server (LXC auf Daniels Proxmox)

Dedizierter LXC-Container, komplett getrennt von Daniels privatem Cloud-LXC (110).

**Spezifikationen:**
- **OS:** Debian 13 (Trixie), unprivileged, nesting=1
- **RAM:** 8192 MB (Semaphore + Zabbix + Vaultwarden + PocketID + Ansible)
- **CPU:** 4 Cores
- **Disk:** 64 GB auf NVMe (local-lvm)
- **Netzwerk:** Netbird-Client + LAN-Zugang (192.168.3.x)

### 3.2 Dienste auf dem Master

Alle Dienste laufen als Docker Container auf `127.0.0.1`. Caddy terminiert TLS.

| Dienst | Subdomain | Port (intern) | Zweck |
|--------|-----------|---------------|-------|
| Caddy | — | Host Network | Reverse Proxy für alle Admin-Dienste |
| PocketID | id.loco.ollornog.de | 127.0.0.1:1411 | OIDC-Provider für Admin-Dienste |
| Tinyauth | auth.loco.ollornog.de | 127.0.0.1:9090 | Forward-Auth für Admin-Dienste |
| Vaultwarden | vault.loco.ollornog.de | 127.0.0.1:8222 | Credential-Management (alle Kunden) |
| Semaphore | deploy.loco.ollornog.de | 127.0.0.1:3000 | Ansible Web-UI |
| Zabbix | monitor.loco.ollornog.de | 127.0.0.1:8080 | Zentrales Monitoring |
| Ansible | — | — | Direkt installiert (apt/pip) |
| Git | — | — | LocoCloud-Repo (geklont) |
| msmtp | — | — | Alert-Mails |
| Netbird Client | — | — | VPN zu allen Kunden |

### 3.3 Subdomain-Schema: `*.loco.ollornog.de`

Alle Admin-Dienste laufen unter `loco.ollornog.de` als Sub-Subdomain:

```
loco.ollornog.de           → Landingpage / Dashboard (optional)
id.loco.ollornog.de        → PocketID (Admin-SSO)
auth.loco.ollornog.de      → Tinyauth (Admin Forward-Auth)
vault.loco.ollornog.de     → Vaultwarden (Admin-Credentials)
deploy.loco.ollornog.de    → Semaphore (Ansible-UI)
monitor.loco.ollornog.de   → Zabbix (Monitoring)
```

**DNS-Setup:**
- Wildcard A-Record: `*.loco.ollornog.de → 46.225.165.213` (Daniels Hetzner-Server, A-Record bei UDAG)

**Entscheidung:** Der Master-LXC auf Daniels Proxmox ist NICHT direkt öffentlich erreichbar. Stattdessen bekommt der Caddy auf Daniels bestehendem Hetzner-Server (46.225.165.213) zusätzliche Routen für `*.loco.ollornog.de`.

**Traffic-Flow:** Internet → Hetzner Caddy (46.225.165.213) → Netbird → Master-LXC

Das ist die pragmatischste Lösung:
- Kein zusätzlicher Server nötig
- Kein Sicherheitsrisiko: Master-LXC ist nur über Netbird erreichbar, Caddy auf Hetzner leitet nur weiter
- Für Kunden mit eigenem Hetzner-Server kann alternativ der Traffic über deren Server geroutet werden

### 3.4 TLS für Master-Dienste

- Caddy auf Daniels Hetzner (46.225.165.213) terminiert TLS für `*.loco.ollornog.de`
- Leitet über Netbird an den Master-LXC weiter (HTTP, kein TLS nötig im Tunnel)
- Master-Caddy lauscht auf HTTP und fügt Header hinzu

### 3.5 Repo auf dem Master

```bash
# Initialer Clone (SSH-Key für GitHub, Deploy-Key oder Personal Access Token)
git clone git@github.com:Ollornog/LocoCloud.git /opt/lococloudd
# oder mit Deploy-Key:
GIT_SSH_COMMAND="ssh -i /root/.ssh/github-deploy-key" \
  git clone git@github.com:Ollornog/LocoCloud.git /opt/lococloudd
```

Das Repo wird per Deploy-Key geklont (read-only reicht für den Master). Änderungen werden lokal auf Daniels Rechner gemacht, gepusht, und auf dem Master per `git pull` aktualisiert (manuell oder per Semaphore-Task).

### 3.6 Backup-Server (Admin-Seite)

Dedizierter LXC oder externe Storage für Kunden-Backups:

| Option | Standort | Kapazität | Zweck |
|--------|----------|-----------|-------|
| Backup-LXC auf Proxmox | Lokal (SATA SSD) | 3.7 TB verfügbar | Primäres Backup-Ziel |
| Hetzner Storage Box | Hetzner DC (EU) | Skalierbar (ab 1TB) | Off-Site-Backup |
| Zweiter Hetzner vServer | Hetzner DC (EU) | Je nach Plan | Redundanz |

---

## 4. Deployment-Varianten pro Kunde

### 4.1 Variante A: Cloud-Only (Alles auf Hetzner)

```
Internet (HTTPS)
    │
    ▼
Hetzner vServer (firma.de)      ← NEUER Server, NICHT Daniels privater!
    ├── Caddy (TLS, forward_auth → Tinyauth)
    ├── PocketID (id.firma.de)
    ├── Tinyauth (auth.firma.de)
    ├── Alle Apps (Docker Container)
    ├── Alle Datenbanken (Docker Container)
    ├── Netbird Client (Admin-Zugang)
    └── Zabbix Agent
```

**Einfachste Variante.** Alles auf einem Server. Caddy terminiert TLS, Tinyauth schützt alles. Alle Dienste als Docker Container.

### 4.2 Variante B: Hybrid (Hetzner + Lokaler Proxmox)

```
Internet (HTTPS)
    │
    ▼
Hetzner vServer (firma.de)      ← NEUER Server pro Kunde (= Gateway/Entry-Point)
    ├── Caddy (TLS, forward_auth → Tinyauth)
    ├── PocketID (id.firma.de)
    ├── Tinyauth (auth.firma.de)
    ├── Optionale Apps auf Hetzner (Docker)
    ├── Netbird Client
    │
    │   Netbird VPN Tunnel (WireGuard-verschlüsselt)
    │
    ├──► LXC "nextcloud" (100.114.x.1:8080)   ← Eigener Netbird-Client
    ├──► LXC "paperless" (100.114.x.2:8081)    ← Eigener Netbird-Client
    └──► LXC "vaultwarden" (100.114.x.3:8222)  ← Eigener Netbird-Client
         (alle auf Proxmox beim Kunden)
```

**Kein lokaler Caddy, kein Gateway-LXC, keine Proxmox-Bridge!** Der Hetzner-Caddy routet direkt über Netbird an jeden einzelnen App-LXC. Jeder LXC hat seinen eigenen Netbird-Client.

**Traffic-Flow:**
1. Mitarbeiter → HTTPS → Hetzner vServer
2. Caddy: TLS-Terminierung + `forward_auth` → Tinyauth
3. Lokale Apps: `reverse_proxy` direkt an Netbird-IP des jeweiligen LXC
4. Online-Apps: `reverse_proxy` auf `127.0.0.1:PORT`

**Kein TLS auf den lokalen LXCs nötig!** Caddy auf Hetzner terminiert TLS, Netbird-Tunnel ist WireGuard-verschlüsselt. Das eliminiert den Certbot+rsync+Pull-Mechanismus komplett.

**Bei `single_lxc`-Modus:** Nur ein LXC mit allem, ein Netbird-Client, ein Peer. Caddy auf Hetzner routet alles an eine einzige Netbird-IP.

### 4.3 Variante C: Lokal-Only (Alles beim Kunden)

```
Internet (HTTPS)
    │
    ▼
Kunden-Router (Port-Forward 80/443 oder DynDNS)
    │
    ▼
Proxmox beim Kunden
    ├── LXC "gateway" (exponiert, Port-Forward Ziel)
    │   ├── Docker: Caddy (TLS via Let's Encrypt)
    │   ├── Docker: PocketID (id.firma.de)
    │   ├── Docker: Tinyauth (auth.firma.de)
    │   └── Netbird Client (100.114.x.0)
    │
    │   Netbird-Tunnel (lokal, trotzdem verschlüsselt)
    │
    ├── LXC "nextcloud" + Netbird (100.114.x.1)
    ├── LXC "paperless" + Netbird (100.114.x.2)
    └── LXC "infra" + Netbird (100.114.x.4)
```

> **Nur bei Lokal-Only gibt es einen Gateway-LXC.** Dieser übernimmt die Rolle, die bei Hybrid/Cloud der Hetzner hat: Caddy + PocketID + Tinyauth. Routing zu den App-LXCs läuft über Netbird — konsistent mit den anderen Varianten.

**Voraussetzung:** Feste IP oder DynDNS + Port-Forward.

### 4.4 Der öffentliche Einstiegspunkt

**Immer ist der öffentlich erreichbare Server der Single-Entry-Point.** Der Caddy auf diesem Server routet zu allen anderen Servern:

- **Cloud-Only:** Hetzner ist Entry-Point, alles lokal
- **Hybrid:** Hetzner ist Entry-Point, routet via Netbird zu lokalem Proxmox
- **Lokal-Only:** Proxmox-LXC ist Entry-Point (via DynDNS/Port-Forward)

---

## 5. Isolation: Docker vs. LXC pro App

### 5.1 Das Problem

Auf Hetzner-Servern (Cloud-Only oder Hybrid-Online-Teil): **Alles Docker.** Kein Proxmox, kein LXC. Einfach, bewährt.

Auf dem lokalen Proxmox beim Kunden gibt es zwei Ansätze:

### 5.2 Option 1: Ein LXC, alles Docker (wie auf Hetzner)

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
- Einheitlich mit Hetzner-Variante (selbe Ansible-Rollen)
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
    ├── Zabbix Agent
    ├── Restic Backup
    └── Netbird Client (100.114.x.4)
```

**Jeder LXC bekommt seinen eigenen Netbird-Client** und damit eine eigene Netbird-IP. Es gibt KEINEN Gateway-LXC auf dem Proxmox — der Kunden-Hetzner-Server ist der Gateway!

**Traffic-Flow (Hybrid):**
```
Internet → Hetzner vServer (Caddy + Auth)
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

> **Bei Lokal-Only** braucht man einen Gateway-LXC mit Caddy, weil es keinen Hetzner gibt. Dieser Gateway-LXC hat auch einen Netbird-Client und routet über Netbird an die App-LXCs.

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

Bei Hybrid- und Cloud-Only-Varianten ist der **Kunden-Hetzner-Server der Gateway**. Der Caddy auf dem Hetzner terminiert TLS und leitet über Netbird direkt an die einzelnen App-LXCs. Das bedeutet:

- **Keine Proxmox-Bridge nötig** — kein vmbr1, kein internes Subnetz, kein Routing
- **Kein zusätzlicher Caddy auf dem Proxmox** — der Hetzner-Caddy macht alles
- **Kein Single Point of Failure** auf Proxmox-Seite — jeder LXC ist eigenständig erreichbar
- **Direkter Ansible-Zugriff** — Master-Server erreicht jeden LXC direkt über Netbird (kein SSH-Hopping über Gateway)

Die einzige Ausnahme ist **Lokal-Only** — dort muss ein Gateway-LXC mit Caddy existieren, weil es keinen Hetzner gibt.

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

### 5.7 Netzwerk-Übersicht bei LXC-pro-App (Hybrid)

```
┌─────────────────────────────────────────────────────────────┐
│ Hetzner vServer (firma.de)                                  │
│ ├── Caddy (TLS, forward_auth → Tinyauth)                   │
│ ├── PocketID (id.firma.de)                                  │
│ ├── Tinyauth (auth.firma.de)                                │
│ └── Netbird Client (100.114.a.0)                            │
│         │                                                   │
│         │ Netbird WireGuard Tunnel (verschlüsselt)          │
└─────────┼───────────────────────────────────────────────────┘
          │
          ├───────────────────────────────────────────────┐
          │                                               │
┌─────────▼─────────────┐  ┌──────────────▼──────────────┐
│ Proxmox beim Kunden   │  │                             │
│                       │  │                             │
│ LXC: nextcloud        │  │  LXC: paperless             │
│ ├── Netbird (x.1)     │  │  ├── Netbird (x.2)          │
│ ├── Docker: Nextcloud  │  │  ├── Docker: Paperless      │
│ ├── Docker: MariaDB   │  │  ├── Docker: PostgreSQL      │
│ └── Docker: Redis     │  │  ├── Docker: Gotenberg       │
│     Port: 8080        │  │  └── Docker: Tika            │
│                       │  │      Port: 8081              │
└───────────────────────┘  └──────────────────────────────┘

Caddyfile auf Hetzner:
  cloud.firma.de → reverse_proxy 100.114.x.1:8080
  paper.firma.de → reverse_proxy 100.114.x.2:8081
```

**Kein TLS auf den LXCs nötig** — Netbird-Tunnel ist WireGuard-verschlüsselt, Caddy auf Hetzner terminiert TLS für den Endbenutzer.

**Kein lokaler Caddy nötig** — der Hetzner-Caddy routet direkt an jeden LXC.

**Alle Docker-Container binden auf 127.0.0.1** — Netbird-Traffic kommt über `wt0` Interface auf dem LXC an und wird vom Docker-Container auf localhost bedient. Caddy auf Hetzner erreicht den Port über die Netbird-IP.

---

## 6. Netzwerk-Architektur (Netbird)

### 6.1 Geteilter Manager, getrennte Gruppen

Daniels bestehender Netbird-Manager (`netbird.ollornog.de`) wird für LocoCloud mitgenutzt. Die Isolation geschieht über Gruppen und Policies.

```
Netbird Manager (netbird.ollornog.de)
│
├── PRIVATE GRUPPEN (Daniels Kram, unverändert)
│   ├── Group: admin-privat    → Drog-Tower, Cloud-LXC
│   └── Policy: admin-privat ↔ admin-privat
│
├── LOCOCLOUDD GRUPPEN
│   ├── Group: loco-admin      → Master-LXC, Daniels Geräte (für Admin)
│   ├── Group: loco-backup     → Backup-Server
│   ├── Group: kunde-abc       → Alle Server von Kunde ABC
│   ├── Group: kunde-xyz       → Alle Server von Kunde XYZ
│   └── ...
│
├── LOCOCLOUDD POLICIES
│   ├── loco-admin → kunde-*        (Admin-Zugang zu allen Kunden)
│   ├── loco-admin → loco-backup    (Admin-Zugang zu Backup)
│   ├── loco-backup → kunde-*       (Backup-Pull von allen Kunden)
│   ├── kunde-abc → kunde-abc       (Intern: Hetzner ↔ Proxmox)
│   ├── kunde-xyz → kunde-xyz       (Intern)
│   └── KEINE Policy: kunde-abc ↔ kunde-xyz  (Isolation!)
│
└── KEINE Cross-Policies zwischen privat und loco!
    (admin-privat sieht loco-* nicht und umgekehrt)
```

### 6.2 Peer-Benennung

Konsistente Benennung für Übersichtlichkeit:

```
loco-master                    ← Master-LXC
loco-backup                    ← Backup-Server
abc-hetzner                    ← Kunde ABC, Hetzner vServer
abc-proxmox                    ← Kunde ABC, lokaler Proxmox
abc-gw                         ← Kunde ABC, Gateway-LXC (bei LXC-pro-App)
abc-apps                       ← Kunde ABC, Apps-LXC
xyz-hetzner                    ← Kunde XYZ
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

Bei Hybrid: Wenn der Hetzner-Caddy an lokale LXCs routen muss, braucht er die Netbird-IP. Diese wird als Ansible-Variable hinterlegt, NICHT als Netbird DNS Zone (verursacht Konflikte mit öffentlichem DNS).

---

## 7. Authentifizierung & Autorisierung

### 7.1 Zwei Auth-Ebenen

1. **Admin-Auth** (LocoCloud-Management): PocketID + Tinyauth auf `*.loco.ollornog.de`
2. **Kunden-Auth** (pro Kunde): Eigene PocketID + Tinyauth auf `*.firma.de`

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
**Admin:** Daniel (generiertes Passwort → Admin-Vaultwarden)
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
- **OIDC-Clients erstellen:** `POST /api/oidc-clients` (Name, Callback-URLs, Scopes)

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

### 7.8 Tinyauth-Warnung

> **Entschieden: Tinyauth.** Tinyauth ist laut Maintainer nicht production-ready, reicht aber aus: Es wird ausschließlich als OIDC-Forward-Auth genutzt (Login nur über PocketID Passkeys). Brute-Force-Schutz ist irrelevant, da kein direkter Login stattfindet. Die Ansible-Rollen werden austauschbar gebaut — bei Problemen ist ein Wechsel auf **Authelia** möglich.

---

## 8. Caddy Reverse Proxy System

### 8.1 Prinzip

**Default: ALLES blockiert.** Öffentliche Pfade werden explizit gewhitelistet.

Pro öffentlich erreichbarem Server ein Caddy. Bei Hybrid: Caddy auf Hetzner ist der Single-Entry-Point, KEIN Caddy auf dem lokalen Server nötig (Netbird-Tunnel ist verschlüsselt).

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
# Generiert: {{ ansible_date_time.iso8601 }}
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
    url: "https://id.{{ kunde_domain }}/api/oidc-clients"
    method: POST
    headers:
      Authorization: "Bearer {{ pocketid_api_token }}"
    body_format: json
    body:
      name: "{{ app_name }}"
      callback_urls:
        - "https://{{ app_subdomain }}.{{ kunde_domain }}{{ app_oidc_redirect_path }}"
    status_code: 201
  register: oidc_result

- name: Store OIDC credentials in Vaultwarden
  include_role:
    name: credentials
  vars:
    credential_name: "{{ kunde_name }} — {{ app_name }} OIDC"
    credential_username: "{{ oidc_result.json.client_id }}"
    credential_password: "{{ oidc_result.json.client_secret }}"
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
7. Registriert Zabbix-Check

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
│     └── server_role: app                                       │
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
│  8. Zabbix-Check registrieren                                  │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

> **Chicken-and-Egg gelöst:** Die Netbird-IP ist erst nach dem Join bekannt (Schritt 3). Deshalb wird `hosts.yml` dynamisch in Schritt 4 aktualisiert. Ab Schritt 5 verbindet sich Ansible direkt über die neue Netbird-IP.

**Entfernen:**
1. Playbook `remove-app.yml` mit `app_name`
2. Stoppt Container, archiviert Daten
3. Entfernt OIDC-Client
4. Regeneriert Caddyfile + restart
5. Entfernt Zabbix-Check

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
| Ansible-Vault-Passwort selbst | Admin-Vaultwarden (vault.loco.ollornog.de) | Shell-Script `vault-pass.sh` holt es via `bw` CLI |
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

`vault.loco.ollornog.de` — komplett getrennt von Daniels privatem Vaultwarden (`vault.ollornog.de`).

### 10.3 Ordnerstruktur

```
LocoCloud Organisation/
├── Infrastruktur/
│   ├── Master-LXC SSH Key
│   ├── GitHub Deploy Key
│   ├── Netbird API Credentials
│   ├── Zabbix Admin
│   └── Master PocketID Admin
├── Kunde ABC (firma-abc.de)/
│   ├── Server/
│   │   ├── Hetzner SSH Key
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
        Deployed: {{ ansible_date_time.iso8601 }}
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
    ├── Option 2: Hetzner Storage Box
    └── Option 3: Off-Site auf Betreiber-Infrastruktur via Netbird
```

Das Backup-Ziel ist **pro Kunde konfigurierbar**, nicht eine globale Entscheidung. Alle Ziele sind über Netbird oder direkt per SFTP erreichbar. Restic verschlüsselt client-seitig — der Backup-Server sieht nur verschlüsselte Blobs.

### 11.2 Was wird gesichert

1. Docker Volumes aller Apps
2. Datenbank-Dumps (Pre-Backup: `pg_dump`, `mysqldump`)
3. PocketID Daten (SQLite + Config)
4. Tinyauth Config
5. Caddy Caddyfile
6. Docker Compose + .env Files

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

    # Option 2: Hetzner Storage Box
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
```

---

## 12. Monitoring & Alerting

### 12.1 Zabbix auf Master-Server

`monitor.loco.ollornog.de` — eigene Instanz, getrennt von Daniels privatem Monitoring.

### 12.2 Was wird überwacht

| Check | Methode | Hinweis |
|-------|---------|---------|
| CPU, RAM, Disk | Zabbix Agent | Standard |
| Docker Container | Zabbix Agent + Script | |
| HTTP-Status Apps | Zabbix HTTP Agent | **Über Backend-Port (localhost), NICHT öffentliche URL!** Tinyauth gibt sonst 401 |
| SSL-Zertifikat | HTTP Agent | Über öffentliche URL (kein Auth auf TLS-Ebene) |
| Netbird Peer | Script | Ping über Netbird-IP |
| Backup-Status | Script | Letzter Restic-Snapshot |

### 12.3 Uptime Kuma (optionale Kunden-App)

`status.firma.de` — optionales Status-Dashboard pro Kunde. Zeigt Kunden ob ihre Dienste online sind.

- **Kein Agent nötig:** Prüft HTTP/Ping von innen (läuft auf dem Kunden-LXC)
- **Kein OIDC:** Geschützt durch Tinyauth Forward-Auth
- **Port:** 8229
- **Optional:** Wird nur deployt wenn `uptime_kuma_enabled: true` im Kunden-Inventar
- **Status-Page:** Kann eine öffentliche Status-Seite generieren (konfigurierbar)

> Uptime Kuma ersetzt NICHT Zabbix. Zabbix = Admin-Monitoring (Infra, Ressourcen). Uptime Kuma = Kunden-Dashboard ("Sind meine Dienste online?").

### 12.4 Zabbix Agent auf Kunden-Servern

Meldet über Netbird an den Master-Zabbix. TLS-PSK für verschlüsselte Kommunikation:

```ini
Server={{ loco_master_netbird_ip }}
Hostname={{ kunde_id }}-{{ inventory_hostname }}
TLSConnect=psk
TLSPSKIdentity={{ kunde_id }}-{{ inventory_hostname }}
TLSPSKFile=/etc/zabbix/zabbix_agent2.psk
```

---

## 13. Repo-Struktur & Konfiguration

### 13.1 Vollständige Struktur

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
│   ├── netbird_client/               # Netbird Installation + Join
│   ├── monitoring/                   # Zabbix Agent
│   ├── backup/                       # Restic
│   ├── credentials/                  # Vaultwarden API
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
│   ├── add-app.yml
│   ├── remove-app.yml
│   ├── update-app.yml
│   ├── update-caddy.yml
│   ├── add-user.yml
│   ├── remove-user.yml
│   ├── update-all.yml
│   ├── backup-now.yml
│   ├── restore.yml
│   ├── onboard-customer.yml
│   └── offboard-customer.yml
│
├── scripts/
│   ├── init-master.sh                # Bootstrap-Script für Master-Server
│   ├── new-customer.sh               # Inventar aus Template generieren
│   └── health-check.sh
│
└── docs/
    ├── SETUP.md                      # Master-Server Setup
    ├── ONBOARDING.md                 # Neukunden-Prozess
    ├── APP-DEVELOPMENT.md            # Neue App-Rolle erstellen
    └── TROUBLESHOOTING.md
```

### 13.2 Globale Konfiguration: `config/lococloudd.yml`

**ALLES Spezifische wird hier konfiguriert.** So kann das Repo public gehen, ohne Daniels persönliche Daten zu leaken.

```yaml
# config/lococloudd.yml
# =====================================================================
# GLOBALE LOCOCLOUDD-KONFIGURATION
# Alle betreiberspezifischen Einstellungen zentral an einem Ort.
# Diese Datei wird in .gitignore aufgenommen!
# Stattdessen wird config/lococloudd.yml.example committed.
# =====================================================================

# --- Betreiber ---
operator:
  name: "Daniel"
  email: "daniel@ollornog.de"           # Admin-E-Mail für PocketID etc.
  domain: "ollornog.de"                 # Basis-Domain des Betreibers

# --- Admin-Subdomain ---
admin:
  subdomain: "loco"                     # → *.loco.ollornog.de
  full_domain: "loco.ollornog.de"       # Generiert aus operator.domain + admin.subdomain

# --- Admin-Dienste URLs ---
urls:
  pocketid: "id.loco.ollornog.de"
  tinyauth: "auth.loco.ollornog.de"
  vaultwarden: "vault.loco.ollornog.de"
  semaphore: "deploy.loco.ollornog.de"
  zabbix: "monitor.loco.ollornog.de"

# --- Netbird (geteilter Manager) ---
netbird:
  manager_url: "https://netbird.ollornog.de"  # Daniels bestehender Netbird
  api_token: ""                                # Netbird API Token
  # NICHT im Repo! Wird über Umgebungsvariable oder Vault geladen.

# --- PocketID (Admin-Instanz, REST-API) ---
pocketid:
  api_token: ""                                # PocketID REST-API Token
  # Für User/Gruppen/OIDC-Client-Automation via uri-Modul

# --- SMTP ---
smtp:
  host: "smtps.udag.de"
  port: 587
  starttls: true
  user: "ollornog-de-0001"
  from: "loco@ollornog.de"
  # Passwort: Über Vault oder Umgebungsvariable

# --- GitHub Repo ---
repo:
  url: "git@github.com:Ollornog/LocoCloud.git"
  branch: "main"
  deploy_key_path: "/root/.ssh/lococloudd-github-key"

# --- Vaultwarden (Admin-Instanz) ---
vaultwarden:
  url: "https://vault.loco.ollornog.de"
  api_token_path: "/root/.loco-vaultwarden-token"
  organization_id: ""                   # Wird nach Setup eingetragen

# --- Bitwarden CLI (für Ansible Vault Passwort + Lookup-Plugin) ---
bitwarden_cli:
  server_url: "https://vault.loco.ollornog.de"  # Muss auf Vaultwarden zeigen
  vault_item_name: "lococloudd-ansible-vault"    # Item mit Vault-Passwort

# --- Öffentlicher Einstiegspunkt für Admin-Dienste ---
admin_gateway:
  hetzner_ip: "46.225.165.213"         # Caddy leitet *.loco.ollornog.de via Netbird an Master-LXC
```

### 13.3 `.gitignore`

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

### 13.4 `config/lococloudd.yml.example`

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
  zabbix: "monitor.admin.example.com"

netbird:
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
  hetzner_ip: ""                             # IP des Hetzner-Servers fuer Admin-Routing
```

### 13.5 `ansible.cfg`

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

## 14. Semaphore-Konfiguration

### 14.1 Zugang

`deploy.loco.ollornog.de` — hinter Tinyauth (nur Daniel)

### 14.2 Projekte

| Projekt | Inventar | Zweck |
|---------|----------|-------|
| Master | `master` | Master-Server Verwaltung |
| Kunde ABC | `kunde-abc` | Alles für Kunde ABC |
| Kunde XYZ | `kunde-xyz` | Alles für Kunde XYZ |
| Global | alle | Cross-Kunde-Updates |

### 14.3 Templates pro Kunde

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

### 14.4 Öffentliche Pfade in Semaphore editieren

Da die öffentlichen Pfade im Inventar (`apps_enabled[].public_paths`) definiert sind, können sie über Semaphore geändert werden:

1. Im Semaphore-Projekt → Environment → Inventar-Datei editieren
2. `public_paths` anpassen
3. Template "Update Caddy" ausführen → Caddyfile wird regeneriert

---

## 15. Deployment-Abläufe

### 15.1 Master-Server erstmalig einrichten

```bash
# 1. LXC auf Proxmox erstellen (manuell oder per Script)
# 2. SSH-Zugang einrichten (Key von Daniel)
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
2. Netbird-Client installieren + joinen (Gruppe: `loco-admin`)
3. PocketID deployen (`id.loco.ollornog.de`)
4. Tinyauth deployen (`auth.loco.ollornog.de`)
5. Vaultwarden deployen (`vault.loco.ollornog.de`)
6. Semaphore deployen (`deploy.loco.ollornog.de`)
7. Zabbix Server deployen (`monitor.loco.ollornog.de`)
8. Caddy deployen mit Admin-Caddyfile
9. Alle Credentials in Vaultwarden speichern

### 15.2 Neuer Kunde

**Proxmox-Onboarding (Hybrid/Lokal-Only mit `lxc_per_app`):**

Der Kunden-Proxmox wird minimal vorbereitet — nur Netbird wird manuell installiert. Alles andere (LXC-Erstellung, App-Deployment) erledigt Ansible remote:

```
Manuelle Vorbereitung (einmalig am Kunden-Proxmox):
1. Proxmox aufsetzen (Standard-Installation)
2. Netbird auf dem Proxmox-Host installieren + joinen (Gruppe: kunde-xxx)
3. API-Token für Ansible erstellen (Datacenter → API Tokens)
4. SSH-Key von Master deployen
→ Proxmox ist jetzt über Netbird vom Master erreichbar

Inventar vorbereiten:
1. bash scripts/new-customer.sh kunde-abc "Firma ABC GmbH" "firma-abc.de" "hybrid"
2. hosts.yml + group_vars/all.yml anpassen (Proxmox API-Token, Netbird-IP)
3. DNS-Records anlegen (A + Wildcard *.firma-abc.de)
4. Hetzner vServer bestellen (falls Hybrid/Cloud)
5. Git commit + push → Auf Master: git pull

Automatisiert (Semaphore → onboard-customer.yml):
 1. Netbird-Gruppe "kunde-xxx" erstellen (Netbird API)
 2. Netbird-Policies erstellen: intern + loco-admin→kunde + loco-backup→kunde (API)
 3. Netbird-Setup-Key generieren (reusable, 24h Ablauf) (API)
 4. LXC-Template herunterladen falls fehlend (pveam download, delegiert an Proxmox)
 5. LXC-Container erstellen auf Proxmox (community.general.proxmox über Netbird)
    └── TUN-Device konfigurieren (für Netbird im LXC)
 6. Bootstrap via pct exec (delegiert an Proxmox-Host):
    ├── SSH-Key injizieren
    ├── Netbird installieren + joinen (Setup-Key aus Schritt 3)
    └── Netbird-IP ermitteln → hosts.yml aktualisieren
 7. base-Rolle (direkte SSH via Netbird-IP): Hardening + Docker + UFW
 8. Entry-Point konfigurieren (Hetzner oder Gateway-LXC):
    ├── PocketID deployen (id.firma.de)
    ├── Tinyauth deployen (auth.firma.de)
    └── Admin-User in PocketID anlegen (API)
 9. Pro App: Deploy + OIDC-Client (PocketID API) + Credentials → Vaultwarden
10. Caddy → Caddyfile generieren + restart
11. Monitoring → Zabbix Agent auf jedem Host + Checks registrieren
12. Backup → Restic Setup + initiales Backup
13. Smoke-Test → HTTP-Checks auf alle Subdomains
```

> **Kernidee:** Der Proxmox-Host braucht nur Netbird + API-Token. Ansible erstellt Netbird-Gruppen, -Policies und -Keys automatisch via API, erstellt und bootstrappt alle LXC-Container remote über die Proxmox API und `pct exec`, und verbindet sich dann direkt via Netbird für alles Weitere. Kein manuelles LXC-Setup nötig.

### 15.3 Benutzer hinzufügen

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

### 15.4 Kunde offboarden

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
│  5. Zabbix-Hosts entfernen                                     │
│     └── Alle Hosts mit Prefix "{{ kunde_id }}-"               │
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

> **Hetzner-Server wird NICHT automatisch gelöscht.** Das muss Daniel manuell über die Hetzner-Konsole tun — zu riskant für Automation. Das Playbook gibt am Ende eine Zusammenfassung aus mit Hinweis: "Hetzner-Server XYZ kann jetzt manuell gelöscht werden."

> **DNS-Records** müssen ebenfalls manuell entfernt werden (A-Record + Wildcard der Kunden-Domain).

---

## 16. Sicherheits-Hardening

### 16.1 Ansible-Rolle `base`

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
| Watchtower | Docker-Image-Patches täglich 04:00 (Label-basiert, nur Minor/Patch) |
| USB deaktiviert | Nur auf physischen Servern (`is_lxc`-Check!) |
| .env chmod 600 | Alle Secrets-Files |
| Docker Port-Bind | Entry-Point: `127.0.0.1:PORT` / App-LXCs: `0.0.0.0:PORT` + UFW auf wt0 |

### 16.2 LXC-spezifisch

Variable `is_lxc: true/false` in der Rolle steuert:
- Kernel-Parameter: Nur netzwerkbezogene sysctl (LXC kann `kernel.*` und `fs.*` nicht setzen)
- USB: Nicht deaktivieren in LXC
- TUN-Device: Für Netbird in LXC nötig (`lxc.cgroup2.devices.allow: c 10:200 rwm`)

### 16.3 Admin-User pro Server

```yaml
admin_user: "srvadmin"     # Konfigurierbar pro Kunde
admin_user_nopasswd: true  # NOPASSWD für Ansible-Kompatibilität
```

---

## 17. Wartung & Updates

### 17.1 Automatisch

| Task | Frequenz | Tool |
|------|----------|------|
| OS-Sicherheitsupdates | Täglich | unattended-upgrades |
| Docker-Image-Updates (Patches) | Täglich 04:00 | Watchtower (Label-basiert) |
| Backup | Konfigurierbar (default: 6h) | Restic Cron |
| Health-Checks | Alle 5 min | Zabbix |
| SSL-Erneuerung | Automatisch | Caddy |

### 17.2 Watchtower-Strategie: Nur Security-Patches automatisch

**Problem:** Watchtower mit `:latest`-Tags kann bei Major-Updates Apps kaputt machen (z.B. Nextcloud 29 → 30, Breaking Changes in Paperless, DB-Migrationen die fehlschlagen).

**Lösung:** Label-basiertes Watchtower mit konservativen Image-Tags.

```yaml
# Docker Compose Template für jede App:
services:
  app:
    image: "nextcloud:29"          # Pinned auf Major-Version, Patches automatisch
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
    # ...

  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_LABEL_ENABLE=true      # Nur gelabelte Container updaten
      - WATCHTOWER_SCHEDULE=0 0 4 * * *   # Täglich 04:00
      - WATCHTOWER_CLEANUP=true           # Alte Images entfernen
      - WATCHTOWER_NOTIFICATIONS=email    # Optional: Benachrichtigung bei Update
      - WATCHTOWER_NOTIFICATION_EMAIL_FROM={{ loco.smtp.from }}
      - WATCHTOWER_NOTIFICATION_EMAIL_TO={{ loco.operator.email }}
      - WATCHTOWER_NOTIFICATION_EMAIL_SERVER={{ loco.smtp.host }}
      - WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PORT={{ loco.smtp.port }}
      - WATCHTOWER_NOTIFICATION_EMAIL_SERVER_USER={{ loco.smtp.user }}
```

**Image-Tag-Strategie:**
- `nextcloud:29` → bekommt automatisch 29.0.1, 29.0.2, etc. (Patches)
- `nextcloud:30` → manuell via `update-app.yml` wenn getestet (Major-Update)
- Container ohne Label werden von Watchtower ignoriert

**Major-Updates** (die was kaputt machen können) werden ausschließlich über Semaphore/`update-app.yml` gemacht:
1. Image-Tag im Inventar ändern (z.B. `nextcloud_version: "30"`)
2. `update-app.yml` ausführen → neues Image pullen, Container neu starten
3. Post-Update-Checks (Health-Check, DB-Migration prüfen)

### 17.3 Manuell (Semaphore)

| Task | Playbook |
|------|----------|
| Major App-Updates | `update-app.yml` — Image-Tag im Inventar ändern, dann ausführen |
| Full OS-Update | `update-all.yml` |
| Backup-Test | `backup-test.yml` |
| Mitarbeiter anlegen/entfernen | `add-user.yml` / `remove-user.yml` |

---

## 18. Kunden-Inventar-System

### 18.1 Beispiel: Hybrid-Kunde (single_lxc)

```yaml
# inventories/kunde-abc/hosts.yml
all:
  children:
    proxmox:
      hosts:
        abc-proxmox:
          ansible_host: "100.114.a.99"   # Netbird-IP des Proxmox-Hosts
          ansible_user: root
          server_role: proxmox
          is_lxc: false
          proxmox_node: "pve"
          proxmox_api_host: "100.114.a.99"
          proxmox_api_token_id: "ansible@pam!loco"
          proxmox_api_token_secret: "{{ vault_proxmox_token }}"
          lxc_template: "local:vztmpl/debian-13-standard_13.0-1_amd64.tar.zst"
    online:
      hosts:
        abc-hetzner:
          ansible_host: "100.114.a.0"    # Netbird-IP
          ansible_user: srvadmin
          server_role: online
          public_ip: "203.0.113.10"
          is_lxc: false
    lokal:
      hosts:
        abc-apps:
          ansible_host: "100.114.a.1"    # Netbird-IP (ein LXC für alles)
          ansible_user: srvadmin
          server_role: apps
          is_lxc: true
```

> **Der Proxmox-Host** ist im Inventar als `server_role: proxmox`. Er wird NICHT wie ein App-Server gehärtet (kein Docker, andere UFW-Regeln). Er dient nur als Ziel für LXC-Erstellung via Proxmox API und `pct exec`-Bootstrap. Netbird auf dem Proxmox-Host wird beim Kunden-Onboarding manuell installiert (einmaliger Schritt).

### 18.2 Beispiel: Hybrid-Kunde (lxc_per_app)

```yaml
# inventories/kunde-abc/hosts.yml
all:
  children:
    proxmox:
      hosts:
        abc-proxmox:
          ansible_host: "100.114.a.99"   # Netbird-IP des Proxmox-Hosts
          ansible_user: root
          server_role: proxmox
          is_lxc: false
          proxmox_node: "pve"
          proxmox_api_host: "100.114.a.99"
          proxmox_api_token_id: "ansible@pam!loco"
          proxmox_api_token_secret: "{{ vault_proxmox_token }}"
          lxc_template: "local:vztmpl/debian-13-standard_13.0-1_amd64.tar.zst"
    online:
      hosts:
        abc-hetzner:
          ansible_host: "100.114.a.0"    # Netbird-IP
          ansible_user: srvadmin
          server_role: online
          public_ip: "203.0.113.10"
          is_lxc: false
    lokal:
      hosts:
        abc-nextcloud:
          ansible_host: "100.114.a.1"    # Eigener Netbird-Client
          ansible_user: srvadmin
          server_role: app
          app_name: nextcloud
          is_lxc: true
        abc-paperless:
          ansible_host: "100.114.a.2"    # Eigener Netbird-Client
          ansible_user: srvadmin
          server_role: app
          app_name: paperless
          is_lxc: true
        abc-infra:
          ansible_host: "100.114.a.3"    # Eigener Netbird-Client
          ansible_user: srvadmin
          server_role: infra
          is_lxc: true
```

> **Jeder LXC hat seine eigene Netbird-IP.** Ansible erreicht jeden einzelnen direkt über Netbird — kein SSH-Hopping, kein Gateway. Der Proxmox-Host wird nur für LXC-Erstellung und Bootstrap benötigt.

### 18.3 Beispiel: Cloud-Only

```yaml
all:
  hosts:
    abc-hetzner:
      ansible_host: "100.114.a.0"
      ansible_user: srvadmin
      server_role: all_in_one
      public_ip: "203.0.113.10"
      is_lxc: false
```

### 18.4 Beispiel: Lokal-Only (lxc_per_app)

```yaml
all:
  children:
    proxmox:
      hosts:
        abc-proxmox:
          ansible_host: "100.114.a.99"   # Netbird-IP des Proxmox-Hosts
          ansible_user: root
          server_role: proxmox
          is_lxc: false
          proxmox_node: "pve"
          proxmox_api_host: "100.114.a.99"
          proxmox_api_token_id: "ansible@pam!loco"
          proxmox_api_token_secret: "{{ vault_proxmox_token }}"
          lxc_template: "local:vztmpl/debian-13-standard_13.0-1_amd64.tar.zst"
    gateway:
      hosts:
        abc-gw:
          ansible_host: "100.114.a.0"    # Netbird-IP
          ansible_user: srvadmin
          server_role: gateway           # Caddy + PocketID + Tinyauth
          is_lxc: true
    lokal:
      hosts:
        abc-nextcloud:
          ansible_host: "100.114.a.1"    # Eigener Netbird-Client
          ansible_user: srvadmin
          server_role: app
          app_name: nextcloud
          is_lxc: true
        abc-paperless:
          ansible_host: "100.114.a.2"    # Eigener Netbird-Client
          ansible_user: srvadmin
          server_role: app
          app_name: paperless
          is_lxc: true
        abc-infra:
          ansible_host: "100.114.a.3"
          ansible_user: srvadmin
          server_role: infra
          is_lxc: true
```

> **Bei Lokal-Only:** Der Gateway-LXC übernimmt die Rolle des Hetzner-Servers (Caddy + Auth). Routing zu App-LXCs geht über Netbird — kein Unterschied zur Hybrid-Variante aus Sicht der App-LXCs. Der Proxmox-Host ist im Inventar für LXC-Erstellung und Bootstrap.

### 18.5 group_vars/all.yml (Hauptkonfiguration)

```yaml
# =====================================================================
# KUNDEN-KONFIGURATION
# =====================================================================

kunde_name: "Firma ABC GmbH"
kunde_domain: "firma-abc.de"
kunde_id: "abc001"

variante: "hybrid"                      # hybrid | cloud_only | lokal_only
isolation_mode: "lxc_per_app"           # single_lxc | lxc_per_app

online_server: "abc-hetzner"

# --- Netbird ---
netbird_setup_keys:
  online: "{{ vault_netbird_key_online }}"
  # Bei lxc_per_app: ein Key pro LXC (oder reusable Key für die Kundengruppe)
  lokal: "{{ vault_netbird_key_lokal }}"
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
    target: "lokal"
    netbird_ip: "100.114.a.1"          # Eigene Netbird-IP (LXC: abc-nextcloud)
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
    target: "lokal"
    netbird_ip: "100.114.a.2"          # Eigene Netbird-IP (LXC: abc-paperless)
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
    target: "online"                   # Läuft auf Hetzner → netbird_ip wird ignoriert
    netbird_ip: ""
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

# --- DynDNS (nur bei lokal_only) ---
# Entschieden: Master-Server (Hetzner) übernimmt DNS-Updates
# für lokale Kunden — immer online, kennt die Netbird-IPs
dyndns:
  enabled: false
  provider: "master"  # Master-Server aktualisiert DNS für lokale Kunden
```

---

## 19. Repo Public-Readiness

### 19.1 Was NICHT ins Repo darf

| Typ | Wo stattdessen |
|-----|----------------|
| `config/lococloudd.yml` | `.gitignore`, nur `.example` committed |
| Kunden-Inventare mit echten IPs | Ansible Vault oder `.gitignore` |
| SSH-Keys, API-Tokens | Vaultwarden + lokale Dateien |
| Netbird Setup-Keys | Vaultwarden |
| Passwörter jeder Art | Vaultwarden |

### 19.2 Was ins Repo darf

- Alle Rollen, Playbooks, Templates
- `config/lococloudd.yml.example`
- `inventories/_template/`
- Dokumentation
- Scripts

### 19.3 Ansible Vault für sensible Inventar-Daten

Für Kunden-Inventare die nicht in `.gitignore` stehen sollen (z.B. wenn das Repo privat bleibt), können sensitive Werte mit Ansible Vault verschlüsselt werden:

```yaml
# inventories/kunde-abc/group_vars/vault.yml (verschlüsselt)
vault_netbird_key_online: "encrypted-value"
vault_netbird_key_primary: "encrypted-value"
```

### 19.4 README.md (Auszug)

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

## 20. Bekannte Fallstricke & Lessons Learned

### Aus dem ollornog.de-Setup

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
| **Docker Port-Binding** | **Auf Entry-Point-Servern** (Hetzner, Gateway-LXC): `127.0.0.1:PORT:PORT` — Caddy ist lokal. **Auf App-LXCs** (lxc_per_app): `0.0.0.0:PORT:PORT` — Caddy sitzt remote auf dem Hetzner und erreicht den LXC über Netbird-IP. Absichern über UFW: App-Port nur auf `wt0` erlauben! | Alle Compose Files |
| **UFW auf App-LXCs** | Bei lxc_per_app: App-Ports (8080, 8081 etc.) nur auf Netbird-Interface `wt0` erlauben, SSH nur auf `wt0`. Default deny incoming. So sind die Docker-Ports trotz `0.0.0.0`-Bind nicht im LAN erreichbar. | base-Rolle + UFW |
| **Health-Check hinter Auth** | Backend-Ports (localhost) prüfen, nicht öffentliche URL | Monitoring |
| **Caddy handle-Reihenfolge** | Spezifische Matcher VOR Fallback `handle {}` | Caddyfile |
| **CSP per App** | Nicht global! VW, NC, PocketID setzen eigenen CSP | Caddyfile |
| **PocketID /register** | Per Caddy 403 blocken | Caddyfile |
| **Shared Redis** | Bei `single_lxc`: DB-Nummern nutzen (db=0, db=1). Bei `lxc_per_app`: Jeder LXC hat eigenen Redis → DB-Nummern nicht nötig | Docker Compose |
| **USB in LXC** | NICHT deaktivieren (existiert nicht) | base-Rolle |
| **Tinyauth nicht prod-ready** | Monitoring, Fallback-Plan auf Authelia | Architektur |

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

## 21. Offene Design-Entscheidungen

### Gelöste Entscheidungen (zur Referenz)

| Frage | Entscheidung | Siehe Kapitel |
|-------|-------------|---------------|
| Öffentliche IP für `*.loco.ollornog.de` | Route über Daniels Hetzner (46.225.165.213), Caddy leitet via Netbird an Master-LXC weiter | Kap. 3.3 |
| PocketID User-Management | API-Automation via PocketID REST-API (Bearer-Token) | Kap. 7.6 |
| Backup Off-Site Ziel | Dynamisch pro Kunde konfigurierbar (SFTP via Netbird, Hetzner Storage Box, oder Betreiber-Infra) | Kap. 11 |
| Ansible Vault vs. Vaultwarden | Beides komplementär: Vault für Repo-Encryption, Vaultwarden für Credential-Store + Lookup | Kap. 10.1 |
| Shared Redis | Implizit durch `isolation_mode` gelöst (single_lxc: DB-Nummern, lxc_per_app: eigener Container) | Kap. 9.3 |
| Isolation auf Proxmox | `lxc_per_app` empfohlen, `single_lxc` als Option | Kap. 5 |
| LXC-Bootstrap-Methode | `pct exec` via Proxmox-Host (SSH-Key + Netbird injizieren, dann direkte Verbindung) | Kap. 5.6 |
| Netbird-Gruppen/Keys/Policies | Vollautomatisch via Netbird REST-API durch Ansible (kein manueller Eingriff) | Kap. 6.3 |
| Watchtower-Strategie | Label-basiert + gepinnte Major-Versionen. Patches automatisch, Major-Updates manuell via Semaphore | Kap. 17.2 |
| LXC-Template auf Proxmox | Ansible lädt Template via `pveam download` automatisch herunter wenn fehlend | Kap. 5.6 |
| Offboarding-Strategie | Gestuft: Archivieren (Standard) oder komplett löschen. Hetzner-Server manuell. Credentials archiviert | Kap. 15.4 |
| Tinyauth vs. Authelia | Tinyauth — reicht aus, da nur OIDC via PocketID (kein direkter Login, kein Brute-Force-Risiko). Austauschbar bauen, bei Problemen auf Authelia wechseln | Kap. 7.8 |
| DynDNS (Lokal-Only) | Master-Server (Hetzner) übernimmt DNS-Updates für lokale Kunden — immer online, kennt die Netbird-IPs | Kap. 18 |
| Admin sudo | NOPASSWD — SSH nur über Netbird (`wt0`) + Key-Only. Netbird ist die zweite Sicherheitsstufe | Kap. 16.3 |
| Monitoring | Zabbix auf Master für Infrastruktur-Monitoring. Uptime Kuma als optionale Kunden-App für Status-Dashboards (`status.firma.de`) | Kap. 12 |

### Noch offene Entscheidungen

Keine — alle Entscheidungen sind getroffen.

---

## Anhang A: Port-Zuordnung

| Port | Dienst |
|------|--------|
| 1411 | PocketID |
| 3000 | Semaphore (nur Master) |
| 8080 | Nextcloud / Zabbix Web |
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
| 9090 | Tinyauth |
| 10050 | Zabbix Agent |

---

## Anhang B: Checkliste neue App-Rolle

- [ ] `defaults/main.yml` mit allen Variablen
- [ ] `docker-compose.yml.j2` — Port-Binding je nach Server-Rolle
- [ ] `.env.j2` — Secrets als Variablen
- [ ] `oidc.yml` — OIDC-Client via PocketID REST-API erstellen, Credentials in Vaultwarden speichern
- [ ] Public Paths definieren (oder leer = komplett geschützt)
- [ ] Backup-Pfade definieren
- [ ] Health-Check: Port + Path für Monitoring
- [ ] Handler: `docker restart caddy`
- [ ] PG 18: Mount `/var/lib/postgresql`
- [ ] Redis: DB-Nummer zuweisen (single_lxc) oder eigener Container (lxc_per_app)
- [ ] CSP: Nur setzen wenn App keinen eigenen hat
- [ ] `remove.yml`: Daten archivieren, nicht löschen
- [ ] Idempotenz testen (2x laufen lassen)
- [ ] Keine hardcodierten Domains/E-Mails (alles aus Config/Inventar)

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
