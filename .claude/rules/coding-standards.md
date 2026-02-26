# Coding-Standards

## Ansible

- **Idempotenz ist Pflicht.** Jeder Task muss mehrfach ausführbar sein ohne Seiteneffekte. `state: present` statt `command: apt install`.
- **`docker compose` (V2 Plugin)**, NICHT `docker-compose` (V1 deprecated).
- **Keine rohen `command`/`shell`-Aufrufe** wenn ein Ansible-Modul existiert.
- **Handler-Pattern:** Änderung → notify Handler → Handler am Ende des Plays. Wenn sofort nötig: `meta: flush_handlers`.
- **Variablen-Herkunft:** `config/lococloudd.yml` (global), `group_vars/all.yml` (pro Kunde), `defaults/main.yml` (pro Rolle). Niemals hardcoden.
- **Globale Config laden:** In jedem Playbook als `pre_tasks`:
  ```yaml
  pre_tasks:
    - name: Load global config
      include_vars:
        file: "{{ playbook_dir }}/../config/lococloudd.yml"
        name: loco
  ```
- **Tags verwenden** für granulare Ausführung: `tags: [base, hardening]`, `tags: [caddy, config]`.

## Jinja2-Templates

- **Header in generierten Dateien:**
  ```
  # ============================================
  # GENERIERT DURCH ANSIBLE — NICHT MANUELL EDITIEREN
  # Kunde: {{ kunde_name }} ({{ kunde_domain }})
  # Generiert: {{ ansible_facts.date_time.iso8601 }}
  # ============================================
  ```
- **Keine Logik in Templates** die in Rollen gehört. Templates rendern nur Variablen.

## Docker Compose

- **Immer `restart: unless-stopped`**
- **Immer expliziter `container_name`**
- **Port-Binding:** `127.0.0.1:PORT` auf Entry-Point-Servern, `0.0.0.0:PORT` auf App-LXCs (+ UFW auf `wt0`)
- **Volumes:** Explizite Host-Pfade, keine anonymen Volumes.
- **PostgreSQL 18:** Mount auf `/var/lib/postgresql` (NICHT `/var/lib/postgresql/data`)
- **.env-Dateien:** `chmod 600`

## Caddyfile

- **`import public`** auf jeder Domain (Security Headers)
- **`import auth`** als Default auf jedem geschützten Pfad
- **Öffentliche Pfade:** Spezifische `handle @matcher`-Blöcke VOR dem Fallback `handle {}`
- **Pfad-Matching:** `handle /path*` (NICHT `handle /path/*`). Mit Slash matcht nur `/path/foo`, ohne Slash matcht auch `/path` allein. Relevant z.B. für Netbird `/relay`.
- **Reverse Proxy über Netbird (TLS):** `tls_server_name` pro Route setzen. `reverse_proxy https://100.x.x.x` ohne `tls_server_name` sendet die IP als SNI → Backend hat kein Zert dafür → 502.
- **HTTP/2 über VPN-Tunnel:** `versions 1.1` im `transport http` Block erzwingen bei `reverse_proxy https://` über Netbird. HTTP/2 Binary Framing fragmentiert bei WireGuard MTU ~1420 → leere Responses. Immer zusammen mit `tls_server_name` und `header_up Host` setzen.
- **CSP:** Nur für Apps OHNE eigenen CSP setzen. Vaultwarden, Nextcloud, PocketID, Paperless setzen ihren eigenen.
- **Nach Änderungen:** `docker restart caddy` (NICHT `caddy reload` — Inode-Problem bei Bind-Mounts)

## Docker Compose — Watchtower-Labels

- **Kunden-Apps** (Nextcloud, Paperless, Vaultwarden-Kunde, Uptime Kuma): `com.centurylinklabs.watchtower.enable=true`
- **Infrastruktur-Container** (Caddy, Netbird, PocketID, Tinyauth, Semaphore, Grafana, Alloy, Baserow): **KEIN Watchtower-Label**. Updates nur über Ansible.
- Grund: Watchtower hat Netbird-Server aktualisiert → Relay-Endpoint geändert → VPN-Ausfall.

## Secrets

- **NIEMALS Klartext in Git.** Weder in Variablen, noch in Kommentaren, noch in Beispielen.
- **`config/lococloudd.yml`** ist in `.gitignore` — nur `.example` wird committed.
- **Kunden-Secrets:** Ansible Vault (`group_vars/vault.yml`)
- **Generierte Passwörter:** `lookup('password', '/dev/null chars=ascii_letters,digits length=32')`
- **Credentials speichern:** `credentials`-Rolle nutzt `scripts/vw-credentials.py`. Das Script implementiert das Bitwarden-Protokoll (OAuth2 Login, AES-256-CBC Verschlüsselung, HMAC) und erstellt automatisch einen Service-User.
- **Vaultwarden API ≠ Admin-Token:** `/api/ciphers` braucht User-JWT + client-seitige Verschlüsselung. `vw-credentials.py` handhabt beides automatisch.
- **Laufzeit-Secrets lesen:** `community.general.bitwarden` Lookup-Plugin:
  ```yaml
  lookup('community.general.bitwarden', 'item-name', field='password')
  ```

## PocketID API-Integration

- **Auth-Header:** `X-API-Key: {{ pocketid_api_token }}` (NICHT `Authorization: Bearer`). PocketID v2 nutzt `X-API-Key`.
- **User anlegen:** `uri`-Modul gegen `https://id.firma.de/api/users` (POST)
- **Gruppen erstellen:** `uri`-Modul gegen `https://id.firma.de/api/user-groups`
- **OIDC-Clients erstellen:** `uri`-Modul gegen `https://id.firma.de/api/oidc/clients` (Name, callbackURLs, Scopes)
- API gibt Client-ID und Client-Secret zurück → in Vaultwarden speichern
- PocketID API-Token wird als Variable `pocketid_api_token` aus Vault geladen
- **Env-Variable im Container:** `STATIC_API_KEY` (mind. 16 Zeichen)
