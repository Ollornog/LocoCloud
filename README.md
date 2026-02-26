# LocoCloud

**Turnkey self-hosted infrastructure for small businesses**, powered by Ansible.

LocoCloud is a single Git repository that deploys, manages, and monitors complete self-hosted environments for small companies (5-50 employees). Clone the repo on a master server, configure your customers, run a playbook — done.

```bash
# Quick start on a fresh Debian 12/13 server:
apt update && apt install -y curl
curl -fsSL https://raw.githubusercontent.com/Ollornog/LocoCloud/main/scripts/setup.sh -o setup.sh
bash setup.sh
```

The setup script interactively asks for configuration (domain, email, SMTP, optional Netbird) and runs the master playbook.

---

## What It Does

- **One repo, many customers** — Monorepo with inventory-based separation per customer
- **Master-first workflow** — Install the master with all admin tools, then add customers, servers, and apps
- **Full auth stack** — PocketID (OIDC) + Tinyauth (forward auth) per customer, SSO across all apps
- **14 app roles** — Nextcloud, Paperless-NGX, Vaultwarden, Outline, Gitea, HedgeDoc, and more
- **Flexible deployment** — Freely assign server roles (gateway, app_server, etc.) to any host. Cloud, on-premise, or hybrid
- **Encryption at rest** — gocryptfs on `/mnt/data` for all customer data, keyfile only on master
- **Monitoring & logging** — Grafana + Prometheus + Loki on master, Alloy agent on customer servers
- **Automatic credential management** — All generated passwords stored in Vaultwarden
- **Backup with verification** — Restic backups with pre-backup DB dumps, monthly restore tests
- **DSGVO/GoBD compliance** — TOM, VVT, Löschkonzept auto-generated as Jinja2 templates per customer
- **Netbird VPN (optional)** — VPN mesh for admin access, or use direct IP connectivity

---

## Architecture

```
                    Internet
                       │
            ┌──────────▼──────────┐
            │   Gateway Server    │  ← server_roles: [gateway, customer_master]
            │   Caddy (Wildcard)  │
            │   PocketID + Auth   │
            │   *.customer.de     │
            └──────────┬──────────┘
                       │ Direct IP or Netbird VPN
            ┌──────────▼──────────┐
            │   App Server(s)     │  ← server_roles: [app_server]
            │   ├── Nextcloud     │
            │   ├── Paperless     │
            │   ├── Vaultwarden   │
            │   ├── Alloy Agent   │
            │   └── /mnt/data     │  ← gocryptfs encrypted
            └─────────────────────┘

┌─────────────────────────────────┐
│   Master Server                 │  ← server_roles: [master]
│   ├── Ansible + Git repo        │
│   ├── PocketID (admin)          │
│   ├── Vaultwarden (admin)       │
│   ├── Semaphore (web UI)        │
│   ├── Grafana Stack             │  ← Grafana + Prometheus + Loki
│   ├── Baserow (permissions)     │
│   └── gocryptfs key store       │
└─────────────────────────────────┘
```

---

## Quick Start

### Option A: Automated Setup (Recommended)

See the quick start command at the top of this README. The script handles everything interactively.

### Option B: Manual Setup

```bash
# 1. Clone the repo
git clone git@github.com:Ollornog/LocoCloud.git
cd LocoCloud

# 2. Install Ansible collections
ansible-galaxy collection install -r requirements.yml

# 3. Create global config
cp config/lococloudd.yml.example config/lococloudd.yml
# Edit config/lococloudd.yml with your values

# 4. Setup the master server
ansible-playbook playbooks/setup-master.yml -i inventories/master/

# 5. Create a customer
bash scripts/new-customer.sh abc001 "Acme Corp" "acme-corp.com"
# Edit inventories/kunde-abc001/group_vars/all.yml

# 6. Add a server to the customer
ansible-playbook playbooks/add-server.yml -i inventories/kunde-abc001/ \
  -e "server_ip=203.0.113.10 server_user=root server_pass=xxx server_name=main"

# 7. Deploy
ansible-playbook playbooks/onboard-customer.yml -i inventories/kunde-abc001/
```

### Prerequisites

- Debian 12 (Bookworm) or 13 (Trixie) server/LXC for the master
- Min. 2 CPU cores, 2 GB RAM, 20 GB disk
- Ansible >= 2.15 (auto-installed by setup script)
- DNS wildcard for admin services (`*.admin.example.com`)
- Netbird is **optional** — servers can also be reached via direct IP

---

## Repository Structure

