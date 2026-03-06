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
| Tinyauth deaktiviert per Default | Alle Apps haben eigene OIDC-Auth via PocketID (SSO-only, Signup disabled). Tinyauth ist optional (`loco.tinyauth.enabled: false`) für Apps ohne eigene Auth. Verursachte CSS/JS-Ladeprobleme bei öffentlichen Signing-Links (Documenso `/d/*`). |
| LXC Bootstrap Chicken-and-Egg | Frische LXCs haben kein SSH/Netbird. Lösung: `pct exec` via Proxmox-Host (delegiert). |
| Netbird-IP erst nach Join bekannt | Bootstrap via `pct exec`, Netbird-IP aus `netbird status --json` lesen, dann `hosts.yml` updaten. |
| Watchtower + `:latest` = Breaking Changes | Image-Tags auf Major-Version pinnen (`nextcloud:29`). Watchtower nur Label-basiert. Major-Updates manuell. |
| Watchtower darf KEINE Infra-Container updaten | Netbird, Caddy, PocketID, Tinyauth, Semaphore, Grafana, Alloy, NocoDB: KEIN Watchtower-Label. Updates NUR über Ansible. Vorfall: Watchtower hat Netbird-Server aktualisiert → Relay-Endpoint geändert → Tunnel kaputt. |
| Netbird 502 nach Watchtower-Update (v0.65.3) | Ab v0.65.0 hat Netbird den Relay-Endpoint von `/relay/*` auf `/relay*` geändert. Caddy-Pfad-Matcher greift nicht mehr + TLS-SNI-Mismatch. Fix: `handle /relay*` (ohne Slash) und `tls_server_name` pro Domain im `transport http` Block. |
| Netbird P2P statt Relay (Server ↔ LXC) | Wenn Netbird-Server und Peer auf demselben Host laufen: Eingebetteter STUN-Server kann sich nicht selbst vermitteln → STUN bleibt auf "Checking..." hängen → Relay statt P2P. Fix: Externe STUN-Server (Cloudflare + Google) in `/opt/stacks/netbird/config.yaml` eintragen. |
| Netbird v0.66.0 JSON-Format geändert | `netbird status --json` hat kein top-level `.status`/`.ip` mehr. Stattdessen: `.management.connected` (bool) und `.netbirdIp` (string mit CIDR). `netbird_client`-Rolle wurde angepasst. |
| Netbird MTU 1280 (Standard) | Netbird setzt wt0 auf MTU 1280 statt WireGuard-Standard 1420. ~10% Throughput-Verlust + Protokollprobleme. Fix: `netbird_mtu`-Rolle (systemd Service MTU 1420, nftables MSS 1240, sysctl TCP MTU Probing). Wird automatisch nach `netbird_client` deployed. In LXC: kein udev, systemd `BindsTo=` funktioniert. Mobile Clients (Android/iOS) bleiben bei 1280 — Server-MSS Clamping schützt deren TCP-Traffic. |
| nftables flush ruleset löscht UFW/Docker | `nftables.service` macht `flush ruleset` beim Start → UFW und Docker-Regeln weg. MSS Clamping deshalb als eigener systemd-Service mit eigenem nft-Table (`netbird-mss-local`), NICHT über `nftables.service`. |
| nft/sysctl Pfad in LXC | `/usr/sbin/nft` und `/usr/sbin/sysctl` sind auf Debian 12 LXC möglicherweise nicht im PATH. Templates verwenden volle Pfade. |
| LXC-Template fehlt auf Proxmox | Ansible muss Template via `pveam download` herunterladen bevor LXC-Erstellung. |
| gocryptfs nach Reboot nicht gemountet | Systemd-Service `gocryptfs-mount.service` prüfen. Muss VOR `docker.service` starten. Master erreichbar? SSH-Key gültig? |
| gocryptfs Keyfile auf Server vergessen | SOFORT löschen! Keyfile darf nur auf Master + Key-Backup liegen. |
| Caddy HTTP/2 leere Responses über Netbird VPN | HTTP/2 Binary Framing + WireGuard MTU ~1420 → Frame-Fragmentierung, Stream-Desync. Fix: `versions 1.1` im `transport http` Block + `tls_server_name` + `header_up Host`. Gilt für alle `reverse_proxy https://` über Netbird. |
| Grafana Alloy hoher RAM | `--server.http.memory-limit-mb=256` auf kleinen LXCs. WAL-Größe begrenzen. |
| Loki Retention greift nicht | `compactor` muss in Loki-Config aktiviert sein. Ohne Compactor werden alte Chunks nicht gelöscht. |
| ACME schlägt fehl bei Netbird-only Setup | Server nicht öffentlich erreichbar → HTTP-01 Challenge fehlschlägt. Fix: `admin.tls_mode` in Config auf `cert_sync`, `dns` oder `internal` setzen. Siehe `setup.sh` TLS-Frage. |
| Caddy `tls internal` + Vaultwarden SSO | Vaultwarden validiert OIDC server-seitig gegen PocketID via HTTPS. Bei internem TLS muss Container die Caddy-CA vertrauen: `ca-bundle.crt` (System-CAs + Caddy-CA) wird als Volume gemountet + `extra_hosts` für DNS-Auflösung. Bundle wird erst nach Caddy-Start komplett — Caddy-Rolle erstellt Bundle und restartet Vaultwarden. |
| Caddy DNS-Modus braucht Custom Image | Standard `caddy:2` hat kein DNS-Plugin. Bei `tls_mode: dns` wird ein `Dockerfile` mit `xcaddy build --with github.com/caddy-dns/<provider>` deployed. `docker compose build` statt Pull. |
| Cert-Server: Caddy Docker vs systemd | Cert-Server kann Caddy als Docker-Container oder systemd-Service betreiben. Docker: Certs in Docker-Volume (dynamisch via `docker volume inspect`), Caddyfile auf Host (bind mount), `docker restart caddy`. Systemd: Certs in `/var/lib/caddy/...`, Caddyfile `/etc/caddy/Caddyfile`, `systemctl reload caddy`. Export-Script erkennt Modus automatisch. |
| Cert-Export: Bind-Mounts nicht erkannt | Cert-Export-Script suchte nur Named Volumes + systemd-Pfade. Bind-Mount (`/opt/stacks/caddy/data:/data`) wurde nicht gefunden. Fix: Prüfreihenfolge Bind-Mount (`docker inspect`) → Named Volume → systemd-Pfad. `setup.sh` Export-Script ist angepasst. |
| Caddyfile Duplikate auf Cert-Server | `cat >> Caddyfile` mehrfach ausgeführt → doppelte Admin-Cert-Blöcke → Caddy-Fehler. Fix: `setup.sh` entfernt bestehende Admin-Blöcke (inkl. alte aus früheren Setups) per `sed` bevor der neue Block angehängt wird. Alle Caddyfile-Modifikationen müssen idempotent sein. |
| Caddy cert_sync: fehlendes Cert → kompletter Ausfall | Caddy validiert ALLE referenzierten Cert-Dateien beim Start. Fehlt eine → Startup-Abbruch → ALLE Dienste down. Fix: `ensure-certs.sh` erzeugt selbstsignierte Platzhalter für fehlende Certs VOR Caddy-Start. Werden beim nächsten cert-sync durch echte Certs ersetzt. |

