# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Was das ist

Reine Bash-Toolbox (macOS, `jq`, `curl`, `afplay`), die Claude Code nach jeder Antwort den letzten Absatz mit der deutschen Thorsten-Stimme vorlesen lässt. Kein Build, kein Paketmanager, keine Abhängigkeiten außer den Shell-Tools. Sprache im Repo ist durchgehend Deutsch: Kommentare, Log-Zeilen, Test-Ausgaben, Commit-Messages, README.

## Befehle

```bash
# Alle Tests (jeder Test ist eigenständig, Exit ≠ 0 bei Fehlschlag)
for t in tests/*.sh; do "$t" || echo "FAIL: $t"; done

# Einzelner Test
./tests/test-pronunciation.sh     # Regeln bauen/anwenden (tts.sh)
./tests/test-clean-markdown.sh    # Markdown → Sprechtext (tts.sh)
./tests/test-strip-sections.sh    # Fussbereich abschneiden (tts.sh, speak.sh)
./tests/test-mute-marker.sh       # Verfall des Stumm-Markers (speak.sh)
./tests/test-commands.sh          # Ausrollen der Slash-Commands (commands.sh)
./tests/test-pronounce.sh         # Vorsprechen der Kandidaten (pronounce.sh)

# Hook von Hand füttern (so ruft Claude Code ihn auf)
echo '{"session_id":"t","cwd":"'"$PWD"'","last_assistant_message":"Hallo Welt"}' | ./speak.sh

# Einzelbausteine
./replay.sh "$PWD"                        # letzte Antwort der Session dieses Projekts wiederholen
./speakable.sh "Text mit Slice"           # nur Aussprache-Regeln anwenden (kein Markdown-Cleanup)
./pronounce.sh "Sleis" "Slaiß" "Sleiß"    # Kandidaten vorsprechen (ohne Regeln)
./install.sh / ./uninstall.sh             # interaktiv; trägt Stop-Hook + Commands ein/aus
```

Die Skripte tragen `# shellcheck source=`-Direktiven; `shellcheck *.sh tests/*.sh` ist der passende Linter, falls installiert (`brew install shellcheck`). Laufzeit-Diagnose steht in `speak.log` (gitignored, auf 100 Zeilen gekappt).

## Architektur

### Zwei Sprachrohre, eine Regelbasis

1. **Vorlese-Hook** (`speak.sh`, als Claude-Code-`Stop`-Hook registriert): liest das Hook-JSON von stdin, extrahiert `last_assistant_message`, nimmt den letzten Absatz (oder alles bei `paragraph: "all"`), bereinigt Markdown, wendet Aussprache-Regeln an, synthetisiert, spielt ab.
2. **Sprachmodus** (`/sprich` über voicemode): Claude spricht selbst per `mcp__voicemode__converse`. Der Sprechtext läuft vorher durch `speakable.sh`, damit dieselben Aussprache-Regeln gelten.

Beide sourcen `tts.sh` — die einzige Stelle mit Config-Laden, Markdown-Bereinigung, Regel-Engine, Synthese und Wiedergabe. `tts.sh` wird **nur gesourct, nie ausgeführt**; gleiches gilt für `commands.sh`.

### Marker-Protokoll in `/tmp` (Session-Isolation)

Alles Zustandsbehaftete liegt in `/tmp`, damit parallele Sessions sich nicht ins Wort fallen:

| Datei | Wer schreibt | Zweck |
|---|---|---|
| `claude-voice-cwd-<md5(cwd)>` | `speak.sh` | Mapping Projektpfad → Session-ID; `replay.sh` löst darüber die Session auf, weil `/read-msg` nur das cwd kennt |
| `claude-voice-<session>-lastmsg.txt` | `speak.sh` | Volltext der letzten Antwort für `/read-msg` |
| `claude-voice-<session>-skip` | `replay.sh` | Einmal-Marker: der Hook überspringt die nächste Antwort (sonst liest er die Bestätigung von `/read-msg` vor) |
| `claude-voice-mute-<md5(cwd)>` | `/sprich` | Stumm-Marker mit **Heartbeat**: `/sprich` frischt ihn vor jedem `converse` auf; `speak.sh` ignoriert ihn, wenn er älter als `MUTE_TTL_MIN` (10 min) ist, und räumt ihn weg |
| `claude-voice-<session>.wav/.pid` | `tts.sh` | Session-eigene Audiodatei und PID der laufenden Wiedergabe; `pronounce.sh` nutzt eigene Pfade, um den Hook nicht abzuwürgen |

**Vertrag zwischen `speak.sh` und `commands/sprich.md`:** Das Marker-Protokoll (Pfad-Schema, Heartbeat, TTL) steht auf beiden Seiten. Wer eine Seite ändert, muss die andere mitziehen — genau deshalb liegen die Commands im Repo und nicht nur im Profil.

### Slash-Commands mit Platzhalter

`commands/*.md` enthalten `{{CLAUDE_VOICE_DIR}}`; `commands_install` (in `commands.sh`) ersetzt ihn beim Ausrollen durch den Repo-Pfad und kopiert nach `~/.claude/commands/` (global) bzw. `.claude/commands/` (lokal) — passend zur Hook-Wahl in `install.sh`. Weicht eine installierte Fassung ab: Diff zeigen, nachfragen, bei Ja `.bak` anlegen. `COMMANDS_ASSUME=j|n` beantwortet die Frage nicht-interaktiv (Tests). **Nach einer Änderung in `commands/` muss `./install.sh` erneut laufen**, sonst bleibt das Profil auf dem alten Stand.

### Aussprache-Lexikon (`pronunciation.txt`)

