# Aussprache-Lexikon für beide Sprachrohre

**Datum:** 2026-08-11
**Status:** freigegeben

## Problem

Das Thorsten-Modell ist auf Deutsch trainiert und verunstaltet englische Begriffe.
`tts.sh` begegnet dem mit hartcodierten `sed`-Zeilen am Ende von
`tts_clean_markdown` — bis heute `Claude` → `Klod` und `Keycloak` → `Kii klooug`,
inzwischen um `Slice`/`Slices` ergänzt. Genau diese Ergänzung legt die drei
Defekte offen:

1. **Der Sprachmodus profitiert nicht.** Die Regeln stecken in einer Funktion,
   die nur `speak.sh` und `replay.sh` aufrufen. Im Sprachmodus geht der Text
   direkt von der Antwort an `converse` — dort spricht die Stimme „Claude" so
   aus, wie es dasteht. Die Klod-Regel existiert seit Langem und war im
   Sprachmodus trotzdem nie wirksam.
2. **Neue Regeln kosten einen Code-Change.** Ein verunstalteter Begriff ist
   eine Beobachtung im Gespräch, keine Programmieraufgabe. Heute muss dafür
   eine Shell-Funktion editiert werden.
3. **Die Reihenfolge ist eine Falle.** `sed 's/Slice/Slaiß/g'` macht aus
   „Slices" ein „Slaißs". Wer eine Regel anhängt, muss wissen, dass längere
   Begriffe vor kürzeren stehen müssen — nichts im Code sagt das.

## Lösung

### Regelquelle

`pronunciation.txt` im Repo-Root, getrackt:

```
# claude-voice — Aussprache
# Begriff = Lautschrift

Claude   = Klod
Keycloak = Kii klooug
Slices   = Slaißis
Slice    = Slaiß
```

Versioniert, nicht in `config.json`: die Regeln gehören zum Thorsten-Modell,
nicht zur Maschine. Die Historie zeigt, welche Lautschrift wann gewonnen hat,
und eine Neuinstallation bringt sie mit.

**Die Reihenfolge in der Datei ist bedeutungslos.** Beim Laden werden die
Regeln nach Begriffslänge absteigend sortiert, damit `Slices` immer vor `Slice`
greift. Neue Regeln dürfen deshalb stumpf angehängt werden, und die Datei darf
nach Belieben umsortiert werden. Wörter, die sich in der Beugung anders
anhören, brauchen weiterhin eine eigene Zeile.

### Zwei Funktionen statt einer

`tts.sh` verliert seine Wortliste und bekommt eine zweite Funktion:

| Funktion | Aufgabe |
|---|---|
| `tts_clean_markdown` | entfernt nur noch Markdown — wie der Name verspricht |
| `tts_apply_pronunciation` | liest `pronunciation.txt`, wendet die Regeln auf stdin an |

`tts_apply_pronunciation` baut **einen** `sed`-Aufruf mit mehreren
`-e`-Ausdrücken, keine Pipe aus N Aufrufen. Die Regeldatei wird über
`$SCRIPT_DIR` gefunden, dem Muster von `CONFIG` und `LOG` folgend — nie über
das aktuelle Arbeitsverzeichnis, das beim Hook-Aufruf ein fremdes Projekt ist.

`speak.sh` und `replay.sh` rufen beide Funktionen nacheinander auf.

### Datenfluss

```
Vorlese-Hook (speak.sh, replay.sh)
  Antwort → Absatz → tts_clean_markdown → tts_apply_pronunciation
          → tts_synthesize → tts_play

Sprachmodus (/sprich)
  Sprechtext → speakable.sh → converse(message=…)
```

`speakable.sh` ruft **nur** `tts_apply_pronunciation` auf. Der Sprechtext des
Sprachmodus ist bereits Klartext; es gibt dort kein Markdown zu entfernen.
Beide Wege teilen sich damit exakt dieselbe Regelanwendung, ohne dass eine
Seite den Ballast der anderen mitschleppt.

### Neue Skripte

**`speakable.sh`** — nimmt Text als Argument oder über stdin, gibt ihn mit
angewandten Regeln auf stdout aus. Mehr nicht. Im Sprachmodus hängt er sich an
den Heartbeat, den `/sprich` ohnehin vor jedem Zug macht:

```bash
touch "/tmp/claude-voice-mute-$(echo -n "$PWD" | md5 -q)" \
  && {{CLAUDE_VOICE_DIR}}/speakable.sh "Claude schneidet ein Slice."
# → Klod schneidet ein Slaiß.
```

Die Ausgabe wandert als `message` in `converse`. Kein zusätzlicher
Round-Trip gegenüber heute.

**`pronounce.sh`** — spricht Kandidaten zum Vergleich vor:

```bash
pronounce.sh "Sleis" "Slaiß" "Sleiß"
# spricht: „Erstens: Sleis. Zweitens: Slaiß. Drittens: Sleiß."
```

Ein einziger Synthese-Durchgang, damit es eine zusammenhängende Aufnahme wird.
Die Kandidaten gehen **roh** in die Synthese, ohne Regelanwendung — sonst
überschriebe eine bestehende Regel den Testkandidaten und man hörte nie, was
man eingibt. Eigene Datei-Pfade (`/tmp/claude-voice-pronounce.wav|.pid`), damit
laufende Wiedergaben des Hooks unberührt bleiben.

Gebraucht wird das Skript nur außerhalb des Sprachmodus. Innerhalb spricht der
Agent die Kandidaten über `converse`.

