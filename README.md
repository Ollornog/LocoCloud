# LocoCloud

**Turnkey self-hosted infrastructure for small businesses**, powered by Ansible.

LocoCloud is a single Git repository that deploys, manages, and monitors complete self-hosted environments for small companies (5-50 employees). Clone the repo on a master server, configure your customers, run a playbook — done.

---

## What It Does

- **One repo, many customers** — Monorepo with inventory-based separation per customer
- **Full auth stack** — PocketID (OIDC) + Tinyauth (forward auth) per customer, SSO across all apps
- **Automated app deployment** — Nextcloud, Paperless-NGX, Vaultwarden, and more as Ansible roles
- **Three deployment variants** — Cloud-only (Hetzner), Hybrid (Hetzner + Proxmox), Local-only (Proxmox + Gateway)
- **Zero-trust networking** — Netbird VPN for admin/infrastructure, public access for end users via Caddy
- **Automatic credential management** — All generated passwords stored in Vaultwarden
- **Backup & monitoring** — Restic backups, Zabbix monitoring, Uptime Kuma (optional)

---

## Architecture

```
                    Internet
                       │
            ┌──────────▼──────────┐
            │   Hetzner vServer   │
            │   Caddy (Wildcard)  │
            │   *.firma-abc.de    │
            └──────────┬──────────┘
                       │ Netbird VPN
            ┌──────────▼──────────┐
            │   Customer Server   │
            │   ├── PocketID      │  ← OIDC Provider
            │   ├── Tinyauth      │  ← Forward Auth
            │   ├── Nextcloud     │  ← Apps
            │   ├── Paperless     │
            │   ├── Vaultwarden   │
            │   └── Caddy         │  ← Reverse Proxy
            └─────────────────────┘

┌─────────────────────────────────┐
│        Master Server            │
│   ├── Ansible + Git repo        │
│   ├── PocketID (admin)          │
│   ├── Vaultwarden (admin)       │
│   ├── Semaphore (web UI)        │
│   ├── Zabbix (monitoring)       │
│   └── Netbird Client            │
└─────────────────────────────────┘
```

---

## Quick Start

### Prerequisites

- Debian 13 (Trixie) server/LXC for the master
- Ansible >= 2.15
- A running Netbird management server
- DNS wildcard for admin services (`*.admin.example.com`)

### Setup

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
bash scripts/new-customer.sh abc001 "Acme Corp" "acme-corp.com" cloud_only
# Edit inventories/kunde-abc001/group_vars/all.yml
# Edit + encrypt inventories/kunde-abc001/group_vars/vault.yml

# 6. Onboard the customer
ansible-playbook playbooks/onboard-customer.yml -i inventories/kunde-abc001/

