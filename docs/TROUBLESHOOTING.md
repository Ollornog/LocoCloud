# Troubleshooting — Bekannte Probleme & Lösungen

---

## Infrastruktur

### Caddy: 502 Bad Gateway nach Template-Update

**Problem:** Nach Änderung eines Caddy-Templates per Ansible kommt 502.

**Ursache:** `nano`/Template-Write erstellt einen neuen Inode. `caddy reload` findet die alte Datei.

**Lösung:**
```bash
docker restart caddy
```

Ansible-Handler verwenden: `notify: restart caddy` → Handler führt `docker restart caddy` aus.

---

### Caddy: 502 bei Reverse Proxy über Netbird

**Problem:** `reverse_proxy https://100.x.x.x` liefert 502.

**Ursache:** Caddy sendet die IP als SNI. Das Backend-Caddy hat kein Zertifikat für die IP → TLS-Handshake schlägt fehl.

**Lösung:** `tls_server_name` pro Route setzen:

```
reverse_proxy https://100.x.x.x {
    transport http {
        tls_server_name app.firma-abc.de
    }
}
```

---

### Caddy: HTTP/2 Reverse Proxy über Netbird VPN — Leere Responses

**Problem:** Wenn Caddy per `reverse_proxy https://` über das Netbird WireGuard-VPN an ein HTTPS-Backend proxied, liefert HTTP/2 leere 200-Responses (Content-Length: 0, kein Body, keine Upstream-Headers). Der Request erreicht das Backend nicht — tcpdump auf dem Backend zeigt keine eingehenden Pakete. Caddy loggt keinen Fehler, gibt aber nur die eigenen Header zurück (public-Snippet).

**Ursache:** HTTP/2 Binary Framing über den WireGuard-Tunnel (MTU ~1420) führt zu Frame-Fragmentierung und Stream-State-Desynchronisation. Die TLS-in-WireGuard-Encapsulation reduziert die effektive Payload, HTTP/2 HPACK-State und Flow-Control-Windows geraten durch Paket-Reordering aus dem Takt. Caddy parsed die H2-Response-Header (daher 200), aber DATA-Frames kommen nicht sauber durch.

**Diagnose-Schritte die zum Fix führten:**
1. `curl -skv` durch Hetzner Caddy: 200 mit leerem Body
2. Direkt zur Cloud-LXC (`--resolve` auf Netbird-IP): 302 mit allen Headers → Backend OK
3. `curl -skv https://100.114.17.50`: TLS Alert "internal error" (SNI = IP statt Domain)
4. `curl --resolve cloud.ollornog.de:443:100.114.17.50`: Funktioniert → TLS/SNI OK
5. tcpdump auf Cloud-LXC wt0: Kein Traffic von Hetzner-IP → H2 Connection steckt fest
6. `versions 1.1` erzwingen: Sofort funktionsfähig

**Lösung:** Im Caddyfile `versions 1.1` im transport-Block setzen, plus expliziten `header_up Host` und `tls_server_name`:

```caddyfile
cloud.ollornog.de {
    import public
    handle {
        reverse_proxy https://100.114.17.50 {
            header_up Host cloud.ollornog.de
            transport http {
                tls_insecure_skip_verify
                tls_server_name cloud.ollornog.de
                versions 1.1
            }
        }
    }
}
```

**Gilt für:** Alle `reverse_proxy`-Blöcke die über Netbird VPN an ein HTTPS-Backend proxien.

**Datum:** 26. Februar 2026

---

### Caddy: Auth blockiert öffentliche Pfade

**Problem:** Public Paths (z.B. Nextcloud-Sharing `/s/*`) werden trotzdem von Tinyauth blockiert.

**Ursache:** Falsche Reihenfolge im Caddyfile — spezifische Matcher müssen VOR dem Fallback `handle {}` stehen.

**Lösung:** Im Caddyfile-Template: `handle`-Blöcke für öffentliche Pfade VOR dem geschützten Fallback-Block.