## App-spezifisch

| Problem | Lösung |
|---------|--------|
| Nextcloud HSTS-Warning | Apache im Container setzt Header selbst via Volume-Mount `security.conf` |
| Nextcloud Single Logout | `--send-id-token-hint=0` in user_oidc setzen |
| Nextcloud extrem langsam (1+ Min Ladezeit) | Tinyauth Forward-Auth als Bottleneck: Jeder Sub-Request (JS, CSS, Fonts, Bilder — 184 Stück) geht durch Tinyauth-Roundtrip über Netbird. 184 × 150ms + Queuing = über 1 Minute. Fix: `import auth` aus dem Nextcloud Caddy-Block entfernen — NC hat eigene OIDC-Auth über PocketID. |
| Paperless ESC-Registrierung | `PAPERLESS_ACCOUNT_ALLOW_SIGNUPS: false` explizit setzen! |
| PocketID /register | Per Caddy auf 403 blocken. PocketID kann Registrierung nicht nativ deaktivieren. |
| Netbird Dashboard lokaler Login | Combined Setup: `localAuthDisabled: true` in `config.yaml` unter `auth:` setzen, dann `docker restart netbird-server`. Embedded IdP (Dex) muss auch `enabled: false` sein. Vorher PocketID als externen IdP konfigurieren, sonst Aussperrung! |
| Semaphore DB env var | `SEMAPHORE_DB` (NICHT `SEMAPHORE_DB_NAME`). Falscher Name → Semaphore kann keine DB-Verbindung herstellen → Crash beim Start → Connection refused auf Port 3000. |
| Semaphore PG Passwort-Mismatch | PostgreSQL liest `POSTGRES_PASSWORD` nur bei erster DB-Init. Bei erneutem Run mit neuem Passwort → `password authentication failed`. `deploy.yml` hat zweistufigen Schutz: 1) Passwort-Persistenz aus bestehender `.env`, 2) Auto-Recovery bei Mismatch (Logs prüfen → DB-Reset → Neustart). |

