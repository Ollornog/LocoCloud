# CLAUDE.md — Project Context for AI Assistants

## What This Is

LocoCloud is an Ansible monorepo that deploys self-hosted infrastructure for small businesses.
One master server manages multiple customer environments via inventories.

## Architecture Essentials

- **Master server**: PocketID, Tinyauth, Vaultwarden, Semaphore, Grafana Stack, Baserow, Caddy
- **Customer servers**: Gateway (Caddy) → App servers (Nextcloud, Paperless, etc.)
- **Auth chain**: PocketID (OIDC) → Tinyauth (forward-auth) → Apps
- **Credentials**: All generated passwords stored in Vaultwarden via `scripts/vw-credentials.py`
- **Encryption**: gocryptfs on `/mnt/data`, keyfile only on master
- **Networking**: Netbird VPN (optional) or direct IP connectivity

## Key Config Files

| File | Purpose |
|------|---------|
| `config/lococloudd.yml` | Global config (gitignored, create from `.example`) |
| `inventories/master/hosts.yml` | Master server inventory |
| `inventories/kunde-*/group_vars/all.yml` | Per-customer config |
| `ansible.cfg` | Ansible settings, vault password script |

## Repo Structure

```
roles/
  base/                  # OS hardening, Docker, UFW, Fail2ban
  caddy/                 # Reverse proxy (master + customer templates)
  pocketid/              # OIDC provider
  tinyauth/              # Forward auth
  netbird_client/        # VPN client
  netbird_server/        # Self-hosted Netbird management
  gocryptfs/             # Encryption for /mnt/data
  grafana_stack/         # Grafana + Prometheus + Loki
  alloy/                 # Grafana Alloy agent (customer servers)
  baserow/               # Permission management
  credentials/           # Vaultwarden API integration
  backup/                # Restic backups
  key_backup/            # gocryptfs key backup
  compliance/            # TOM, VVT, Löschkonzept templates
  watchtower/            # Auto-update (customer apps only)
  monitoring/            # Wrapper → delegates to alloy
  lxc_create/            # Proxmox LXC creation
  apps/
    _template/           # Copy for new app roles
    nextcloud/           # MariaDB + Redis
    paperless/           # PostgreSQL
    vaultwarden/         # SQLite, OIDC via PocketID
    semaphore/           # Ansible Web-UI
    outline/             # PostgreSQL + Redis
    gitea/               # PostgreSQL
    hedgedoc/            # PostgreSQL
    documenso/           # PostgreSQL
    calcom/              # PostgreSQL
    pingvin_share/       # SQLite
    stirling_pdf/        # No DB
    listmonk/            # PostgreSQL
    uptime_kuma/         # SQLite
playbooks/
  setup-master.yml       # Master setup (run first)
  onboard-customer.yml   # New customer
  site.yml               # Full deploy (idempotent)
  add-app.yml            # Single app
  add-server.yml         # Bootstrap fresh server
scripts/
  setup.sh               # Interactive master setup
  vw-credentials.py      # Vaultwarden API (Bitwarden protocol)
  new-customer.sh        # Generate customer inventory
  vault-pass.sh          # Ansible Vault password helper
docs/
  KONZEPT.md             # Architecture reference v5.0 (source of truth)
  SETUP.md               # Master setup guide
  ONBOARDING.md          # Customer onboarding
  APP-DEVELOPMENT.md     # How to create app roles
  SEMAPHORE.md           # Semaphore Web-UI config
  TROUBLESHOOTING.md     # Known issues
  FAHRPLAN.md            # Implementation roadmap
```

## Critical Patterns

- **Global config**: Every playbook loads `config/lococloudd.yml` as `loco` in `pre_tasks`
- **Docker Compose V2**: Always `docker compose`, never `docker-compose`
- **Caddy restart**: Always `docker restart caddy`, never `caddy reload` (inode issue)
- **PostgreSQL 18**: Mount on `/var/lib/postgresql`, NOT `/var/lib/postgresql/data`
- **Port binding**: `127.0.0.1:PORT` on gateways, `0.0.0.0:PORT` + UFW on app servers
- **PocketID API**: `X-API-Key` header, NOT `Authorization: Bearer`
- **Watchtower**: Only customer apps, NEVER infrastructure containers
- **Secrets**: Never in Git. Ansible Vault or Vaultwarden only.

## Rules Location

Detailed rules are in `.claude/rules/`:
- `coding-standards.md` — Ansible, Jinja2, Docker, Caddy patterns
- `known-issues.md` — Fallstricke with solutions
- `new-app-checklist.md` — Checklist for new app roles
- `cleanup.md` — Post-task cleanup rules
- `documentation.md` — What to document when
