# App-Rollen Entwicklung — Anleitung

Diese Anleitung beschreibt, wie eine neue App-Rolle für LocoCloud erstellt wird.

---

## Grundprinzip

Jede App ist eine Ansible-Rolle unter `roles/apps/<appname>/`. Die Rolle muss:

- **Idempotent** sein (mehrfach ausführbar ohne Seiteneffekte)
- **Keine Secrets hardcoden** (alles über Variablen/Vault)
- **OIDC über PocketID** unterstützen (wenn möglich)
- **Credentials in Vaultwarden** speichern

---

## Rollenstruktur

```
roles/apps/<appname>/
├── defaults/
│   └── main.yml          # Alle Variablen mit Kommentaren
├── tasks/
│   ├── main.yml          # Dispatcher (importiert deploy, oidc, remove)
│   ├── deploy.yml        # Container deployen (idempotent)
│   ├── oidc.yml          # OIDC-Client in PocketID registrieren
│   └── remove.yml        # App entfernen (Daten archivieren)
├── templates/
│   ├── docker-compose.yml.j2
│   └── env.j2
└── handlers/
    └── main.yml          # Handler: docker restart caddy
```

---

## Schritt-für-Schritt: Neue Rolle erstellen

### 1. defaults/main.yml

Alle konfigurierbaren Variablen mit Kommentaren:

```yaml
---
# roles/apps/meineapp/defaults/main.yml
# MeineApp — Kurzbeschreibung

meineapp_stack_path: "/opt/stacks/meineapp"
meineapp_image: "meineapp/meineapp:latest"
meineapp_port: 8080

# Domain
meineapp_domain: ""  # z.B. "app.firma-abc.de"

# Database (PostgreSQL)
meineapp_db_image: "postgres:18"
meineapp_db_name: "meineapp"
meineapp_db_user: "meineapp"
meineapp_db_password: ""  # Generated if empty

# OIDC
meineapp_oidc_enabled: false
meineapp_oidc_client_id: ""
meineapp_oidc_client_secret: ""
meineapp_oidc_provider_url: ""

# Public paths (accessible without Tinyauth)
meineapp_public_paths: []

# Backup paths
meineapp_backup_paths:
  - "/opt/stacks/meineapp"

# Health check
meineapp_health_path: "/health"
```

### 2. tasks/main.yml

```yaml
---
# Dispatcher
- name: Deploy MeineApp
  ansible.builtin.import_tasks: deploy.yml
  tags: [meineapp, deploy]

- name: Configure OIDC
  ansible.builtin.import_tasks: oidc.yml
  when: meineapp_oidc_enabled | default(false)
  tags: [meineapp, oidc]
```

### 3. tasks/deploy.yml

```yaml
---
- name: Create MeineApp stack directory
  ansible.builtin.file:
    path: "{{ meineapp_stack_path }}"
    state: directory
    mode: "0755"

# Generate DB password if not set
- name: Generate DB password
  ansible.builtin.set_fact:
    meineapp_db_password: "{{ lookup('password', '/dev/null chars=ascii_letters,digits length=32') }}"
  when: meineapp_db_password | default('') | length == 0

- name: Deploy docker-compose.yml
  ansible.builtin.template:
    src: docker-compose.yml.j2
    dest: "{{ meineapp_stack_path }}/docker-compose.yml"
    mode: "0644"
  notify: restart caddy

- name: Deploy .env
  ansible.builtin.template:
    src: env.j2
    dest: "{{ meineapp_stack_path }}/.env"
    mode: "0600"
  notify: restart caddy

- name: Start MeineApp stack
  community.docker.docker_compose_v2:
    project_src: "{{ meineapp_stack_path }}"
    state: present
    pull: "missing"

- name: Wait for MeineApp to be ready
  ansible.builtin.uri:
    url: "http://127.0.0.1:{{ meineapp_port }}{{ meineapp_health_path }}"
    status_code: [200, 302]
  register: health
  retries: 30
  delay: 5
  until: health.status in [200, 302]
```

### 4. tasks/oidc.yml

OIDC-Client über PocketID REST-API registrieren:

```yaml
---
# Create OIDC client in PocketID via API
- name: Create OIDC client in PocketID
  ansible.builtin.uri:
    url: "https://{{ pocketid_domain | default('id.' + kunde_domain) }}/api/oidc/clients"
    method: POST
    headers:
      Authorization: "Bearer {{ pocketid_api_token }}"
    body_format: json
    body:
      name: "{{ app_name | default('MeineApp') }}"
      callbackURLs:
        - "https://{{ meineapp_domain }}/callback"
    status_code: [200, 201]
  register: oidc_client
  when: meineapp_oidc_client_id | default('') | length == 0

- name: Set OIDC credentials
  ansible.builtin.set_fact:
    meineapp_oidc_client_id: "{{ oidc_client.json.client_id }}"
    meineapp_oidc_client_secret: "{{ oidc_client.json.client_secret }}"
  when: oidc_client is not skipped

# Store in Vaultwarden
- name: Store OIDC credentials in Vaultwarden
  ansible.builtin.include_role:
    name: credentials
    tasks_from: store.yml
  vars:
    vw_api_url: "{{ loco.vaultwarden.url }}"
    credential_name: "{{ kunde_name | default('') }} — MeineApp OIDC"
    credential_username: "{{ meineapp_oidc_client_id }}"
    credential_password: "{{ meineapp_oidc_client_secret }}"
    credential_uri: "https://{{ meineapp_domain }}"
    credential_notes: "OIDC Client for MeineApp. Created: {{ ansible_facts.date_time.iso8601 }}"
  when: oidc_client is not skipped

# Redeploy .env with OIDC credentials
- name: Redeploy .env with OIDC credentials
  ansible.builtin.template:
    src: env.j2
    dest: "{{ meineapp_stack_path }}/.env"
    mode: "0600"
  notify: restart caddy

# Restart to pick up OIDC config
- name: Restart MeineApp for OIDC
  community.docker.docker_compose_v2:
    project_src: "{{ meineapp_stack_path }}"
    state: restarted
  when: oidc_client is not skipped
```

