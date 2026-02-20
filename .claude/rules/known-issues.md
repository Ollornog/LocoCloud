# Bekannte Fallstricke & Lösungen

## Infrastruktur

| Problem | Lösung |
|---------|--------|
| nano erstellt neuen Inode | `docker restart caddy` statt `caddy reload`. Ansible-Handler nutzen. |
| PostgreSQL 18 Mount-Pfad | `/var/lib/postgresql` NICHT `/var/lib/postgresql/data` |
| LXC Kernel-Parameter | `is_lxc`-Variable prüfen. In LXC: nur netzwerk-sysctl, kein `kernel.*`, `fs.*` |
| USB in LXC | NICHT deaktivieren (existiert nicht). `is_lxc`-Check. |
| Docker UFW-Bypass | Docker umgeht UFW. Für App-LXCs mit `0.0.0.0`-Bind: UFW App-Port nur auf `wt0` erlauben. |
| Netbird DNS Konflikte | Custom DNS Zones NUR für interne Domains. Öffentliche Domains NICHT eintragen. |
| Tinyauth nicht prod-ready | Entschieden: Tinyauth reicht (nur OIDC, kein Brute-Force-Risiko). Austauschbar bauen, Fallback auf Authelia. |
| LXC Bootstrap Chicken-and-Egg | Frische LXCs haben kein SSH/Netbird. Lösung: `pct exec` via Proxmox-Host (delegiert). |
| Netbird-IP erst nach Join bekannt | Bootstrap via `pct exec`, Netbird-IP aus `netbird status --json` lesen, dann `hosts.yml` updaten. |
| Watchtower + `:latest` = Breaking Changes | Image-Tags auf Major-Version pinnen (`nextcloud:29`). Watchtower nur Label-basiert. Major-Updates manuell. |
| Watchtower darf KEINE Infra-Container updaten | Netbird, Caddy, PocketID, Tinyauth, Semaphore, Zabbix: KEIN Watchtower-Label. Updates NUR über Ansible. Vorfall: Watchtower hat Netbird-Server aktualisiert → Relay-Endpoint geändert → Tunnel kaputt. |
| LXC-Template fehlt auf Proxmox | Ansible muss Template via `pveam download` herunterladen bevor LXC-Erstellung. |

## App-spezifisch

| Problem | Lösung |
|---------|--------|
| Nextcloud HSTS-Warning | Apache im Container setzt Header selbst via Volume-Mount `security.conf` |
| Nextcloud Single Logout | `--send-id-token-hint=0` in user_oidc setzen |
| Paperless ESC-Registrierung | `PAPERLESS_ACCOUNT_ALLOW_SIGNUPS: false` explizit setzen! |
| PocketID /register | Per Caddy auf 403 blocken. PocketID kann Registrierung nicht nativ deaktivieren. |

## Caddy

| Problem | Lösung |
|---------|--------|
| handle-Reihenfolge | Spezifische Matcher VOR Fallback `handle {}`. Sonst blockt Auth public Pfade. |
| CSP per App | Nicht global setzen. VW, NC, PocketID, Paperless setzen eigenen CSP. |
| Inode nach Template-Write | Immer `docker restart caddy`, nie `caddy reload`. |
| Caddy `handle` Pfad-Matching | `handle /path*` matcht `/path` UND `/path/foo`. `handle /path/*` matcht NUR `/path/foo`, NICHT `/path` allein. Für Endpoints die beides brauchen (z.B. Netbird `/relay`): immer `handle /path*` ohne Slash. |
| TLS SNI bei Reverse Proxy über Netbird | `reverse_proxy https://100.x.x.x` sendet die IP als SNI → Backend-Caddy hat kein Zert dafür → 502. Lösung: `tls_server_name domain.de` pro Route setzen, kein generisches Snippet. |

## Ansible-spezifisch

| Problem | Lösung |
|---------|--------|
| Idempotenz | `state: present`, keine rohen `command`-Aufrufe |
| Secrets in Git | NIEMALS Klartext. Ansible Vault oder Vaultwarden. |
| Handler-Reihenfolge | Laufen am Ende des Plays. `meta: flush_handlers` für sofort. |
| docker-compose V1 vs V2 | `docker compose` (V2 Plugin), NICHT `docker-compose` |
| become in LXC | Ansible braucht `become: true` für Docker als non-root |
| Globale Config laden | `include_vars` in pre_tasks, nicht `ansible.cfg` |
| Health-Check hinter Auth | Backend-Ports (localhost) prüfen, nicht öffentliche URL (Tinyauth gibt sonst 401) |
