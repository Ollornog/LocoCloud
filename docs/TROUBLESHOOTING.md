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

### Paperless: Selbstregistrierung möglich

**Problem:** Benutzer können sich selbst bei Paperless registrieren.

**Lösung:** Explizit setzen in der `.env`:
```
PAPERLESS_ACCOUNT_ALLOW_SIGNUPS=false
```

Ist in der Paperless-Rolle als Default konfiguriert.

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
