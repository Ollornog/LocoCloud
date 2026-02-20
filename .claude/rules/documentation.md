# Dokumentations-Pflichten

## Wann wird was dokumentiert

| Ereignis | Zu aktualisierende Datei(en) |
|----------|------------------------------|
| Neue Ansible-Rolle erstellt | `docs/APP-DEVELOPMENT.md`, Rolle `defaults/main.yml` mit Kommentaren |
| Architektur-Änderung | `docs/KONZEPT.md`, `CLAUDE.md` |
| Neues bekanntes Problem | `docs/TROUBLESHOOTING.md`, `.claude/rules/known-issues.md` |
| Offene Entscheidung getroffen | `docs/KONZEPT.md` Kapitel 21 aktualisieren, als gelöst markieren |
| Neue Konfigurationsoption | `config/lococloudd.yml.example` aktualisieren |
| Playbook hinzugefügt/geändert | `docs/SETUP.md` oder `docs/ONBOARDING.md` je nach Kontext |
| Security-Änderung | `docs/KONZEPT.md` Kapitel 16, `.claude/rules/known-issues.md` |

## Format-Regeln

- **Deutsch** für alle Projektdokumentation (Konzept, Troubleshooting, Onboarding)
- **Englisch** für `README.md` und Code-Kommentare (Repo soll public-fähig sein)
- **Inline-Kommentare in YAML:** Kurz, erklären das WARUM, nicht das WAS
- **Keine TODO-Kommentare** im Code. Offene Punkte → `docs/KONZEPT.md` Kapitel 21 oder GitHub Issue

## CLAUDE.md pflegen

Wann die `CLAUDE.md` aktualisiert werden MUSS:

1. **Neue Rolle erstellt** → Repo-Struktur-Baum aktualisieren
2. **Architektur-Entscheidung getroffen** → Architektur-Essenz aktualisieren
3. **Offene Entscheidung gelöst** → Aus Konzept entfernen, als feste Regel aufnehmen
4. **Neue Datei/Ordner die Claude kennen muss** → Repo-Struktur aktualisieren

Format: Maximal ~120 Zeilen. Keine Redundanz mit `.claude/rules/` oder `docs/KONZEPT.md`.