# 7. Deploy apps
ansible-playbook playbooks/site.yml -i inventories/kunde-abc001/
```

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
│   ├── netbird_client/            # VPN client + API automation
│   ├── credentials/               # Vaultwarden API integration
│   ├── monitoring/                # Zabbix agent
│   ├── backup/                    # Restic backup
│   ├── watchtower/                # Auto-update for customer apps
│   ├── lxc_create/                # Proxmox LXC creation + bootstrap
│   └── apps/
│       ├── nextcloud/             # Nextcloud (MariaDB + Redis)
│       ├── paperless/             # Paperless-NGX (PostgreSQL + Redis)
│       ├── vaultwarden/           # Vaultwarden (SQLite)
│       ├── semaphore/             # Semaphore Ansible UI
│       └── uptime_kuma/           # Uptime Kuma status page
├── playbooks/
│   ├── setup-master.yml           # Master server setup
│   ├── onboard-customer.yml       # New customer onboarding
│   ├── site.yml                   # Full deploy (base + auth + apps)
│   ├── add-app.yml                # Add single app to customer
│   ├── remove-app.yml             # Remove app (archive data)
│   ├── add-user.yml               # Add user to PocketID + Tinyauth
│   ├── remove-user.yml            # Remove user
│   ├── update-all.yml             # OS updates on all servers
│   ├── backup-now.yml             # Trigger immediate backup
│   ├── restore.yml                # Restore from backup
│   └── offboard-customer.yml      # Customer offboarding
├── scripts/
│   ├── new-customer.sh            # Generate customer inventory
│   └── vault-pass.sh              # Ansible Vault password from Vaultwarden
└── docs/
    ├── KONZEPT.md                 # Architecture reference (German)
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
| `setup-master.yml` | Set up the master server | `ansible-playbook playbooks/setup-master.yml -i inventories/master/` |
| `onboard-customer.yml` | Onboard a new customer | `ansible-playbook playbooks/onboard-customer.yml -i inventories/kunde-abc/` |
| `site.yml` | Full deploy (idempotent) | `ansible-playbook playbooks/site.yml -i inventories/kunde-abc/` |
| `add-app.yml` | Deploy a single app | `ansible-playbook playbooks/add-app.yml -i inventories/kunde-abc/ -e "app_name=Nextcloud"` |
| `remove-app.yml` | Remove an app (archive) | `ansible-playbook playbooks/remove-app.yml -i inventories/kunde-abc/ -e "app_name=Nextcloud"` |
| `add-user.yml` | Add a customer user | `ansible-playbook playbooks/add-user.yml -i inventories/kunde-abc/ -e "username=... email=... display_name=..."` |
| `remove-user.yml` | Remove a customer user | `ansible-playbook playbooks/remove-user.yml -i inventories/kunde-abc/ -e "username=... email=..."` |
| `update-all.yml` | OS updates | `ansible-playbook playbooks/update-all.yml -i inventories/kunde-abc/` |
| `backup-now.yml` | Immediate backup | `ansible-playbook playbooks/backup-now.yml -i inventories/kunde-abc/` |
| `restore.yml` | Restore from backup | `ansible-playbook playbooks/restore.yml -i inventories/kunde-abc/` |
| `offboard-customer.yml` | Offboard customer | `ansible-playbook playbooks/offboard-customer.yml -i inventories/kunde-abc/ [-e "destroy=true"]` |

---

## Deployment Variants

### Cloud-Only

Customer has a Hetzner VPS. Everything runs on that server.

```
Internet → Hetzner VPS (Caddy + PocketID + Tinyauth + Apps)
```

### Hybrid

Customer has a Hetzner VPS as entry-point + a local Proxmox server with LXCs for apps.

```
Internet → Hetzner VPS (Caddy) → Netbird VPN → Proxmox LXCs (Apps)
```

### Local-Only

Everything runs on-premise on a Proxmox server. A Gateway-LXC handles public access.

```
Internet → Router (Port-Forward) → Gateway-LXC (Caddy + Auth) → App-LXCs
```

---

## Security

- **SSH:** Key-only authentication, root login disabled, custom port configurable
- **Firewall:** UFW default-deny incoming, SSH only via Netbird interface (`wt0`)
- **Fail2ban:** SSH jail active on all servers
- **Kernel hardening:** sysctl network parameters, unattended security upgrades
- **Docker:** Port binding on `127.0.0.1` for entry-point servers
- **Secrets:** Never in Git. Ansible Vault for repo encryption, Vaultwarden for runtime secrets
- **Auth:** All apps behind Tinyauth by default, public paths explicitly whitelisted
- **.env files:** Mode 0600 on all servers

---

## Adding a New App

See [docs/APP-DEVELOPMENT.md](docs/APP-DEVELOPMENT.md) for a step-by-step guide on creating new app roles.

---

## Documentation

| Document | Language | Content |
|----------|----------|---------|
| [KONZEPT.md](docs/KONZEPT.md) | German | Architecture reference (the source of truth) |
| [FAHRPLAN.md](docs/FAHRPLAN.md) | German | Implementation roadmap |
| [SETUP.md](docs/SETUP.md) | German | Master server setup guide |
| [ONBOARDING.md](docs/ONBOARDING.md) | German | Customer onboarding process |
| [APP-DEVELOPMENT.md](docs/APP-DEVELOPMENT.md) | German | How to create new app roles |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | German | Known issues and solutions |

---

## License

This project is currently private. License TBD.