## Caddy

| Problem | Lösung |
|---------|--------|
| handle-Reihenfolge | Spezifische Matcher VOR Fallback `handle {}`. Sonst blockt Auth public Pfade. |
| CSP per App | Nicht global setzen. VW, NC, PocketID, Paperless setzen eigenen CSP. |
| Inode nach Template-Write | Immer `docker restart caddy`, nie `caddy reload`. |
| Caddy `handle` Pfad-Matching | `handle /path*` matcht `/path` UND `/path/foo`. `handle /path/*` matcht NUR `/path/foo`, NICHT `/path` allein. Für Endpoints die beides brauchen (z.B. Netbird `/relay`): immer `handle /path*` ohne Slash. |
| TLS SNI bei Reverse Proxy über Netbird | `reverse_proxy https://100.x.x.x` sendet die IP als SNI → Backend-Caddy hat kein Zert dafür → 502. Lösung: `tls_server_name domain.de` pro Route setzen, kein generisches Snippet. |
| Caddy-Änderung nach nano wirkungslos | nano erstellt neue Datei (neuer Inode), Docker Bind-Mount referenziert den alten Inode. `docker restart caddy` löst es — ggf. auch Browser-Cache leeren. Besser: Ansible-Templates statt manueller Edits. |
| Caddy HTTP/2 über VPN → leerer Body | `reverse_proxy https://` über Netbird: H2 Binary Framing fragmentiert bei WireGuard MTU ~1420 → 200 OK aber leerer Body, Backend bekommt nichts. Fix: `versions 1.1` im `transport http` Block erzwingen. Immer zusammen mit `tls_server_name` und `header_up Host` verwenden. |

## Bootstrap

