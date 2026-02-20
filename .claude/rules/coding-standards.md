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
  # Generiert: {{ ansible_date_time.iso8601 }}
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
- **CSP:** Nur für Apps OHNE eigenen CSP setzen. Vaultwarden, Nextcloud, PocketID, Paperless setzen ihren eigenen.
- **Nach Änderungen:** `docker restart caddy` (NICHT `caddy reload` — Inode-Problem bei Bind-Mounts)

## Secrets

- **NIEMALS Klartext in Git.** Weder in Variablen, noch in Kommentaren, noch in Beispielen.
- **`config/lococloudd.yml`** ist in `.gitignore` — nur `.example` wird committed.
- **Kunden-Secrets:** Ansible Vault (`group_vars/vault.yml`)
- **Generierte Passwörter:** `lookup('password', '/dev/null chars=ascii_letters,digits length=32')`
- **Alles in Vaultwarden speichern** über die `credentials`-Rolle.
- **Laufzeit-Secrets lesen:** `community.general.bitwarden` Lookup-Plugin:
  ```yaml
  lookup('community.general.bitwarden', 'item-name', field='password')
  ```

## PocketID API-Integration

- **User anlegen:** `uri`-Modul gegen `https://id.firma.de/api/users` (POST, Bearer-Token)
- **Gruppen erstellen:** `uri`-Modul gegen `https://id.firma.de/api/user-groups`
- **OIDC-Clients erstellen:** `uri`-Modul gegen `https://id.firma.de/api/oidc-clients` (Name, Callback-URLs, Scopes)
- API gibt Client-ID und Client-Secret zurück → in Vaultwarden speichern
- PocketID API-Token wird als Variable `pocketid_api_token` aus Vault geladen