---

### Caddy: handle Pfad-Matching

**Problem:** `/relay` oder `/api`-Endpoints werden nicht korrekt gematchted.

**Erklärung:**
- `handle /path*` matcht `/path` UND `/path/foo`
- `handle /path/*` matcht NUR `/path/foo`, NICHT `/path` allein

**Lösung:** Für Endpoints die beides brauchen (z.B. Netbird `/relay`): immer `handle /path*` ohne Slash.

---

### PostgreSQL 18: Mount-Pfad

**Problem:** PostgreSQL-Container startet nicht oder verliert Daten.

**Ursache:** Falscher Mount-Pfad.

**Lösung:** Volume auf `/var/lib/postgresql` mounten, NICHT `/var/lib/postgresql/data`:

```yaml
volumes:
  - ./db:/var/lib/postgresql
```

---

### LXC: Kernel-Parameter nicht setzbar

**Problem:** `sysctl` schlägt fehl in LXC-Containern.

**Ursache:** LXCs teilen den Kernel mit dem Host. `kernel.*` und `fs.*` Parameter sind nicht erlaubt.

**Lösung:** `is_lxc: true` im Inventar setzen. Die Base-Rolle überspringt dann nicht-kompatible sysctl-Einstellungen und setzt nur Netzwerk-Parameter.

---

### LXC: TUN-Device für Netbird

**Problem:** Netbird kann in LXC kein TUN-Device erstellen.

**Ursache:** TUN-Device muss in der LXC-Konfiguration explizit erlaubt werden.

**Lösung:** Die `lxc_create`-Rolle konfiguriert TUN automatisch:
```
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

---

### Docker umgeht UFW

**Problem:** Docker-Ports sind trotz UFW-Deny von außen erreichbar.

**Ursache:** Docker manipuliert iptables direkt und umgeht UFW.

**Lösung:**
- Entry-Point-Server: Port-Binding auf `127.0.0.1:PORT`
- App-LXCs: `0.0.0.0:PORT` + UFW-Regel nur auf `wt0` (Netbird-Interface):
  ```bash
  ufw allow in on wt0 to any port 8080 proto tcp
  ```

---

### Netbird: DNS-Konflikte

**Problem:** Öffentliche Domains werden nicht aufgelöst.

**Ursache:** Netbird Custom DNS Zones für öffentliche Domains eingetragen.

**Lösung:** Custom DNS Zones NUR für interne Domains verwenden. Öffentliche Domains NICHT in Netbird-DNS eintragen.

---

### Watchtower: Infrastruktur-Container aktualisiert

**Problem:** Netbird, Caddy oder andere Infrastruktur-Container werden unerwartet aktualisiert → Ausfall.

**Ursache:** Watchtower aktualisiert alle Container mit dem Label `com.centurylinklabs.watchtower.enable=true`.

**Lösung:**
- **Kunden-Apps** (Nextcloud, Paperless, Vaultwarden, Uptime Kuma): Watchtower-Label setzen
- **Infrastruktur** (Caddy, Netbird, PocketID, Tinyauth, Semaphore, Grafana, Alloy, Baserow): KEIN Watchtower-Label. Updates nur über Ansible.

---

## App-spezifisch

### Nextcloud: HSTS-Warning im Admin-Panel

**Problem:** Nextcloud zeigt "Strict-Transport-Security Header is not set" Warnung.

**Lösung:** Apache im Container setzt den Header selbst via Volume-Mount `security.conf`. Die Nextcloud-Rolle mountet eine angepasste `security.conf` die den HSTS-Header setzt.

---

### Nextcloud: Single Logout funktioniert nicht

**Problem:** Logout in Nextcloud loggt nicht aus PocketID aus.

**Lösung:** In der user_oidc-Konfiguration:
```
--send-id-token-hint=0
```

Wird automatisch von der `oidc.yml`-Task der Nextcloud-Rolle gesetzt.

---

### Nextcloud: HEVC-Videos (GoPro .MOV/.MTS) spielen nicht ab in Files-App

**Problem:** HEVC/H.265-kodierte Videos (typisch: GoPro, moderne Smartphones) zeigen in der Nextcloud Files-App keinen Video-Player oder nur Audio ohne Bild. Betrifft bestimmte Client-Kombinationen.

**Ursache:** Nextcloud's Viewer-App (Core-App) nutzt Plyr (HTML5 `<video>`) und macht **kein Transcoding**. Die Rohdatei wird direkt an den Browser geschickt. Ob das Video abspielt, hängt ausschließlich vom HEVC-Codec-Support des Browsers/OS ab.

**Hinweis:** Die Memories-App (go-vod/HLS Transcoding) transkodiert HEVC on-the-fly zu H.264 und funktioniert. Aber Memories registriert sich nicht als Video-Handler in der Files-App — das sind getrennte Code-Pfade.

**Lösungen pro Client:**

| Client | Status | Lösung |
|--------|--------|--------|
| Linux + Chrome | Nicht lösbar | Chrome auf Linux hat keinen Software-HEVC-Decoder (Patentlizenzkosten). NVIDIA-GPUs (NVDEC) sind nicht kompatibel (Chrome nutzt VA-API). **Firefox 137+ verwenden** — dekodiert HEVC per Software über System-FFmpeg. |
| Windows + Chrome | Lösbar | "HEVC Video Extensions from Device Manufacturer" (kostenlos) oder "HEVC Video Extensions" (~0,99€) aus dem Microsoft Store installieren, Chrome neu starten. Chrome delegiert HEVC an Windows Media Foundation API. |
| macOS + Chrome/Safari | Funktioniert | VideoToolbox dekodiert nativ. |
| Android/iOS | Funktioniert | Native HEVC-Unterstützung. |

**Diagnose:** `chrome://gpu` prüfen — wenn kein "HEVC DECODE" Eintrag, fehlt der Decoder.