| Problem | Lösung |
|---------|--------|
| Caddy-Handler vor Caddy-Rolle | Vaultwarden notifiziert `restart caddy`, aber Caddy-Rolle kommt später im Playbook. Handler toleriert `No such container` via `failed_when`. |
| urllib verliert Cookies bei Redirect | `vw-credentials.py` Admin-Login: `urllib` folgt 302/303 und verliert `Set-Cookie`. Fix: `http.client` statt `urllib` für Admin-Login. |
| JSON-Template mit Sonderzeichen | Ansible `copy: content:` mit `"{{ variable }}"` erzeugt kaputtes JSON wenn Werte Anführungszeichen enthalten. Fix: `{{ dict | to_json }}`. |

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
| PocketID v2 API-Header | `X-API-Key: <token>`, NICHT `Authorization: Bearer <token>`. PocketID v2 akzeptiert nur `X-API-Key` für STATIC_API_KEY-Auth. |
| PocketID Token Precedence | `pocketid_api_token` NICHT als role-level `vars:` setzen (Precedence 21 überschreibt `set_fact`). Nur als play-level `vars:` (Precedence 14). |
| PocketID v2 Client Secret | `POST /api/oidc/clients` gibt KEIN Secret zurück. Secret separat generieren: `POST /api/oidc/clients/{id}/secret` → `{"secret": "..."}`. |
| Vaultwarden API ≠ Admin-Token | `/api/ciphers` braucht User-JWT (OAuth2 Login) + client-seitige Verschlüsselung. Admin-Token nur für `/admin/`. `credentials`-Rolle nutzt `scripts/vw-credentials.py` (Bitwarden-Protokoll vollautomatisch). |
| Vaultwarden Register 404 | Ab VW 1.33+ ist `/api/accounts/register` entfernt. Primärer Pfad: `/identity/accounts/register`. Ab 1.34+: neuer Flow über `send-verification-email` + `finish`. `vw-credentials.py` probiert alle drei Pfade automatisch. |
| Vaultwarden Login nach Registration scheitert | `SIGNUPS_ALLOWED=false` blockiert Registration. Fix: `store.yml` erkennt "Registration not allowed", toggelt `SIGNUPS_ALLOWED=true` in `.env` via `lineinfile`, macht `docker compose down/up` (NICHT `docker restart` — restart liest env_file nicht neu ein!), registriert, und stellt `SIGNUPS_ALLOWED=false` wieder her (block/always). Zwei Recreates nur beim ersten Mal. |
| Vaultwarden SSO_ONLY blockiert Service-User-Login | `SSO_ONLY=true` erzwingt SSO-Login für alle User → `vw-credentials.py` Service-User kann sich nicht per Passwort anmelden → "SSO sign-in is required". Fix: `store.yml` erkennt den Fehler, toggelt `SSO_ONLY=false` in `.env` (zusammen mit `SIGNUPS_ALLOWED=true`), `docker compose down/up`, Retry, Restore. Wichtig: `when`-Bedingung im Block darf NICHT `_vw_store_result` referenzieren (wird im Retry überschrieben → `always` wird übersprungen). Stattdessen `set_fact` Flag VOR dem Block setzen. |
| Vaultwarden Admin-Invite blockiert Registration | Ab VW 1.32+ erstellt `POST /admin/invite` einen User-Record in der DB. Anschliessende Registration schlaegt fehl mit "user already exists". Fix: `vw-credentials.py` registriert DIREKT ohne Invite-Schritt. Bei `SIGNUPS_ALLOWED=true` (via Ansible Toggle) funktioniert direkte Registration. |
| Vaultwarden Admin-API /users/overview gibt HTML | `GET /admin/users/overview` gibt HTML zurueck, NICHT JSON. `vw-credentials.py` muss `GET /admin/users` verwenden (gibt JSON-Liste). |
| Netbird Repo Signed-By Konflikt | Manueller Install legt `/usr/share/keyrings/netbird-archive-keyring.gpg` an, Ansible will `/etc/apt/keyrings/netbird.asc` → apt-Fehler. `netbird_client`-Rolle räumt Legacy-Key/Repo auf. |
| `to_native` Deprecation Warning | Upstream-Bug in Ansible-Core `authorized_key`-Modul (Import aus `ansible.module_utils._text`). Wird in ansible-core 2.24 entfernt. Kein Fix unsererseits möglich — warten auf upstream Patch. |
| Python Interpreter Warning | `ansible_python_interpreter: /usr/bin/python3` explizit im Inventar setzen. Sonst warnt Ansible bei jeder neuen Python-Version. |
