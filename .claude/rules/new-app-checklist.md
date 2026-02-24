# Checkliste: Neue App-Rolle

Wenn eine neue App als Ansible-Rolle implementiert wird:

## Rollenstruktur

- [ ] `roles/apps/<appname>/defaults/main.yml` mit allen Variablen + Kommentaren
- [ ] `roles/apps/<appname>/templates/docker-compose.yml.j2` — Port-Binding je nach Server-Rolle
- [ ] `roles/apps/<appname>/templates/env.j2` — Secrets als Variablen
- [ ] `roles/apps/<appname>/tasks/deploy.yml` — idempotent
- [ ] `roles/apps/<appname>/tasks/oidc.yml` — OIDC-Client in PocketID registrieren
- [ ] `roles/apps/<appname>/tasks/remove.yml` — Daten archivieren, nicht löschen
- [ ] `roles/apps/<appname>/handlers/main.yml` — `docker restart caddy`

## PocketID API-Integration (in `oidc.yml`)

- [ ] OIDC-Client über PocketID REST-API erstellen (`uri`-Modul, Bearer-Token)
- [ ] Callback-URL korrekt setzen: `https://{{ app_subdomain }}.{{ kunde_domain }}{{ app_oidc_redirect_path }}`
- [ ] Client-ID und Client-Secret aus API-Response extrahieren
- [ ] Credentials über `credentials`-Rolle in Admin-Vaultwarden speichern
- [ ] App mit OIDC-Credentials konfigurieren (`.env` oder Config-Datei)

## Konfiguration

- [ ] Public Paths definiert (oder leer = komplett geschützt)
- [ ] Backup-Pfade definiert (auf `/mnt/data/`)
- [ ] Pre-Backup-Hook: DB-Dump definiert falls DB vorhanden
- [ ] Health-Check definiert (Port + Path für Grafana Monitoring)
- [ ] Audit-Logging aktiviert und dokumentiert
- [ ] PostgreSQL 18: Mount auf `/var/lib/postgresql`
- [ ] Redis: Bei `single_lxc` DB-Nummer zuweisen, bei `lxc_per_app` eigener Container
- [ ] CSP: Nur setzen wenn App keinen eigenen hat

## Compliance

- [ ] VVT-Eintrag: Verarbeitungstätigkeit im `compliance`-Template definiert
- [ ] Daten in `/mnt/data/` ablegen (gocryptfs-geschützt)
- [ ] Löschfristen im Löschkonzept-Template definiert

## Qualität

- [ ] Keine hardcodierten Domains/E-Mails
- [ ] Idempotenz getestet (Playbook 2x laufen lassen)
- [ ] `docs/APP-DEVELOPMENT.md` aktualisiert
- [ ] Repo-Struktur in `CLAUDE.md` aktualisiert