### 5. tasks/remove.yml

```yaml
---
- name: Stop MeineApp stack
  community.docker.docker_compose_v2:
    project_src: "{{ meineapp_stack_path }}"
    state: absent
  ignore_errors: true

- name: Archive MeineApp data
  ansible.builtin.command: >
    tar czf /opt/archives/meineapp-{{ ansible_facts.date_time.date }}.tar.gz
    -C {{ meineapp_stack_path }} .
  args:
    creates: "/opt/archives/meineapp-{{ ansible_facts.date_time.date }}.tar.gz"
```

### 6. templates/docker-compose.yml.j2

```yaml
# ============================================
# GENERIERT DURCH ANSIBLE — NICHT MANUELL EDITIEREN
# Kunde: {{ kunde_name | default('N/A') }} ({{ kunde_domain | default('N/A') }})
# Generiert: {{ ansible_facts.date_time.iso8601 }}
# ============================================
services:
  meineapp:
    image: {{ meineapp_image }}
    container_name: meineapp
    restart: unless-stopped
    ports:
      - "{{ '127.0.0.1' if 'gateway' in server_roles else '0.0.0.0' }}:{{ meineapp_port }}:8080"
    env_file:
      - .env
    volumes:
      - ./data:/app/data
{% if meineapp_db_image is defined %}

  meineapp-db:
    image: {{ meineapp_db_image }}
    container_name: meineapp-db
    restart: unless-stopped
    volumes:
      - ./db:/var/lib/postgresql
    environment:
      POSTGRES_DB: {{ meineapp_db_name }}
      POSTGRES_USER: {{ meineapp_db_user }}
      POSTGRES_PASSWORD: {{ meineapp_db_password }}
{% endif %}
```

### 7. templates/env.j2

```
# ============================================
# GENERIERT DURCH ANSIBLE — NICHT MANUELL EDITIEREN
# Generiert: {{ ansible_facts.date_time.iso8601 }}
# ============================================
DATABASE_URL=postgresql://{{ meineapp_db_user }}:{{ meineapp_db_password }}@meineapp-db/{{ meineapp_db_name }}
{% if meineapp_oidc_enabled and meineapp_oidc_client_id | default('') | length > 0 %}
OIDC_CLIENT_ID={{ meineapp_oidc_client_id }}
OIDC_CLIENT_SECRET={{ meineapp_oidc_client_secret }}
OIDC_PROVIDER_URL={{ meineapp_oidc_provider_url }}
{% endif %}
```

### 8. handlers/main.yml

```yaml
---
- name: restart caddy
  ansible.builtin.command: docker restart caddy
  changed_when: true
  listen: restart caddy
```

---

## Wichtige Regeln

### Port-Binding

- **Entry-Point-Server** (`online`, `gateway`, `all_in_one`): `127.0.0.1:PORT`
- **App-LXCs** (`app`, `apps`): `0.0.0.0:PORT` (+ UFW auf `wt0`)

### PostgreSQL 18

Mount-Pfad ist `/var/lib/postgresql`, NICHT `/var/lib/postgresql/data`.

### Docker Compose

- Immer `restart: unless-stopped`
- Immer expliziter `container_name`
- Volumes: Explizite Host-Pfade, keine anonymen Volumes

### .env-Dateien

- Immer `mode: "0600"` im Ansible-Template-Task
- Secrets als Variablen, niemals hardcodiert

### Watchtower

- Kunden-Apps bekommen: `labels: { com.centurylinklabs.watchtower.enable: "true" }`
- Infrastruktur-Container: KEIN Watchtower-Label

### CSP (Content Security Policy)

Nur für Apps setzen, die keinen eigenen CSP haben. Vaultwarden, Nextcloud, PocketID, Paperless setzen ihren eigenen CSP.

---

## Tinyauth-Integration

Apps werden über Caddy + Tinyauth geschützt. Im Kunden-Caddyfile:

- Default: Alles hinter `import auth`
- Öffentliche Pfade: Über `public_paths` in der App-Konfiguration definieren

---

## Testen

1. **Deployment:** `ansible-playbook playbooks/add-app.yml -i inventories/kunde-test/ -e "app_name=MeineApp"`
2. **Idempotenz:** Playbook 2x ausführen → beim 2. Lauf keine `changed`-Tasks
3. **OIDC:** Login über PocketID testen
4. **Remove:** `ansible-playbook playbooks/remove-app.yml -i inventories/kunde-test/ -e "app_name=MeineApp"`

---

## Bestehende App-Rollen als Referenz

| Rolle | Besonderheiten |
|-------|---------------|
| `nextcloud` | MariaDB + Redis, occ-Befehle, HSTS-Fix, user_oidc |
| `paperless` | PostgreSQL + Redis + Gotenberg + Tika, OIDC |
| `vaultwarden` | SQLite, Admin-Token, SSO |
| `semaphore` | PostgreSQL, OIDC, Access-Key-Persistenz |
| `uptime_kuma` | Einfachste Rolle, kein OIDC, kein DB |
