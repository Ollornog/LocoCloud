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
| Tinyauth nicht prod-ready | Im Betrieb bewährt: Nur OIDC-Forward-Auth via PocketID (kein direkter Login, kein Brute-Force-Risiko). Kein Fallback nötig. |
| LXC Bootstrap Chicken-and-Egg | Frische LXCs haben kein SSH/Netbird. Lösung: `pct exec` via Proxmox-Host (delegiert). |
| Netbird-IP erst nach Join bekannt | Bootstrap via `pct exec`, Netbird-IP aus `netbird status --json` lesen, dann `hosts.yml` updaten. |
| Watchtower + `:latest` = Breaking Changes | Image-Tags auf Major-Version pinnen (`nextcloud:29`). Watchtower nur Label-basiert. Major-Updates manuell. |
| Watchtower darf KEINE Infra-Container updaten | Netbird, Caddy, PocketID, Tinyauth, Semaphore, Zabbix: KEIN Watchtower-Label. Updates NUR über Ansible. Vorfall: Watchtower hat Netbird-Server aktualisiert → Relay-Endpoint geändert → Tunnel kaputt. |
| Netbird 502 nach Watchtower-Update (v0.65.3) | Ab v0.65.0 hat Netbird den Relay-Endpoint von `/relay/*` auf `/relay*` geändert. Caddy-Pfad-Matcher greift nicht mehr + TLS-SNI-Mismatch. Fix: `handle /relay*` (ohne Slash) und `tls_server_name` pro Domain im `transport http` Block. |
| Netbird P2P statt Relay (Server ↔ LXC) | Wenn Netbird-Server und Peer auf demselben Host laufen: Eingebetteter STUN-Server kann sich nicht selbst vermitteln → STUN bleibt auf "Checking..." hängen → Relay statt P2P. Fix: Externe STUN-Server (Cloudflare + Google) in `/opt/stacks/netbird/config.yaml` eintragen. |
| LXC-Template fehlt auf Proxmox | Ansible muss Template via `pveam download` herunterladen bevor LXC-Erstellung. |

## App-spezifisch

| Problem | Lösung |
|---------|--------|
| Nextcloud HSTS-Warning | Apache im Container setzt Header selbst via Volume-Mount `security.conf` |
| Nextcloud Single Logout | `--send-id-token-hint=0` in user_oidc setzen |
| Nextcloud extrem langsam (1+ Min Ladezeit) | Tinyauth Forward-Auth als Bottleneck: Jeder Sub-Request (JS, CSS, Fonts, Bilder — 184 Stück) geht durch Tinyauth-Roundtrip über Netbird. 184 × 150ms + Queuing = über 1 Minute. Fix: `import auth` aus dem Nextcloud Caddy-Block entfernen — NC hat eigene OIDC-Auth über PocketID. |
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
| Caddy-Änderung nach nano wirkungslos | nano erstellt neue Datei (neuer Inode), Docker Bind-Mount referenziert den alten Inode. `docker restart caddy` löst es — ggf. auch Browser-Cache leeren. Besser: Ansible-Templates statt manueller Edits. |

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
