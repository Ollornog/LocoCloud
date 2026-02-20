# Aufräum-Regeln

## Nach jedem Task

- [ ] Temporäre Testdateien gelöscht (keine `test.yml`, `debug.yml`, `tmp_*`)
- [ ] Debug-Tasks entfernt (`debug: msg=...` die nur zum Testen waren)
- [ ] Auskommentierter Code entfernt
- [ ] Keine leeren Dateien oder Platzhalter-Verzeichnisse ohne Inhalt
- [ ] Keine doppelten/widersprüchlichen Konfigurationen

## Nach Fehlerbehebung

- [ ] Workaround dokumentiert in `docs/TROUBLESHOOTING.md`
- [ ] Falls Architektur-relevant: `docs/KONZEPT.md` aktualisiert
- [ ] Falls neuer Fallstrick: `.claude/rules/known-issues.md` aktualisiert
- [ ] Temporäre Fix-Versuche entfernt (keine `_backup`, `_old`, `_fix` Dateien)
- [ ] Git-History sauber: Aussagekräftige Commit-Messages, kein "test", "fix", "wip"

## Nach Konzeptänderung

- [ ] `docs/KONZEPT.md` ist die ERSTE Datei die geändert wird
- [ ] Alle betroffenen Rollen/Playbooks/Templates angepasst
- [ ] `config/lococloudd.yml.example` aktualisiert falls neue Config-Optionen
- [ ] `CLAUDE.md` aktualisiert (Architektur-Essenz, Repo-Struktur)
- [ ] Inventar-Templates (`inventories/_template/`) aktualisiert
- [ ] Keine verwaisten Referenzen auf alte Konzepte/Variablen/Dateien

## Verbotene Zustände

- **Keine Dateien mit `_old`, `_backup`, `_test`, `_tmp`, `_copy` Suffix** im Repo
- **Keine `*.bak` Dateien**
- **Keine leeren Platzhalter** die keinen Zweck erfüllen
- **Kein auskommentierter Code** der "für später" aufgehoben wird
- **Keine hardcodierten Werte** die in Config/Inventar gehören
- **Kein `ansible_host: 10.10.0.x`** (alte Proxmox-Bridge-IPs) — alles ist Netbird