```
LocoCloud/
├── ansible.cfg                    # Ansible configuration
├── requirements.yml               # Required Ansible collections
├── config/
│   ├── lococloudd.yml             # Global config (gitignored)
│   └── lococloudd.yml.example     # Config template
├── inventories/
│   ├── master/                    # Master server inventory
│   ├── _template/                 # Customer inventory templates
│   └── kunde-*/                   # Per-customer inventories
├── roles/
│   ├── base/                      # OS hardening, Docker, UFW, Fail2ban
│   ├── caddy/                     # Reverse proxy (master + customer)
│   ├── pocketid/                  # OIDC provider
│   ├── tinyauth/                  # Forward auth
│   ├── netbird_client/            # VPN client + API automation (optional)
│   ├── netbird_server/            # Self-hosted Netbird management server
│   ├── gocryptfs/                 # Encryption for /mnt/data + auto-mount
│   ├── grafana_stack/             # Grafana + Prometheus + Loki (master)
│   ├── alloy/                     # Grafana Alloy agent (customer servers)
│   ├── baserow/                   # Permission management (master)
│   ├── credentials/               # Vaultwarden API integration
│   ├── monitoring/                # Wrapper → delegates to alloy
│   ├── backup/                    # Restic + pre-backup hooks + restore tests
│   ├── key_backup/                # gocryptfs key backup server
│   ├── compliance/                # TOM, VVT, Löschkonzept templates
│   ├── watchtower/                # Auto-update for customer apps
│   ├── lxc_create/                # Proxmox LXC creation + bootstrap
│   └── apps/
│       ├── _template/             # Copy template for new app roles
│       ├── nextcloud/             # Nextcloud (MariaDB + Redis)
│       ├── paperless/             # Paperless-NGX (PostgreSQL)
│       ├── vaultwarden/           # Vaultwarden (SQLite)
│       ├── semaphore/             # Semaphore Ansible UI
│       ├── stirling_pdf/          # Stirling PDF toolkit
│       ├── uptime_kuma/           # Uptime Kuma status page
│       ├── documenso/             # Digital signatures (PostgreSQL)
│       ├── pingvin_share/         # File sharing
│       ├── hedgedoc/              # Collaborative Markdown (PostgreSQL)
│       ├── outline/               # Wiki / Knowledge Base (PostgreSQL + Redis)
│       ├── gitea/                 # Git hosting (PostgreSQL)
│       ├── calcom/                # Scheduling (PostgreSQL)
│       └── listmonk/              # Newsletter / Mailing (PostgreSQL)
├── playbooks/
│   ├── setup-master.yml           # Master server setup
│   ├── onboard-customer.yml       # New customer onboarding
│   ├── add-server.yml             # Add fresh server to customer
│   ├── site.yml                   # Full deploy (base + auth + apps)
│   ├── add-app.yml                # Add single app to customer
│   ├── remove-app.yml             # Remove app (archive data)
│   ├── update-app.yml             # Update app (pull + recreate)
│   ├── update-caddy.yml           # Regenerate Caddy configuration
│   ├── add-user.yml               # Add user to PocketID + Tinyauth
│   ├── remove-user.yml            # Remove user
│   ├── update-all.yml             # OS updates on all servers
│   ├── backup-now.yml             # Trigger immediate backup
│   ├── restore.yml                # Restore from backup
│   ├── restore-test.yml           # Monthly restore verification
│   ├── generate-docs.yml          # Regenerate compliance documents
│   └── offboard-customer.yml      # Customer offboarding
├── scripts/
│   ├── setup.sh                   # Automated master setup (interactive)
│   ├── new-customer.sh            # Generate customer inventory
│   ├── vault-pass.sh              # Ansible Vault password from Vaultwarden
│   ├── vw-credentials.py          # Vaultwarden API (Bitwarden protocol, pure Python)
│   ├── pre-backup.sh              # DB dumps before Restic backup
│   └── gocryptfs-mount.sh         # Auto-mount after reboot
└── docs/
    ├── KONZEPT.md                 # Architecture reference (German, v5.0)
    ├── FAHRPLAN.md                # Implementation roadmap (German)
    ├── SETUP.md                   # Master server setup guide
    ├── ONBOARDING.md              # Customer onboarding guide
    ├── APP-DEVELOPMENT.md         # How to create app roles
    └── TROUBLESHOOTING.md         # Known issues and solutions
```

---

## Playbooks