**Alternative Ansätze (nicht umgesetzt):**
- GoPro auf H.264-Aufnahme umstellen (limitiert manche 4K60-Modi)
- Batch-Konvertierung: `ffmpeg -i input.MOV -c:v libx264 -crf 18 -preset slower -c:a copy -map_metadata 0 -movflags +faststart output.mp4` (visuell verlustfrei, aber ~30-50% größere Dateien)
- Nextcloud Workflow Media Converter App (automatische Konvertierung bei Upload)

**Bekannter Memories-Bug:** [GitHub Issue #1587](https://github.com/pulsejet/memories/issues/1587) — Desktop-Browser: Video startet nicht beim ersten Play-Klick (Ladekreisel, kein Bild/Ton). Workaround: Pause → Play. Mobile Browser nicht betroffen.

**Datum:** 26. Februar 2026

---

### Paperless: Selbstregistrierung möglich

**Problem:** Benutzer können sich selbst bei Paperless registrieren.

**Lösung:** Explizit setzen in der `.env`:
```
PAPERLESS_ACCOUNT_ALLOW_SIGNUPS=false
```

Ist in der Paperless-Rolle als Default konfiguriert.

---

### Semaphore: Connection refused auf Port 3000

**Problem:** Health-Check `http://127.0.0.1:3000/api/ping` scheitert dauerhaft mit "Connection refused". Semaphore startet nicht.

**Ursache:** Falscher Environment-Variable-Name für die Datenbank. Semaphore erwartet `SEMAPHORE_DB` (ohne `_NAME`), nicht `SEMAPHORE_DB_NAME`. Ohne den korrekten Datenbanknamen kann Semaphore keine DB-Verbindung herstellen und crasht beim Start.

**Lösung:** In `roles/apps/semaphore/templates/env.j2`:
```
# Richtig:
SEMAPHORE_DB={{ semaphore_db_name }}

# Falsch:
SEMAPHORE_DB_NAME={{ semaphore_db_name }}
```

**Diagnose:** `docker logs semaphore` zeigt DB-Verbindungsfehler. Die korrekten Env-Vars laut [Semaphore-Doku](https://semaphoreui.com/docs/administration-guide/installation/docker):
- `SEMAPHORE_DB` (Datenbankname)
- `SEMAPHORE_DB_USER`
- `SEMAPHORE_DB_PASS`
- `SEMAPHORE_DB_HOST`
- `SEMAPHORE_DB_PORT`
- `SEMAPHORE_DB_DIALECT`

**Datum:** 26. Februar 2026

---

### PocketID: Registrierungsseite öffentlich

**Problem:** `/register`-Endpoint ist öffentlich erreichbar.

**Ursache:** PocketID kann Registrierung nicht nativ deaktivieren.

**Lösung:** Per Caddy auf 403 blocken. Die PocketID-Rolle konfiguriert den Caddy-Block entsprechend:
```
handle /register* {
    respond 403
}
```

---

### PocketID v2 API: 401 "You are not signed in"

**Problem:** OIDC-Client-Registrierung schlägt fehl mit 401, obwohl `STATIC_API_KEY` gesetzt ist.

**Ursache:** PocketID v2 erwartet den API-Key im `X-API-Key`-Header, nicht als `Authorization: Bearer`. Außerdem: Wenn `pocketid_api_token` als role-level `vars:` im Playbook gesetzt wird, überschreibt die Ansible-Precedence (21) den von `set_fact` generierten Token (Precedence 19).

**Lösung:**
1. Header: `X-API-Key: "{{ pocketid_api_token }}"` statt `Authorization: "Bearer ..."`
2. Token nur als play-level `vars:` setzen, nicht in role-level `vars:`

---

## Ansible-spezifisch

### Setup scheitert an vault-pass.sh (Erstes Setup)

**Problem:** `ansible-playbook` scheitert beim initialen Setup mit:
```
ERROR: Could not unlock Bitwarden vault. Is bw CLI configured?
```

**Ursache:** `ansible.cfg` referenziert `scripts/vault-pass.sh` als `vault_password_file`. Beim ersten Setup ist `bw` CLI noch nicht installiert/konfiguriert.

**Lösung:** Das Script hat drei Fallback-Mechanismen:
1. Umgebungsvariable `ANSIBLE_VAULT_PASSWORD` (höchste Priorität)
2. Lokale Passwort-Datei `/root/.loco-vault-pass`
3. `bw` CLI (Bitwarden/Vaultwarden)
4. Dummy-Passwort für Bootstrap (wenn nichts konfiguriert)

Falls der Fehler auftritt (altes Script-Version): Script aktualisieren mit `git pull`.

---

### Playbook-Fehler: "variable 'loco' is undefined"

**Problem:** Playbook bricht ab weil `loco`-Variable fehlt.

**Lösung:** Jedes Playbook braucht in `pre_tasks`:
```yaml
pre_tasks:
  - name: Load global config
    ansible.builtin.include_vars:
      file: "{{ playbook_dir }}/../config/lococloudd.yml"
      name: loco
```

Und die Datei `config/lococloudd.yml` muss existieren (kopiert von `.example`).

---

### Handler laufen nicht sofort

**Problem:** Ein Service wird erst am Ende des Plays neu gestartet, obwohl er sofort neu starten müsste.

**Ursache:** Ansible-Handler laufen standardmäßig am Ende des Plays.

**Lösung:** `meta: flush_handlers` einfügen, wenn ein Restart sofort nötig ist:
```yaml
- name: Force restart now
  ansible.builtin.meta: flush_handlers
```

---

### docker-compose V1 vs V2

**Problem:** `docker-compose` Command not found.

**Lösung:** V1 (`docker-compose`) ist deprecated. LocoCloud verwendet V2 (`docker compose`) als Plugin. Die Base-Rolle installiert `docker-compose-plugin`. Im Ansible-Code wird `community.docker.docker_compose_v2` verwendet.

---

### Health-Check hinter Tinyauth gibt 401

**Problem:** HTTP-Health-Check auf öffentliche URL gibt 401 (Unauthorized).

**Ursache:** Tinyauth blockiert den Request.

**Lösung:** Health-Checks auf Backend-Ports (localhost) statt auf die öffentliche URL:
```yaml
# Richtig:
url: "http://127.0.0.1:8080/health"

# Falsch:
url: "https://app.firma-abc.de/health"
```

---

### LXC Bootstrap: Chicken-and-Egg-Problem

**Problem:** Frische LXCs haben kein SSH und kein Netbird. Ansible kann sie nicht erreichen.

**Lösung:** Bootstrap via `pct exec` auf dem Proxmox-Host (delegiert):
1. LXC erstellen + starten
2. `pct exec` zum Injizieren von SSH-Key + Netbird-Installation
3. Netbird-IP aus `netbird status --json` auslesen
4. `hosts.yml` mit neuer Netbird-IP updaten

Die `lxc_create`-Rolle automatisiert diesen Prozess.

---

## Verschlüsselung (gocryptfs)

### gocryptfs: /mnt/data nicht gemountet nach Reboot

**Problem:** Nach einem Reboot ist `/mnt/data` nicht gemountet. Docker-Container starten ohne Daten.

**Ursache:** Der Systemd-Service `gocryptfs-mount.service` konnte den Keyfile nicht vom Master holen (Netzwerk nicht verfügbar, Master offline, SSH-Key ungültig).

**Lösung:**
1. Service-Status prüfen: `systemctl status gocryptfs-mount.service`
2. Master erreichbar? SSH testen: `ssh -i /root/.ssh/id_ed25519 root@<master-ip>`
3. Keyfile auf Master vorhanden? `ls /opt/lococloudd/keys/<hostname>.key`
4. Manuell mounten: `/opt/scripts/gocryptfs-mount.sh`
5. Danach Docker-Container neustarten: `docker restart $(docker ps -q)`

**Wichtig:** Der `gocryptfs-mount.service` muss VOR `docker.service` starten. Die Rolle konfiguriert dies automatisch.

---

### gocryptfs: Keyfile auf Server vergessen

**Problem:** Das Keyfile liegt noch auf dem Kundenserver (z.B. in `/tmp/`).

**Risiko:** Wer Zugriff auf den Server hat, kann die verschlüsselten Daten entschlüsseln.

**Lösung:** SOFORT löschen:
```bash
find /tmp -name "gocryptfs*.key" -delete
find /root -name "gocryptfs*.key" -delete
```

Keyfile darf NUR auf dem Master-Server (`/opt/lococloudd/keys/`) und optional auf dem Key-Backup-Server liegen.

---

## Credential Storage

### Vaultwarden API: 401 bei /api/ciphers

**Problem:** `credentials`-Rolle gibt 401 beim Speichern von Credentials.

**Ursache:** Vaultwarden's `/api/ciphers` erfordert ein User-JWT-Token (OAuth2 Login), nicht den Admin-Token. Zusätzlich müssen alle Daten client-seitig verschlüsselt werden (Bitwarden-Protokoll). Der Admin-Token funktioniert nur für `/admin/`-Endpoints.

**Lösung:** Das Script `scripts/vw-credentials.py` implementiert das vollständige Bitwarden-Verschlüsselungsprotokoll:

1. Erstellt automatisch einen Service-User (`loco-automation@localhost`) via Direkt-Registration
2. Loggt sich per OAuth2 ein und bekommt JWT-Token
3. Verschlüsselt alle Daten client-seitig (AES-256-CBC + HMAC)
4. Speichert/aktualisiert Vault-Items idempotent

Keine manuelle Interaktion nötig. Keine externen Dependencies (pure Python 3.8+).

### Vaultwarden Admin-Login: Cookie wird nicht gesetzt

**Problem:** `vw-credentials.py` loggt sich erfolgreich in das Admin-Panel ein, aber nachfolgende Admin-API-Requests (z.B. `GET /admin/users`) geben HTML statt JSON zurück.

**Ursache:** Python's `urllib.request.urlopen` folgt 302/303-Redirects automatisch. Der `Set-Cookie`-Header mit dem `VW_ADMIN`-Cookie steht auf der Redirect-Response (302), nicht auf der finalen Response (200). urllib verliert den Cookie beim Redirect-Follow.

**Lösung:** `vw-credentials.py` verwendet `http.client` statt `urllib` für den Admin-Login. `http.client` folgt keinen Redirects und gibt die rohe Response zurück — der Cookie wird korrekt ausgelesen.

---

### Vaultwarden Admin-API: /admin/users/overview gibt HTML, nicht JSON

**Problem:** `check_user_exists()` in `vw-credentials.py` erkennt existierende User nicht. `user_exists` ist immer `False`.

**Ursache:** `GET /admin/users/overview` gibt eine HTML-Seite zurück (Admin-Panel-UI), kein JSON. Der JSON-Parse schlägt fehl → Rückgabe ist `None` → User wird nie gefunden.

**Lösung:** `GET /admin/users` verwenden (gibt JSON-Liste zurück). **NICHT** `/admin/users/overview` (HTML).

```python
# Richtig:
users = self.admin_request("GET", "users")

# Falsch (gibt HTML zurück):
users = self.admin_request("GET", "users/overview")
```

**Datum:** 26. Februar 2026

---

### Vaultwarden: Admin-Invite blockiert Registration

**Problem:** Service-User-Registration schlägt fehl mit "Registration not allowed or user already exists", obwohl `SIGNUPS_ALLOWED=true` bestätigt im Container aktiv ist und `user_exists=False`.

**Ursache:** `POST /admin/invite` erstellt einen User-Record in der Datenbank (mit leerem Passwort-Hash). Der anschließende Registration-Endpoint prüft, ob der User existiert, findet den Invite-Record und gibt "user already exists" zurück. Der Invite-Schritt erzeugt genau den Konflikt, der die Registration blockiert.

**Diagnose:**
1. `SIGNUPS_ALLOWED=true` im Container bestätigt via `docker exec vaultwarden sh -c 'echo $SIGNUPS_ALLOWED'`
2. `user_exists=False` (Admin-API konnte User nicht finden — wegen `/users/overview` HTML-Bug)
3. `invite OK` (erstellt User-Record)
4. Registration: 400 "Registration not allowed or user already exists" auf allen Endpoints

**Lösung:** Direkt-Registration OHNE Invite. Bei `SIGNUPS_ALLOWED=true` (via Ansible-Toggle in `store.yml`) funktioniert direkte Registration. Falls ein Stale-User von einem früheren Invite existiert, wird er über die Admin-API gelöscht und die Registration wiederholt.

**Datum:** 26. Februar 2026

---

### Vaultwarden: 404 bei /api/accounts/register

**Problem:** Service-User-Registrierung schlägt mit 404 fehl.

**Ursache:** In Vaultwarden 1.33+ wurde der Registrierungs-Endpoint von `/api/accounts/register` nach `/identity/accounts/register` verschoben. Ab 1.34+ gibt es zusätzlich den neuen Flow über `send-verification-email` + `finish`.

**Lösung:** `vw-credentials.py` versucht automatisch alle drei Registrierungspfade:
1. `/identity/accounts/register` (Vaultwarden 1.27+, primär)
2. `/api/accounts/register` (Legacy-Pfad, ältere Versionen)
3. `send-verification-email` + `finish` (Vaultwarden 1.34+, neuer Flow)

---

### Vaultwarden: "Username or password is incorrect" bei Credential-Speicherung

**Problem:** `credentials`-Rolle schlägt bei `POST /identity/connect/token` fehl mit "Username or password is incorrect", obwohl der Service-User frisch angelegt wurde.

**Ursache:** Mehrstufiges Problem mit drei unabhängigen Faktoren:

1. **SIGNUPS_ALLOWED=false blockiert Registration:** `/identity/accounts/register` gibt "Registration not allowed or user already exists" zurück — auch für per Admin-Invite eingeladene User. Die Fehlermeldung ist bewusst mehrdeutig (Sicherheitsgründe). Das Script hat fälschlicherweise `"already exists"` im String gematcht und die Registration als erfolgreich behandelt, obwohl das Passwort nie gesetzt wurde.

2. **Falscher Registration-Endpoint für VW 1.34+:** Die älteren Endpoints (`/identity/accounts/register`, `/api/accounts/register`) sind in VW 1.34+ für eingeladene User mit `SIGNUPS_ALLOWED=false` nicht nutzbar. Der korrekte Pfad ist der Zwei-Schritt-Flow über `send-verification-email` + `register/finish`.

3. **Fehlender Prelogin-Schritt:** Das Script hat hardcodierte KDF-Parameter (PBKDF2, 600000 Iterationen) für die Passwort-Ableitung verwendet, statt den Server via `/api/accounts/prelogin` nach den tatsächlichen Parametern zu fragen. Bei Vaultwarden-Versionen die Argon2id als Default nutzen, stimmt der Hash nicht.

**Diagnose-Schritte die zum Fix führten:**
1. DEBUG-Ausgaben im Script zeigten: `user_exists=False` → `invite OK` → Registration "not allowed" → fälschlicherweise als OK behandelt → Login scheitert
2. Prelogin-Response: `kdf=0, iterations=600000` → KDF-Parameter korrekt, also nicht die Ursache
3. Kern-Problem: Registration hat nie stattgefunden, User hatte kein Passwort

**Lösung:** Drei Fixes:

1. **Ansible `store.yml` toggelt `SIGNUPS_ALLOWED` via `.env`-Datei:** Die Admin-Config-API (`/admin/config`) existiert nicht in aktueller VW-Version. Stattdessen erkennt `store.yml` den Fehler "Registration not allowed" im stderr, setzt `SIGNUPS_ALLOWED=true` via `lineinfile`, macht `docker compose down` + `docker compose up -d` (NICHT `docker restart` — restart liest env_file nicht neu ein!), retried das Script, und stellt `SIGNUPS_ALLOWED=false` im `always`-Block wieder her. Zwei Container-Recreates nur beim allerersten Run.

2. **False-Positive "already exists" entfernt:** `_try_register()` hat "Registration not allowed **or** user already exists" faelschlicherweise als "User existiert" gewertet. Die Fehlermeldung ist absichtlich mehrdeutig — in 99% der Faelle ist "Registration not allowed" die Ursache. Das Script wirft jetzt korrekt einen Fehler statt stillschweigend weiterzumachen.

3. **Prelogin vor Login:** `login()` fragt `/api/accounts/prelogin` ab fuer korrekte KDF-Parameter.

**Sicherheit:** Vaultwarden ist auf dem Master nur via `127.0.0.1` erreichbar. Caddy blockt `/register` zusaetzlich. Das kurze Fenster mit `SIGNUPS_ALLOWED=true` waehrend der Service-User-Erstellung ist nicht extern erreichbar.

**Datum:** 26. Februar 2026

---

## Bootstrap

### Caddy-Handler schlägt fehl beim initialen Setup

**Problem:** `setup-master.yml` bricht bei `RUNNING HANDLER [restart caddy]` ab mit `No such container: caddy`.

**Ursache:** Die Vaultwarden-Rolle feuert `notify: restart caddy` (z.B. nach SSO-Config-Update), aber die Caddy-Rolle kommt erst später im Playbook dran. Der Handler läuft am Ende des Plays, wenn der Caddy-Container noch nicht existiert.

**Lösung:** Die Handler in `roles/caddy/handlers/main.yml` und `roles/apps/vaultwarden/handlers/main.yml` tolerieren jetzt einen fehlenden Container:
```yaml
- name: restart caddy
  ansible.builtin.command: docker restart caddy
  register: caddy_restart_result
  failed_when:
    - caddy_restart_result.rc != 0
    - "'No such container' not in caddy_restart_result.stderr"
  changed_when: caddy_restart_result.rc == 0
```

---

## Backup

### Restic: Repository nicht initialisiert

**Problem:** Backup schlägt fehl mit "repository not initialized".

**Lösung:** Die `backup`-Rolle initialisiert das Repository automatisch. Falls manuell nötig:
```bash
restic -r sftp:user@host:/path init --password-file /opt/scripts/backup/.restic-password
```

---

### Restic: Verbindung über Netbird fehlgeschlagen

**Problem:** SFTP-Verbindung zum Backup-Ziel klappt nicht.

**Lösung:**
1. Netbird-Verbindung prüfen: `netbird status`
2. SSH-Key-Auth zum Backup-Ziel testen
3. Policy in Netbird prüfen (backup→kunde muss erlaubt sein)

---

## Key Learnings

Gesammelte Erkenntnisse aus Debugging und Betrieb:

- **HTTP/2 vs HTTP/1.1 bei VPN-Tunnel-Backends:** HTTP/2 Binary Framing verträgt sich nicht mit der reduzierten MTU (~1420) von WireGuard-Tunneln. Die TLS-in-WireGuard-Encapsulation führt zu Frame-Fragmentierung und Stream-State-Desynchronisation — Caddy liefert leere 200-Responses ohne Body. **Regel:** Bei `reverse_proxy https://` über Netbird VPN immer `versions 1.1` im `transport http` Block erzwingen.
- **Caddy TLS-SNI bei Netbird-IPs:** `reverse_proxy https://100.x.x.x` sendet die IP als SNI. Backend-Caddy hat kein Zertifikat für IPs → 502 oder TLS Alert. Immer `tls_server_name` und `header_up Host` explizit setzen.
- **Tinyauth als Performance-Bottleneck:** Jeder Sub-Request (JS, CSS, Bilder) geht durch einen Tinyauth-Roundtrip über Netbird. Bei 184 Requests × 150ms = über 1 Minute Ladezeit. Apps mit eigener Auth (Nextcloud OIDC) brauchen kein `import auth` im Caddy-Block.
- **Watchtower und Infrastruktur:** Watchtower darf NIE Infrastruktur-Container aktualisieren. Ein automatisches Netbird-Update hat den Relay-Endpoint geändert und das gesamte VPN lahmgelegt.
- **Vaultwarden Admin-Invite blockiert Registration:** `POST /admin/invite` erstellt einen User-Record in der DB. Anschließende Registration schlägt fehl mit "user already exists". Lösung: Direkt-Registration OHNE Invite bei `SIGNUPS_ALLOWED=true` (via Ansible Toggle).
- **Vaultwarden Admin-API gibt HTML:** `GET /admin/users/overview` gibt HTML zurück, NICHT JSON. Für JSON-User-Liste: `GET /admin/users` verwenden.
- **Vaultwarden SIGNUPS_ALLOWED:** `SIGNUPS_ALLOWED=false` blockiert Registration. Loesung: Ansible `store.yml` toggelt `.env` + `docker compose down/up` (NICHT restart — restart liest env_file nicht neu ein).
- **Caddy Inode-Problem:** Nach Template-Writes immer `docker restart caddy`, nie `caddy reload`. Docker Bind-Mounts referenzieren den Inode, nicht den Dateinamen.
- **HEVC-Video in Nextcloud Files-App:** Nextcloud Viewer macht kein Transcoding — Codec-Support hängt 100% vom Browser/OS ab. Linux+Chrome hat keinen HEVC-Decoder (Firefox 137+ nutzen). Windows+Chrome braucht HEVC Video Extensions aus dem Microsoft Store. Memories-App transkodiert zwar HEVC→H.264, registriert sich aber nicht als Video-Handler in der Files-App.
