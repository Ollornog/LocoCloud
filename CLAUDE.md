# CLAUDE.md — Project Context for AI Assistants

## What This Is

LocoCloud is an Ansible monorepo that deploys self-hosted infrastructure for small businesses.
One master server manages multiple customer environments via inventories.

## Architecture Essentials

- **Master server**: PocketID, Vaultwarden, Semaphore, Grafana Stack (VictoriaMetrics + Loki), NocoDB, Caddy
- **Customer servers**: Gateway (Caddy) → App servers (Nextcloud, Paperless, etc.)
- **Auth chain**: lldap (user directory) → PocketID (OIDC) → Apps. Apps with native LDAP (Nextcloud, Pingvin Share) connect directly to lldap for real-time user status
- **Tinyauth**: Optional forward-auth proxy (disabled by default, for apps without own auth)
- **Credentials**: All generated passwords stored in Vaultwarden via `scripts/vw-credentials.py`
- **Encryption**: gocryptfs on `/mnt/data`, keyfile only on master
- **Networking**: Netbird VPN (optional) or direct IP connectivity
- **TLS modes**: `acme` (public LE), `cert_sync` (rsync certs from public server), `dns` (DNS-01 challenge), `internal` (Caddy CA)
- **Updates**: Ansible via Semaphore (NO Watchtower — removed due to silent breaking changes)
- **Audit logging**: Docker events + admin actions → Loki via Alloy, customer-visible
- **Self-healing**: Automatic container restart on health failure (systemd timer)
- **Break-glass**: Per-customer emergency admin account (sealed, independent of provider)
- **Customer panel**: Status dashboard with LLDAP user link, emergency contact, self-healing status
- **Compliance**: Auto-generated AVV, TOM, VVT, Löschkonzept per customer

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
  lldap/                 # Lightweight LDAP user directory (user lifecycle)
  pocketid/              # OIDC provider (optionally backed by lldap)
  tinyauth/              # Forward auth
  netbird_client/        # VPN client
  netbird_mtu/           # VPN MTU optimization (MTU 1420, MSS clamping, sysctl)
  netbird_server/        # Self-hosted Netbird management
  gocryptfs/             # Encryption for /mnt/data
  grafana_stack/         # Grafana + VictoriaMetrics + Loki
  alloy/                 # Grafana Alloy agent (customer servers)
  nocodb/                # Permission management
  credentials/           # Vaultwarden API integration
  backup/                # Restic backups (+ Netbird DB)
  key_backup/            # gocryptfs key backup
  compliance/            # AVV, TOM, VVT, Löschkonzept templates
  audit_log/             # Docker events + admin action logging → Loki
  customer_panel/        # Customer dashboard (status, LLDAP, contact, self-healing)
  watchtower/            # DEPRECATED — now removes Watchtower (updates via Ansible)
  monitoring/            # DEPRECATED wrapper → use alloy directly
  lxc_create/            # Proxmox LXC creation
  apps/
    _template/           # Copy for new app roles
    nextcloud/           # MariaDB + Redis
    paperless/           # PostgreSQL + Redis + Gotenberg + Tika
    nc_paperless_bridge/ # Nextcloud↔Paperless inotifywait bridge
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
    invoiceninja/        # MariaDB, Tinyauth (no native OIDC)
    espocrm/             # MariaDB, OIDC via PocketID (UI config)
    planka/              # PostgreSQL, OIDC via PocketID
    vikunja/             # PostgreSQL, OIDC via PocketID
    leantime/            # MariaDB, OIDC via PocketID
    kimai/               # MariaDB, Tinyauth + LDAP (SAML only)
    solidtime/           # PostgreSQL, Tinyauth
    zulip/               # PG + RabbitMQ + Memcached + Redis, OIDC
    rocketchat/          # MongoDB, OIDC via admin UI
    n8n/                 # PostgreSQL, Tinyauth (OIDC = paid)
    orangehrm/           # MariaDB, OIDC via admin UI
    easy_appointments/   # MySQL, Tinyauth + LDAP
    bookstack/           # MariaDB, OIDC via PocketID
    directus/            # PostgreSQL, OIDC via PocketID (BSL 1.1)
    huly/                # MongoDB + MinIO + Elasticsearch, Tinyauth
    limesurvey/          # PostgreSQL, Tinyauth + LDAP
    authentik/           # PostgreSQL + Redis, all-in-one IdP (customer alt)
    backrest/            # No DB, Tinyauth (Restic Web UI)
playbooks/
  setup-master.yml       # Master setup (run first)
  setup-admin-gateway.yml # Admin gateway (*.admin.example.com → Master via Netbird)
  onboard-customer.yml   # New customer
  site.yml               # Full deploy (idempotent)
  add-app.yml            # Single app
  add-server.yml         # Bootstrap fresh server
  add-user.yml           # Create user in PocketID/LLDAP
  remove-user.yml        # Remove user from PocketID/LLDAP
  remove-app.yml         # Remove app (archive data, not delete)
  update-customer.yml    # Pull + recreate all Docker containers (Watchtower replacement)
  update-app.yml         # Update single app
  update-all.yml         # Update all customers
  update-caddy.yml       # Update Caddy config only
  backup-now.yml         # Trigger immediate backup
  restore.yml            # Restore from backup
  restore-test.yml       # Monthly backup restore verification
  generate-docs.yml      # Regenerate compliance documents
  setup-breakglass.yml   # Create break-glass emergency admin account
  offboard-customer.yml  # Full offboarding (backup, stop, cleanup)
  disable-user.yml       # Offboarding: disable user across non-LDAP apps
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
- **NO Watchtower**: Removed — updates via `update-customer.yml` (Semaphore trigger). OS patches via unattended-upgrades
- **SSO-only**: All apps disable email/password login when OIDC is enabled. Caddy blocks signup/register paths as defense-in-depth
- **Break-glass**: Every customer gets a sealed emergency admin account via `setup-breakglass.yml`
- **AVV required**: Every customer must have an AVV (auto-generated via compliance role)
- **Tinyauth**: Disabled by default (`loco.tinyauth.enabled`). Only for apps without native auth
- **Secrets**: Never in Git. Ansible Vault or Vaultwarden only.

## Rules Location

Detailed rules are in `.claude/rules/`:
- `coding-standards.md` — Ansible, Jinja2, Docker, Caddy patterns
- `known-issues.md` — Fallstricke with solutions
- `new-app-checklist.md` — Checklist for new app roles
- `cleanup.md` — Post-task cleanup rules
- `documentation.md` — What to document when