| Playbook | Purpose | Usage |
|----------|---------|-------|
| `setup-master.yml` | Set up master server (Grafana, Baserow, Auth, etc.) | `ansible-playbook playbooks/setup-master.yml -i inventories/master/` |
| `onboard-customer.yml` | Onboard new customer (Auth + gocryptfs + Alloy + Compliance) | `ansible-playbook playbooks/onboard-customer.yml -i inventories/kunde-abc/` |
| `add-server.yml` | Bootstrap a fresh server (SSH key, base, gocryptfs, Alloy) | `ansible-playbook playbooks/add-server.yml -i inventories/kunde-abc/ -e "server_ip=... server_user=root server_pass=..."` |
| `site.yml` | Full deploy (idempotent) | `ansible-playbook playbooks/site.yml -i inventories/kunde-abc/` |
| `add-app.yml` | Deploy a single app | `ansible-playbook playbooks/add-app.yml -i inventories/kunde-abc/ -e "app_name=Nextcloud"` |
| `remove-app.yml` | Remove an app (archive) | `ansible-playbook playbooks/remove-app.yml -i inventories/kunde-abc/ -e "app_name=Nextcloud"` |
| `update-app.yml` | Update app (pull + recreate) | `ansible-playbook playbooks/update-app.yml -i inventories/kunde-abc/ -e "app_name=Nextcloud"` |
| `update-caddy.yml` | Regenerate Caddy configuration | `ansible-playbook playbooks/update-caddy.yml -i inventories/kunde-abc/` |
| `add-user.yml` | Add a customer user | `ansible-playbook playbooks/add-user.yml -i inventories/kunde-abc/ -e "username=... email=..."` |
| `remove-user.yml` | Remove a customer user | `ansible-playbook playbooks/remove-user.yml -i inventories/kunde-abc/ -e "username=... email=..."` |
| `update-all.yml` | OS updates | `ansible-playbook playbooks/update-all.yml -i inventories/kunde-abc/` |
| `backup-now.yml` | Immediate backup | `ansible-playbook playbooks/backup-now.yml -i inventories/kunde-abc/` |
| `restore.yml` | Restore from backup | `ansible-playbook playbooks/restore.yml -i inventories/kunde-abc/` |
| `restore-test.yml` | Monthly restore verification | `ansible-playbook playbooks/restore-test.yml -i inventories/kunde-abc/` |
| `generate-docs.yml` | Regenerate compliance docs (TOM, VVT, Löschkonzept) | `ansible-playbook playbooks/generate-docs.yml -i inventories/kunde-abc/` |
| `offboard-customer.yml` | Offboard customer | `ansible-playbook playbooks/offboard-customer.yml -i inventories/kunde-abc/ [-e "destroy=true"]` |

---

## Available Apps

| App | Description | Database | OIDC |
|-----|-------------|----------|------|
| Nextcloud | Cloud storage & collaboration | MariaDB + Redis | Native |
| Paperless-NGX | Document management | PostgreSQL | Native |
| Vaultwarden | Password manager (per customer) | SQLite | Native |
| Outline | Wiki / Knowledge Base | PostgreSQL + Redis | Native |
| Gitea | Git hosting | PostgreSQL | Native |
| HedgeDoc | Collaborative Markdown editor | PostgreSQL | Native |
| Documenso | Digital signatures | PostgreSQL | Native |
| Cal.com | Scheduling / Booking | PostgreSQL | Native |
| Pingvin Share | File sharing | SQLite | Native |
| Stirling PDF | PDF manipulation toolkit | — | Native |
| Listmonk | Newsletter / Mailing | PostgreSQL | Tinyauth |
| Uptime Kuma | Status page / Monitoring | SQLite | Tinyauth |

All apps use Docker Compose v2, `restart: unless-stopped`, explicit container names, and Watchtower labels for auto-updates.

---

## Deployment Scenarios

There are no fixed deployment variants. You freely assign server roles to hosts in each customer's inventory. Common scenarios:

### All-in-One (Single Cloud Server)

```
Internet → Cloud Server [gateway, customer_master, app_server]
```

### Cloud Gateway + Local App Servers

```
Internet → Cloud Server [gateway, customer_master] → Direct IP / Netbird → Local Server [app_server]
```

### Fully Local (On-Premise with Proxmox)

```
Internet → Router (Port-Forward) → Gateway-LXC [gateway, customer_master] → App-LXCs [app_server]
```

---

## Security

- **Encryption at rest:** gocryptfs on `/mnt/data` for all customer app data. Keyfile only on master + key backup server.
- **SSH:** Key-only authentication, root login disabled, custom port configurable
- **Firewall:** UFW default-deny incoming, SSH only via admin interface
- **Fail2ban:** SSH jail active on all servers
- **Kernel hardening:** sysctl network parameters, unattended security upgrades
- **Docker:** Port binding on `127.0.0.1` for entry-point servers, `0.0.0.0` + UFW for app servers
- **Secrets:** Never in Git. Ansible Vault for repo encryption, Vaultwarden for runtime secrets
- **Auth:** All apps behind Tinyauth by default, public paths explicitly whitelisted
- **.env files:** Mode 0600 on all servers
- **Compliance:** DSGVO/GoBD-compliant logging (6-month retention, journald FSS sealing)

---

## Adding a New App

```bash
# 1. Copy the template
cp -r roles/apps/_template roles/apps/my_app

# 2. Customize defaults, templates, and tasks
# See docs/APP-DEVELOPMENT.md for the full checklist
```

See [docs/APP-DEVELOPMENT.md](docs/APP-DEVELOPMENT.md) for a step-by-step guide on creating new app roles.

---

## Documentation

| Document | Language | Content |
|----------|----------|---------|
| [KONZEPT.md](docs/KONZEPT.md) | German | Architecture reference v5.0 (the source of truth) |
| [FAHRPLAN.md](docs/FAHRPLAN.md) | German | Implementation roadmap |
| [SETUP.md](docs/SETUP.md) | German | Master server setup guide |
| [ONBOARDING.md](docs/ONBOARDING.md) | German | Customer onboarding process |
| [APP-DEVELOPMENT.md](docs/APP-DEVELOPMENT.md) | German | How to create new app roles |
| [SEMAPHORE.md](docs/SEMAPHORE.md) | German | Semaphore Web-UI configuration |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | German | Known issues and solutions |

---

## License

This project is currently private. License TBD.
