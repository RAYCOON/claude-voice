# Slash-Commands versionieren und mitausrollen

**Datum:** 2026-08-11
**Status:** freigegeben

## Problem

`sprich.md` und `read-msg.md` liegen ausschließlich in `~/.claude/commands/` und
sind nirgends versioniert. `install.sh` fasst das Verzeichnis nicht an. Daraus
folgen drei Defekte:

1. **Fixes erreichen niemanden.** Der Heartbeat, der den Stumm-Marker am Leben
   hält (Commit `aaa6dd8`), lebt nur auf einer Maschine. Eine Neuinstallation
   bringt ein `sprich.md` ohne Auffrischung mit — der Hook verstummt dann nach
   `MUTE_TTL_MIN` mitten im Sprachmodus.
2. **Zwei Hälften, ein Vertrag.** `speak.sh` und `sprich.md` müssen sich über
   das Marker-Protokoll einig sein. Getrennt versioniert können sie
   auseinanderlaufen, ohne dass es jemand bemerkt.
3. **Harte Pfade.** `read-msg.md` verweist auf
   `/Users/geraldmuller/GitRepos/claude-voice/replay.sh` und funktioniert nur
   unter genau diesem Pfad.

## Lösung

### Repo-Struktur

```
commands/
  sprich.md      entpersonalisiert, mit Heartbeat
  read-msg.md    mit Platzhalter statt hartem Pfad
commands.sh      sourcebare Installationslogik
```

Der Platzhalter `{{CLAUDE_VOICE_DIR}}` wird bei der Installation durch das
Repo-Verzeichnis ersetzt — dasselbe Prinzip, nach dem `install.sh` heute schon
den Hook-Befehl mit `$SCRIPT_DIR` einträgt.

### Installationsziel

Die Commands folgen der Installationsart, die `install.sh` ohnehin abfragt:

| Modus  | Ziel                     |
|--------|--------------------------|
| global | `~/.claude/commands/`    |
| lokal  | `$PWD/.claude/commands/` |

Andernfalls entstünde bei einer Projektinstallation ein lokaler Hook neben
global sichtbaren Commands.

### `commands.sh`

Sourcebare Bibliothek nach dem Muster von `tts.sh`:

```
commands_install <quell-dir> <ziel-dir> <repo-dir>
commands_uninstall <quell-dir> <ziel-dir>
```

`commands_install` behandelt pro Datei vier Fälle:

| Zustand am Ziel      | Verhalten                                              |
|----------------------|--------------------------------------------------------|
| fehlt                | anlegen                                                 |
| identisch zur Vorlage| „bereits aktuell", nichts tun                           |
| weicht ab            | Diff zeigen, `[j/N]` fragen; bei Ja `.bak` + überschreiben |
| Antwort Nein         | unverändert lassen, mit der nächsten Datei weitermachen |

Die Auslagerung dient der Testbarkeit: `install.sh` ist durch `read -rp`
interaktiv und als Ganzes nicht automatisiert prüfbar. Als Funktion lässt sich
die Logik gegen ein temporäres Zielverzeichnis fahren.

Antworten liest die Funktion von `stdin`. Ist `COMMANDS_ASSUME` auf `j` oder `n`
gesetzt, überspringt sie die Rückfrage und nimmt diesen Wert — das macht die
vier Fälle ohne Terminal testbar.

### Entpersonalisierung

„Gerald" wird zu „der Nutzer", der Formulierung aus `sprich.md:2`. Die
Kalibrierungswerte (`vad_aggressiveness: 0`, `listen_duration_min`, das
„Roger"-Protokoll) bleiben als Defaults erhalten; nur ihre Begründung wird
sachlich statt persönlich.

Die bestehende Datei in `~/.claude/commands/` wird beim Umbau nicht angefasst.
Die Angleichung passiert beim nächsten `install.sh`-Lauf über den Diff-Dialog.

### Deinstallation

`uninstall.sh` entfernt die Commands auf Nachfrage — analog zu seiner heutigen
Behandlung der Fallback-Modelle, nicht ungefragt.

## Tests

`tests/test-commands.sh` sourced `commands.sh` und prüft gegen ein temporäres
Zielverzeichnis:

1. Zielverzeichnis leer → Datei wird angelegt, Platzhalter ist ersetzt
2. Ziel identisch → keine Änderung, kein `.bak`
3. Ziel weicht ab, Antwort `j` → überschrieben, `.bak` enthält die alte Fassung
4. Ziel weicht ab, Antwort `n` → unverändert, kein `.bak`
5. Kein `{{CLAUDE_VOICE_DIR}}` bleibt in einer installierten Datei zurück

## Nicht enthalten

- Kein Template-System über die eine Pfad-Ersetzung hinaus
- Keine Kalibrierung über `config.json`: Die Commands sind Markdown für Claude,
  eine Konfigurationsschicht brächte dort Komplexität ohne Nutzen
- Kein automatisches Update bestehender Installationen; der Diff-Dialog bleibt
  die Stelle, an der jemand bewusst entscheidet