- Format `Begriff = Lautschrift`, `#`-Kommentare. `tts_pronunciation_script` baut daraus ein sed-Skript, **sortiert nach Begriffslänge absteigend** — Reihenfolge in der Datei ist bedeutungslos, `Slices` gewinnt vor `Slice`.
- Regeln sind case-sensitiv; Groß-/Kleinschreibung und gebeugte Formen brauchen eigene Zeilen.
- Regeln wirken **nacheinander und kaskadieren**: Steckt ein Begriff in der Ersetzung einer anderen Regel, greift er dort erneut. Deshalb wird `FINAL_TEXT` in `speak.sh` nie ein zweites Mal durch die Regeln geschickt — nur `CLEAN_TEXT` und `PROJECT_NAME` je einmal getrennt.
- `tts_apply_pronunciation` gibt **immer Exit 0** und im Zweifel den Originaltext zurück: das Lexikon darf die Stimme nie kosten. `speakable.sh` ebenfalls immer Exit 0, weil es in der `&&`-Kette des `/sprich`-Heartbeats hängt.
- `pronounce.sh` schickt Kandidaten **roh** in die Synthese — sonst überschriebe eine bestehende Regel genau das, was man hören will.
- `_tts_escape_search`/`_tts_escape_replace` maskieren sed-Sonderzeichen (`& / . * [ ]`); neue Regeln mit Sonderzeichen sind dort abgedeckt, nicht in der Regeldatei.
- `/aussprache` und `/sprich` hängen neue Regeln an, **committen aber bewusst nicht** — der Fund passiert meist mitten in Arbeit an einem anderen Projekt. Ein offener Commit in diesem Repo ist normal.

### Synthese und Wiedergabe

- Primär OpenAI-kompatibler Endpoint (`tts_url`, Standard voicemode-Thorsten auf `:8881`), Fallback lokales `piper` mit Modell aus `models/` (gitignored).
- `config.speed` folgt Pipers `length-scale` (**kleiner = schneller**); für die OpenAI-API wird der Kehrwert gebildet. Nicht „korrigieren".
- `tts_play` startet `afplay` detached über `osascript`, damit die Wiedergabe das Hook-Ende überlebt, und killt nur die eigene PID — nie alle `afplay`.
- `tts_clean_markdown` hängt Listen-Items ohne Satzzeichen einen Punkt an: ohne Satzgrenze liest Piper Aufzählungen als atemlosen Fließtext (gemessen ~24 statt ~18 Zeichen/s).

### Fussbereich abschneiden (`tts_strip_trailing_sections`, `skip_sections`)

Antworten enden oft mit einem Block wie „Nächste sinnvolle Schritte" voller Vorschlagsprompts für den nächsten Turn — ohne Schnitt wäre genau dieser Block der „letzte Absatz", den `speak.sh` vorliest, statt der eigentlichen Antwort. `tts_strip_trailing_sections` (in `tts.sh`) sucht die **letzte** Zeile, die nach Abzug von Markdown-Dekoration (`#`, `**`, führende Sonderzeichen/Emoji) einem der `skip_sections`-Muster (ERE, groß-/kleinschreibungsgenau) entspricht, und schneidet ab dort bis zum Ende weg. Die letzte statt der ersten Übereinstimmung gewinnt, damit ein „Nächste Schritte" mitten in einer Anleitung nicht die zweite Hälfte der Antwort verschluckt; verglichen wird erst nach der Dekoration, damit ein Fließtextsatz wie „Für Nächste Schritte siehe unten." nicht fälschlich triggert. `speak.sh` wendet den Schnitt vor der Absatzauswahl an; bleibt danach nichts Nicht-Leeres übrig (die Antwort war nur der Fussbereich), liest der Hook lieber ungekürzt vor, statt der Stimme den Mund zu verbieten — gleiches Prinzip wie beim Aussprache-Lexikon. `replay.sh` bleibt bewusst unangetastet: `/read-msg` liest immer die volle, ungekürzte Antwort.

### Konfiguration

`config.defaults.json` ist die dokumentierte Vorlage (Keys mit `_`-Präfix sind Kommentare und werden beim Erzeugen von `config.json` gefiltert). `config.json` ist gitignored und die einzige Datei, die der Nutzer anfasst. Beim Hook-Aufruf ist das cwd ein **fremdes Projekt** — Pfade daher immer über `SCRIPT_DIR`/`TTS_DIR` auflösen, nie relativ. `PRONUNCIATION_FILE` kann von außen gesetzt werden (Tests).

## Tests schreiben

- Muster: `set -u`, `check <name> <erwartet> <ist>`, `fails`-Zähler, `mktemp -d` mit `trap … EXIT`, Exit 1 bei Fehlern. Kein Framework.
- Tests, die Skripte mit Synthese aufrufen (`test-mute-marker.sh`, `test-pronounce.sh`, `test-strip-sections.sh`), schieben **curl- und piper-Stubs in den `PATH`** und setzen `TTS_MODEL_PATH` ins Leere — sonst spielt ein installiertes Piper hörbar Audio ab. Sie hängen bewusst ans echte `speak.log` an und prüfen die Log-Zeilen.
- Eigenes Test-cwd (`/tmp/claude-voice-testprojekt`) verwenden, damit Marker echter Projekte unberührt bleiben.

## Konventionen

- Commit-Messages deutsch, mit Bereichspräfix: `vorlesen:`, `lexikon:`, `fix:`, `chore:`.
- Kommentare erklären das **Warum** (welcher Fehler ohne diese Zeile aufträte), nicht das Was — bestehende Kommentare beim Ändern mitpflegen.
- Specs und Pläne liegen unter `.claude/.tmp/specs/` bzw. `.claude/.tmp/plans/`.