### `commands/aussprache.md`

| Aufruf | Verhalten |
|---|---|
| `/aussprache` | listet die aktuellen Regeln auf |
| `/aussprache Slice` | drei Schreibweisen vorschlagen, per `pronounce.sh` vorsprechen, auswählen lassen, eintragen |
| `/aussprache Slice = Slaiß` | trägt direkt ein, ohne Hörprobe |

Existiert der Begriff bereits, wird die bestehende Lautschrift gezeigt und vor
dem Ersetzen nachgefragt. Neue Regeln werden angehängt; die Längensortierung
macht die Position unerheblich.

Nach dem Eintrag wird **nicht** committet, sondern nur Bescheid gegeben. Ein
Aussprache-Fund passiert mitten in anderer Arbeit; ein Auto-Commit landete
sonst ungefragt auf einem fremden Feature-Branch.

Der Command nutzt den Platzhalter `{{CLAUDE_VOICE_DIR}}` für Skript- und
Dateipfade. `install.sh` braucht keine Änderung: `commands_install` rollt jede
`*.md` aus `commands/` aus.

### `commands/sprich.md`

Zwei Ergänzungen:

1. **Heartbeat erweitern.** Der `touch`-Befehl vor jedem `converse`-Aufruf
   bekommt den `speakable.sh`-Aufruf angehängt; dessen Ausgabe wird als
   `message` übergeben.
2. **Korrektur erkennen.** Weist der Nutzer im Gespräch auf eine falsche
   Aussprache hin („das heißt nicht X, das heißt Y"), bietet der Agent von
   selbst denselben Ablauf an: Kandidaten über `converse` vorsprechen, wählen
   lassen, in `pronunciation.txt` eintragen, Bescheid geben, nicht committen.

## Fehlerbehandlung

**Leitsatz: das Lexikon darf die Stimme nie kosten.** Jeder Fehlerfall reicht
den Text unverändert durch und protokolliert eine Zeile in `speak.log`, statt
abzubrechen.

| Fall | Verhalten |
|---|---|
| `pronunciation.txt` fehlt oder ist leer | Text unverändert, Logzeile, Exit 0 |
| Zeile ohne `=` | Zeile überspringen, Logzeile, übrige Regeln greifen |
| `#`-Kommentar, Leerzeile | still ignorieren |
| `speakable.sh` ohne Eingabe | leere Ausgabe, Exit 0 |
| TTS-Server tot | unverändert der bestehende Piper-Fallback |
| `pronounce.sh` ohne Kandidaten | Hinweis, Exit 1 |

Der Exit-Code von `speakable.sh` ist kein Detail: der Heartbeat verknüpft
`touch` und Skriptaufruf mit `&&`. Liefert das Skript je einen Fehler, bricht
die Kette und der Agent steht ohne Sprechtext da. Es gibt deshalb **immer** 0
zurück. `pronounce.sh` darf scheitern — es ist ein interaktives Werkzeug, kein
Glied einer Kette.

**Escaping.** Begriff und Ersetzung landen in einem `sed`-Ausdruck. Ein `&` in
der Ersetzung fügt dort den gematchten Text ein, ein `/` beendet den Ausdruck
vorzeitig, `.` und `*` machen aus einem Begriff ein Muster. Beide Seiten werden
vor dem Bau maskiert: die Suchseite die Regex-Metazeichen, die Ersetzungsseite
`&`, `\` und das Trennzeichen. Ohne das zerlegt eine harmlose Regel wie
`AT&T = Ah tee und tee` die Ausgabe.

## Tests

`tests/test-pronunciation.sh`, im Stil von `test-mute-marker.sh`: reines Bash,
`check`-Helfer, Exit-Code gleich Fehleranzahl. Getestet wird gegen eine
temporäre Regeldatei, nie gegen die echte.

1. Einfache Ersetzung greift — `Claude` → `Klod`
2. Längensortierung — bei Regeln für `Slice` und `Slices` wird „Slices" zu
   „Slaißis", und zwar in **beiden** Dateireihenfolgen
3. Sonderzeichen — `AT&T` und `C/C++` überleben als Begriff wie als Ersetzung
4. Kommentare, Leerzeilen und eine kaputte Zeile ohne `=` brechen nichts ab;
   die übrigen Regeln greifen weiter
5. Fehlende Datei → Text unverändert, Exit 0
6. `speakable.sh` gibt in jedem Eingabefall Exit 0 zurück, auch bei leerer
   Eingabe
7. `tts_clean_markdown` ersetzt **keine** Begriffe mehr, nur noch Markdown

Punkt 7 ist die Regressionsbremse gegen das Zurückwandern der Wortliste ins
Skript.

## Abgrenzung

Nicht Teil dieser Arbeit:

- Eintragen ohne Hörprobe und Zustimmung. Regeln **im Gespräch** aufzunehmen
  ist ausdrücklich Teil dieser Arbeit (siehe `commands/sprich.md`); was nicht
  dazugehört, ist die Schreibweise eigenmächtig festzulegen. Welche Umschrift
  richtig klingt, entscheidet das Ohr des Nutzers, nicht eine Heuristik.
- Phonem-Ersetzung über eine Lautschrift wie IPA. Piper nimmt Text; die
  Umschrift in deutscher Rechtschreibung ist das, was funktioniert.
- Sprachabhängige Regelsätze. Es gibt eine Stimme und ein Lexikon.
