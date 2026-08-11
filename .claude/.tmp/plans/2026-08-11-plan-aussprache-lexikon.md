# Aussprache-Lexikon — Umsetzungsplan

> **Für agentische Arbeiter:** ERFORDERLICHE SUB-SKILL: Nutze
> superpowers:subagent-driven-development (empfohlen) oder
> superpowers:executing-plans, um diesen Plan Aufgabe für Aufgabe umzusetzen.
> Die Schritte nutzen Checkbox-Syntax (`- [ ]`) zur Nachverfolgung.

**Ziel:** Die hartcodierte Aussprache-Wortliste aus `tts.sh` in eine
versionierte Regeldatei überführen, die sowohl der Vorlese-Hook als auch der
Sprachmodus nutzt, und beide Wege zum Aufnehmen neuer Regeln bereitstellen.

**Architektur:** `pronunciation.txt` ist die einzige Regelquelle.
`tts.sh` bekommt eine Funktion, die daraus **ein** `sed`-Skript baut und auf
stdin anwendet; sie ist getrennt von der Markdown-Bereinigung, damit der
Sprachmodus sie ohne deren Ballast nutzen kann. `speakable.sh` ist der Zugang
für den Sprachmodus, `pronounce.sh` das Hörprobe-Werkzeug, `aussprache.md` der
Slash-Command.

**Tech-Stack:** Bash (Skripte laufen unter `#!/usr/bin/env bash`), `sed` (BSD,
macOS), `awk`, `sort`, `jq`. Keine neuen Abhängigkeiten.

**Spec:** `.claude/.tmp/specs/2026-08-11-spec-aussprache-lexikon.md`

## Globale Randbedingungen

- **Das Lexikon darf die Stimme nie kosten.** Jeder Fehlerfall in der
  Regelanwendung reicht den Text unverändert durch, schreibt eine Zeile nach
  `speak.log` und gibt **Exit 0** zurück. Nie abbrechen.
- **`speakable.sh` gibt unter allen Umständen Exit 0 zurück.** Der Heartbeat in
  `/sprich` verknüpft `touch` und Skriptaufruf mit `&&`; ein Fehlschlag bräche
  die Kette und ließe den Agenten ohne Sprechtext.
- **Die Regeldatei wird über `$SCRIPT_DIR` gefunden**, nie über das
  Arbeitsverzeichnis — beim Hook-Aufruf ist das cwd ein fremdes Projekt.
- **Kandidaten in `pronounce.sh` gehen roh in die Synthese**, ohne
  Regelanwendung.
- **Kommentare und Ausgaben auf Deutsch**, im Ton des bestehenden Codes:
  erklären warum, nicht was.
- **Tests:** reines Bash, `check`-Helfer, Exit-Code gleich Fehleranzahl,
  Arbeit ausschließlich in `mktemp -d`-Verzeichnissen. Nie gegen die echte
  `pronunciation.txt` testen.
- **Branch:** `user/gemu/tts-aussprache` (existiert bereits, enthält Spec und
  den Slice-Vorabfix).

---

### Task 1: Regeldatei und Lexikon-Funktionen

Baut die Regelquelle und die Funktion, die sie anwendet. Die alte Wortliste in
`tts_clean_markdown` bleibt in dieser Aufgabe noch stehen — sie wird erst in
Task 2 entfernt, damit die Stimme zwischen den Commits nie ohne Regeln dasteht.

**Dateien:**
- Anlegen: `pronunciation.txt`
- Ändern: `tts.sh` (Kopf und neue Funktionen, `tts_clean_markdown` unberührt)
- Test: `tests/test-pronunciation.sh` (anlegen)

**Schnittstellen:**
- Konsumiert: nichts
- Produziert:
  - `PRONUNCIATION_FILE` — Shell-Variable, beim Sourcen von `tts.sh` gesetzt
    auf `<tts.sh-Verzeichnis>/pronunciation.txt`, sofern nicht schon von außen
    belegt (Tests setzen sie vorher)
  - `tts_pronunciation_script <regeldatei> [logdatei]` — schreibt ein
    `sed`-Skript nach stdout, eine `s///g`-Zeile je Regel, nach Begriffslänge
    absteigend sortiert
  - `tts_apply_pronunciation [regeldatei] [logdatei]` — liest stdin, schreibt
    den Text mit angewandten Regeln nach stdout, immer Exit 0

- [ ] **Schritt 1: Regeldatei anlegen**

Datei `pronunciation.txt`:

```
# claude-voice — Aussprache
#
# Format: Begriff = Lautschrift, eine Regel pro Zeile.
# Zeilen mit # und Leerzeilen werden ignoriert.
#
# Die Reihenfolge in dieser Datei ist bedeutungslos: beim Laden gewinnt der
# längere Begriff, damit "Slices" nicht von der Regel für "Slice" zerlegt wird.
# Wörter, die sich gebeugt anders anhören, brauchen trotzdem eine eigene Zeile.

Claude   = Klod
Keycloak = Kii klooug
Slices   = Slaißis
Slice    = Slaiß
```

- [ ] **Schritt 2: Den fehlschlagenden Test schreiben**

Datei `tests/test-pronunciation.sh` anlegen und ausführbar machen
(`chmod +x`):

```bash
#!/usr/bin/env bash
# Prüft das Aussprache-Lexikon: das Bauen und Anwenden der Regeln.
#
# Läuft gegen temporäre Regeldateien in einem eigenen Arbeitsverzeichnis;
# die pronunciation.txt des Repos bleibt unberührt.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
fails=0
trap 'rm -rf "$WORK"' EXIT

# shellcheck source=../tts.sh
. "$REPO/tts.sh" || { echo "tts.sh nicht sourcebar"; exit 1; }

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $name"
  else
    echo "  FAIL: $name — erwartet '$expected', war '$actual'"
    fails=$((fails + 1))
  fi
}

# apply <regeldatei> <text>
apply() { printf '%s' "$2" | tts_apply_pronunciation "$1" /dev/null; }

echo "Fall 1: einfache Ersetzung"
cat > "$WORK/simple.txt" <<'EOF'
Claude = Klod
EOF
check "Begriff ersetzt" "Klod hilft." "$(apply "$WORK/simple.txt" "Claude hilft.")"
check "Rest unberuehrt" "Nichts zu tun." "$(apply "$WORK/simple.txt" "Nichts zu tun.")"

echo
echo "Fall 2: laengerer Begriff gewinnt, unabhaengig von der Dateireihenfolge"
cat > "$WORK/order-a.txt" <<'EOF'
Slice  = Slaiß
Slices = Slaißis
EOF
cat > "$WORK/order-b.txt" <<'EOF'
Slices = Slaißis
Slice  = Slaiß
EOF
check "kurze Regel steht oben" "Slaißis und ein Slaiß" \
  "$(apply "$WORK/order-a.txt" "Slices und ein Slice")"
check "lange Regel steht oben" "Slaißis und ein Slaiß" \
  "$(apply "$WORK/order-b.txt" "Slices und ein Slice")"

echo
echo "Fall 3: sed-Sonderzeichen im Begriff"
cat > "$WORK/special-term.txt" <<'EOF'
AT&T  = Ah tee und tee
C/C++ = Zee plus plus
EOF
check "Ampersand im Begriff"    "Ah tee und tee ruft an." \
  "$(apply "$WORK/special-term.txt" "AT&T ruft an.")"
check "Schraegstrich im Begriff" "Zee plus plus ist alt." \
  "$(apply "$WORK/special-term.txt" "C/C++ ist alt.")"

echo
echo "Fall 4: sed-Sonderzeichen in der Ersetzung"
cat > "$WORK/special-repl.txt" <<'EOF'
Ampere = A&B
Pfad   = Schräg/Strich
EOF
check "Ampersand in der Ersetzung" "A&B fliesst." \
  "$(apply "$WORK/special-repl.txt" "Ampere fliesst.")"
check "Schraegstrich in der Ersetzung" "Schräg/Strich hier." \
  "$(apply "$WORK/special-repl.txt" "Pfad hier.")"

echo
echo "Fall 5: Kommentare, Leerzeilen und eine Zeile ohne ="
cat > "$WORK/messy.txt" <<'EOF'
# Kommentar

Claude = Klod
das ist keine Regel
Slice = Slaiß
EOF
check "uebrige Regeln greifen" "Klod mag Slaiß." \
  "$(apply "$WORK/messy.txt" "Claude mag Slice.")"

echo
echo "Fall 6: Regeldatei fehlt"
printf '%s' "Claude bleibt." | tts_apply_pronunciation "$WORK/gibtsnicht.txt" /dev/null > "$WORK/out.txt"
rc=$?
check "Text unveraendert" "Claude bleibt." "$(cat "$WORK/out.txt")"
check "Exit 0"            "0"              "$rc"

echo
if [ "$fails" -eq 0 ]; then
  echo "Alle Pruefungen bestanden."
else
  echo "$fails Pruefung(en) fehlgeschlagen."
fi
exit "$fails"
```

- [ ] **Schritt 3: Test laufen lassen und Fehlschlag bestätigen**

Ausführen: `./tests/test-pronunciation.sh`
Erwartet: Abbruch mit `tts_apply_pronunciation: command not found` oder
durchgehende FAILs — die Funktion existiert noch nicht.

- [ ] **Schritt 4: Regeldatei-Pfad im Kopf von `tts.sh` festlegen**

In `tts.sh` direkt unter `TTS_DEFAULT_VOICE` (Zeile 6) einfügen:

```bash
# Die Regeldatei liegt neben tts.sh, nicht im Arbeitsverzeichnis — beim
# Hook-Aufruf ist das cwd ein fremdes Projekt. Eine von außen gesetzte
# Variable gewinnt, damit Tests gegen eigene Regeldateien laufen können.
TTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRONUNCIATION_FILE="${PRONUNCIATION_FILE:-$TTS_DIR/pronunciation.txt}"
```

- [ ] **Schritt 5: Die Lexikon-Funktionen implementieren**

In `tts.sh` **nach** `tts_clean_markdown` und **vor** `tts_synthesize`
einfügen:

```bash
# _tts_escape_search / _tts_escape_replace
# Maskieren die Sonderzeichen, die sed in Muster und Ersetzung anders liest
# als gemeint. Ohne das zerlegt eine harmlose Regel wie "AT&T = Ah tee und tee"
# den Ausdruck, in dem sie landet: & fügt den gematchten Text ein, / beendet
# den Ausdruck vorzeitig, . und * machen aus dem Begriff ein Muster.
_tts_escape_search()  { printf '%s' "$1" | sed 's|[][\.*^$/]|\\&|g'; }
_tts_escape_replace() { printf '%s' "$1" | sed 's|[\\&/]|\\&|g'; }

# tts_pronunciation_script <regeldatei> [logfile]
# Baut aus der Regeldatei ein sed-Skript, eine s///g-Zeile je Regel.
# Sortiert nach Begriffslänge absteigend: sonst machte die Regel für "Slice"
# aus einem "Slices" ein "Slaißs", bevor die eigene Regel greifen könnte.
tts_pronunciation_script() {
  local rules="$1" log="${2:-/dev/null}"
  local line term repl broken

  broken=$(grep -vE '^[[:space:]]*(#|$)' "$rules" | grep -vc '=')
  if [ "${broken:-0}" -gt 0 ]; then
    echo "$(date): ${broken} Zeile(n) ohne '=' in $rules uebersprungen" >> "$log"
  fi

  grep -vE '^[[:space:]]*(#|$)' "$rules" | grep '=' | while IFS= read -r line; do
    term="${line%%=*}"
    repl="${line#*=}"
    term="$(printf '%s' "$term" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    repl="$(printf '%s' "$repl" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -n "$term" ] || continue
    printf '%d\t%s\t%s\n' "${#term}" "$term" "$repl"
  done | sort -rn -k1,1 | while IFS="$(printf '\t')" read -r _ term repl; do
    printf 's/%s/%s/g\n' "$(_tts_escape_search "$term")" "$(_tts_escape_replace "$repl")"
  done
}

# tts_apply_pronunciation [regeldatei] [logfile]
# Liest stdin, schreibt den Text mit angewandten Aussprache-Regeln nach stdout.
# Fehlt die Datei, enthält sie keine Regel oder scheitert sed, kommt der Text
# unverändert durch: das Lexikon darf die Stimme nie kosten. Immer Exit 0.
tts_apply_pronunciation() {
  local rules="${1:-${PRONUNCIATION_FILE:-}}" log="${2:-/dev/null}"
  local text script out

  text="$(cat)"

  if [ -z "$rules" ] || [ ! -f "$rules" ]; then
    echo "$(date): Keine Aussprache-Regeln unter '${rules:-<nicht gesetzt>}'" >> "$log"
    printf '%s\n' "$text"
    return 0
  fi

  script="$(tts_pronunciation_script "$rules" "$log")"
  if [ -z "$script" ]; then
    printf '%s\n' "$text"
    return 0
  fi

  out="$(printf '%s\n' "$text" | sed -f <(printf '%s\n' "$script") 2>> "$log")"

  # Ein leerer Rückgabewert bei nicht-leerer Eingabe heißt: sed ist gestolpert.
  if [ -z "$out" ] && [ -n "$text" ]; then
    echo "$(date): Aussprache-Regeln lieferten leeren Text, Original bleibt" >> "$log"
    printf '%s\n' "$text"
    return 0
  fi

  printf '%s\n' "$out"
  return 0
}
```

- [ ] **Schritt 6: Test laufen lassen und grün sehen**

Ausführen: `./tests/test-pronunciation.sh`
Erwartet: `Alle Pruefungen bestanden.` und Exit-Code 0.

Falls Fall 2 fehlschlägt, sitzt der Fehler in der Sortierung; falls Fall 3
oder 4 fehlschlägt, im Escaping. Beide Stellen einzeln prüfen mit:

```bash
. ./tts.sh && tts_pronunciation_script pronunciation.txt
```

Erwartete Ausgabe (Reihenfolge nach Begriffslänge):

```
s/Keycloak/Kii klooug/g
s/Slices/Slaißis/g
s/Claude/Klod/g
s/Slice/Slaiß/g
```

- [ ] **Schritt 7: Committen**

```bash
git add pronunciation.txt tts.sh tests/test-pronunciation.sh
git commit -m "feat: Aussprache-Regeln aus einer versionierten Datei laden

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Umstellung der Sprachrohre, Wortliste raus

Erst hier verliert `tts_clean_markdown` seine Wortliste — im selben Commit, in
dem `speak.sh` und `replay.sh` die neue Funktion aufrufen. Dazwischen gibt es
keinen Zustand ohne Regeln.

**Dateien:**
- Ändern: `tts.sh:43-46` (Wortliste aus `tts_clean_markdown` entfernen)
- Ändern: `speak.sh:93`
- Ändern: `replay.sh:46`
- Test: `tests/test-pronunciation.sh` (Fall 7 ergänzen)

**Schnittstellen:**
- Konsumiert: `tts_apply_pronunciation`, `PRONUNCIATION_FILE` aus Task 1
- Produziert: nichts Neues

- [ ] **Schritt 1: Den fehlschlagenden Test ergänzen**

In `tests/test-pronunciation.sh` **vor** dem abschließenden `if`-Block
einfügen:

```bash
echo
echo "Fall 7: tts_clean_markdown raeumt nur Markdown ab, ersetzt keine Begriffe"
check "Begriff bleibt stehen" "Claude und Slice" \
  "$(printf '%s' '**Claude** und `Slice`' | tts_clean_markdown)"
```

- [ ] **Schritt 2: Test laufen lassen und Fehlschlag bestätigen**

Ausführen: `./tests/test-pronunciation.sh`
Erwartet: `FAIL: Begriff bleibt stehen — erwartet 'Claude und Slice', war
'Klod und Slaiß'` — die Wortliste steckt noch in der Funktion.

- [ ] **Schritt 3: Wortliste aus `tts_clean_markdown` entfernen**

In `tts.sh` diese vier Zeilen ersatzlos streichen:

```bash
    | sed 's/Claude/Klod/g' \
    | sed 's/[Kk]eycloak/Kii klooug/g' \
    | sed 's/[Ss]lices/Slaißis/g' \
    | sed 's/[Ss]lice/Slaiß/g'
```

Die Zeile davor verliert dabei ihren fortsetzenden Backslash und wird zur
letzten Zeile der Pipe:

```bash
    | sed -E 's/^[[:space:]]*//;s/[[:space:]]*$//'
}
```

Den Funktionskommentar anpassen, damit er die neue Arbeitsteilung benennt:

```bash
# tts_clean_markdown — liest stdin, schreibt sprechbaren Text nach stdout
# Code-Blöcke fliegen raus, Inline-Code behält seinen Inhalt.
# Aussprache-Regeln gehören nicht hierher, dafür gibt es
# tts_apply_pronunciation — sonst schleppt der Sprachmodus die
# Markdown-Bereinigung mit, die er nicht braucht.
```

- [ ] **Schritt 4: `speak.sh` umstellen**

`speak.sh:93` ersetzen:

```bash
CLEAN_TEXT=$(echo "$SPEAK_TEXT" | tts_clean_markdown | tts_apply_pronunciation "$PRONUNCIATION_FILE" "$LOG")
```

- [ ] **Schritt 5: `replay.sh` umstellen**

`replay.sh:46` ersetzen:

```bash
CLEAN_TEXT=$(echo "$MESSAGE" | tts_clean_markdown | tts_apply_pronunciation "$PRONUNCIATION_FILE" "$LOG")
```

- [ ] **Schritt 6: Alle Tests laufen lassen**

```bash
./tests/test-pronunciation.sh
./tests/test-mute-marker.sh
./tests/test-commands.sh
```

Erwartet: alle drei melden `Alle Pruefungen bestanden.` und Exit 0.
`test-mute-marker.sh` muss weiterhin grün sein — es fährt `speak.sh` komplett
durch und würde eine kaputte Pipe sofort zeigen.

- [ ] **Schritt 7: Ende-zu-Ende von Hand prüfen**

```bash
echo 'Claude schneidet **Slices** und ein `Slice`.' | (. ./tts.sh && tts_clean_markdown | tts_apply_pronunciation)
```

Erwartet: `Klod schneidet Slaißis und ein Slaiß.`

- [ ] **Schritt 8: Committen**

```bash
git add tts.sh speak.sh replay.sh tests/test-pronunciation.sh
git commit -m "refactor: Wortliste aus tts_clean_markdown in das Lexikon verlegt

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: `speakable.sh` für den Sprachmodus

**Dateien:**
- Anlegen: `speakable.sh` (ausführbar)
- Test: `tests/test-pronunciation.sh` (Fall 8 ergänzen)

**Schnittstellen:**
- Konsumiert: `tts_apply_pronunciation`, `PRONUNCIATION_FILE` aus Task 1
- Produziert: `speakable.sh "<text>"` bzw. `… | speakable.sh` — schreibt den
  Text mit angewandten Regeln nach stdout, Exit immer 0

- [ ] **Schritt 1: Den fehlschlagenden Test ergänzen**

In `tests/test-pronunciation.sh` vor dem abschließenden `if`-Block einfügen:

```bash
echo
echo "Fall 8: speakable.sh"
out=$(PRONUNCIATION_FILE="$WORK/simple.txt" "$REPO/speakable.sh" "Claude hilft.")
check "Argument wird ersetzt" "Klod hilft." "$out"

out=$(printf '%s' "Claude hilft." | PRONUNCIATION_FILE="$WORK/simple.txt" "$REPO/speakable.sh")
check "stdin wird ersetzt" "Klod hilft." "$out"

PRONUNCIATION_FILE="$WORK/simple.txt" "$REPO/speakable.sh" "Claude hilft." > /dev/null
check "Exit 0 bei Text" "0" "$?"

printf '' | PRONUNCIATION_FILE="$WORK/simple.txt" "$REPO/speakable.sh" > /dev/null
check "Exit 0 bei leerer Eingabe" "0" "$?"

printf '' | PRONUNCIATION_FILE="$WORK/gibtsnicht.txt" "$REPO/speakable.sh" > /dev/null
check "Exit 0 ohne Regeldatei" "0" "$?"
```

- [ ] **Schritt 2: Test laufen lassen und Fehlschlag bestätigen**

Ausführen: `./tests/test-pronunciation.sh`
Erwartet: FAILs in Fall 8 mit leeren Ist-Werten — `speakable.sh` gibt es noch
nicht.

- [ ] **Schritt 3: `speakable.sh` schreiben**

```bash
#!/usr/bin/env bash
# Claude Voice - Text durch die Aussprache-Regeln schicken.
#
# Für den Sprachmodus: /sprich hängt den Aufruf an seinen Heartbeat und
# übergibt die Ausgabe als message an converse. Deshalb gibt dieses Skript
# IMMER 0 zurück — ein Fehlschlag bräche die &&-Kette im Heartbeat und ließe
# den Agenten ohne Sprechtext zurück.
#
# Markdown wird bewusst nicht abgeräumt: der Sprechtext des Sprachmodus ist
# schon Klartext.
#
# Aufruf: speakable.sh "Text"   oder   echo "Text" | speakable.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$SCRIPT_DIR/speak.log"

# shellcheck source=tts.sh
. "$SCRIPT_DIR/tts.sh"

if [ "$#" -gt 0 ]; then
  printf '%s' "$*"
else
  cat
fi | tts_apply_pronunciation "$PRONUNCIATION_FILE" "$LOG"

exit 0
```

Ausführbar machen: `chmod +x speakable.sh`

- [ ] **Schritt 4: Test laufen lassen und grün sehen**

Ausführen: `./tests/test-pronunciation.sh`
Erwartet: `Alle Pruefungen bestanden.`, Exit 0.

- [ ] **Schritt 5: Von Hand gegenprüfen**

```bash
./speakable.sh "Claude schneidet ein Slice."
```

Erwartet: `Klod schneidet ein Slaiß.`

- [ ] **Schritt 6: Committen**

```bash
git add speakable.sh tests/test-pronunciation.sh
git commit -m "feat: speakable.sh reicht Sprechtext durch das Lexikon

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: `pronounce.sh` für die Hörprobe

**Dateien:**
- Anlegen: `pronounce.sh` (ausführbar)
- Test: `tests/test-pronounce.sh` (anlegen, ausführbar)

**Schnittstellen:**
- Konsumiert: `tts_load_config`, `tts_synthesize`, `tts_play` aus `tts.sh`
- Produziert: `pronounce.sh <kandidat> [kandidat …]` — synthetisiert und
  spielt die durchnummerierten Kandidaten ab; schreibt den gesprochenen Satz
  als `pronounce.sh — <satz>` nach `speak.log`

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

Der Test braucht einen eigenen `curl`-Stub, damit keine Sprachausgabe anläuft,
und liest den gesprochenen Satz aus dem Log — dasselbe Muster wie
`test-mute-marker.sh`. Datei `tests/test-pronounce.sh` anlegen und ausführbar
machen:

```bash
#!/usr/bin/env bash
# Prüft pronounce.sh — das Vorsprechen von Aussprache-Kandidaten.
#
# Ein curl-Stub verhindert, dass beim Prüfen Sprachausgabe anläuft; geprüft
# wird der Satz, den das Skript ins Log schreibt.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$REPO/speak.log"
STUB="$(mktemp -d)"
fails=0
trap 'rm -rf "$STUB"' EXIT

cat > "$STUB/curl" <<'EOF'
#!/usr/bin/env bash
echo -n "000"
exit 1
EOF
chmod +x "$STUB/curl"

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $name"
  else
    echo "  FAIL: $name — erwartet '$expected', war '$actual'"
    fails=$((fails + 1))
  fi
}

mark_log() { echo "--- TESTMARKE ---" >> "$LOG"; }

spoken_line() {
  awk '/^--- TESTMARKE ---$/ { out = ""; next }
       /pronounce\.sh — / { sub(/^.*pronounce\.sh — /, ""); out = $0 }
       END { printf "%s", out }' "$LOG"
}

echo "Fall 1: drei Kandidaten werden durchnummeriert"
mark_log
PATH="$STUB:$PATH" "$REPO/pronounce.sh" "Sleis" "Slaiß" "Sleiß" > /dev/null 2>&1
check "Satz aufgebaut" "Erstens: Sleis. Zweitens: Slaiß. Drittens: Sleiß." "$(spoken_line)"

echo
echo "Fall 2: mehr Kandidaten als Ordnungszahlen"
mark_log
PATH="$STUB:$PATH" "$REPO/pronounce.sh" a b c d e f g > /dev/null 2>&1
check "siebter faellt auf Nummer zurueck" \
  "Erstens: a. Zweitens: b. Drittens: c. Viertens: d. Fünftens: e. Sechstens: f. Nummer 7: g." \
  "$(spoken_line)"

echo
echo "Fall 3: ohne Kandidaten"
PATH="$STUB:$PATH" "$REPO/pronounce.sh" > /dev/null 2>&1
check "Exit 1" "1" "$?"

echo
echo "Fall 4: Kandidaten gehen roh in die Synthese"
mark_log
PATH="$STUB:$PATH" "$REPO/pronounce.sh" "Claude" > /dev/null 2>&1
check "keine Regel angewandt" "Erstens: Claude." "$(spoken_line)"

echo
if [ "$fails" -eq 0 ]; then
  echo "Alle Pruefungen bestanden."
else
  echo "$fails Pruefung(en) fehlgeschlagen."
fi
exit "$fails"
```

Fall 4 ist der wichtige: stünde `tts_apply_pronunciation` im Weg, käme dort
`Erstens: Klod.` heraus und man hörte nie den Kandidaten, den man eingegeben
hat.

- [ ] **Schritt 2: Test laufen lassen und Fehlschlag bestätigen**

Ausführen: `./tests/test-pronounce.sh`
Erwartet: FAILs mit leeren Ist-Werten — `pronounce.sh` gibt es noch nicht.

- [ ] **Schritt 3: `pronounce.sh` schreiben**

```bash
#!/usr/bin/env bash
# Claude Voice - Aussprache-Kandidaten zum Vergleich vorsprechen.
#
# Aufruf: pronounce.sh "Sleis" "Slaiß" "Sleiß"
#
# Die Kandidaten gehen ROH in die Synthese, ohne Aussprache-Regeln: sonst
# überschriebe eine bestehende Regel genau den Kandidaten, den man hören will.
#
# Alles landet in einem einzigen Synthese-Durchgang, damit der Vergleich eine
# zusammenhängende Aufnahme wird statt drei abgehackter.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
LOG="$SCRIPT_DIR/speak.log"

# shellcheck source=tts.sh
. "$SCRIPT_DIR/tts.sh"

if [ "$#" -eq 0 ]; then
  echo "Aufruf: $(basename "$0") <kandidat> [kandidat ...]"
  exit 1
fi

ORDINALS=(Erstens Zweitens Drittens Viertens Fünftens Sechstens)

TEXT=""
i=0
for candidate in "$@"; do
  label="${ORDINALS[$i]:-Nummer $((i + 1))}"
  TEXT="${TEXT}${label}: ${candidate}. "
  i=$((i + 1))
done
TEXT="${TEXT% }"

tts_load_config "$CONFIG"
TTS_MODEL_PATH="$SCRIPT_DIR/models/${MODEL_NAME}.onnx"

echo "$(date): pronounce.sh — ${TEXT}" >> "$LOG"

# Eigene Pfade, damit eine laufende Wiedergabe des Hooks unberührt bleibt
WAVFILE="/tmp/claude-voice-pronounce.wav"
PIDFILE="/tmp/claude-voice-pronounce.pid"

if tts_synthesize "$TEXT" "$WAVFILE" "$LOG"; then
  tts_play "$WAVFILE" "$PIDFILE"
  echo "Vorsprechen gestartet: $TEXT"
  exit 0
fi

echo "Fehler: Sprachausgabe konnte nicht erzeugt werden — Details in speak.log."
exit 1
```

Ausführbar machen: `chmod +x pronounce.sh`

- [ ] **Schritt 4: Test laufen lassen und grün sehen**

Ausführen: `./tests/test-pronounce.sh`
Erwartet: `Alle Pruefungen bestanden.`, Exit 0.

- [ ] **Schritt 5: Mit echter Stimme gegenhören**

```bash
./pronounce.sh "Sleis" "Slaiß" "Sleiß"
```

Erwartet: hörbare Ausgabe der drei Kandidaten. Läuft gerade ein Sprachmodus,
diesen Schritt überspringen — die Wiedergabe störte das Zuhören.

- [ ] **Schritt 6: Committen**

```bash
git add pronounce.sh tests/test-pronounce.sh
git commit -m "feat: pronounce.sh spricht Aussprache-Kandidaten vor

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Slash-Command `/aussprache`

**Dateien:**
- Anlegen: `commands/aussprache.md`
- Ändern: `tests/test-commands.sh:76` (erwartete Command-Anzahl 2 → 3)

**Schnittstellen:**
- Konsumiert: `pronounce.sh` aus Task 4, `pronunciation.txt` aus Task 1
- Produziert: nichts für andere Aufgaben

- [ ] **Schritt 1: Den fehlschlagenden Test anpassen**

`tests/test-commands.sh:76` ändern:

```bash
  check "alle Commands installiert" "3" "$installed"
```

- [ ] **Schritt 2: Test laufen lassen und Fehlschlag bestätigen**

Ausführen: `./tests/test-commands.sh`
Erwartet: `FAIL: alle Commands installiert — erwartet '3', war '2'` —
`aussprache.md` gibt es noch nicht.

- [ ] **Schritt 3: `commands/aussprache.md` schreiben**

```markdown
Pflege das Aussprache-Lexikon von claude-voice — die Regeln, mit denen das
deutsche Thorsten-Modell englische Begriffe verständlich ausspricht.

Regeldatei: `{{CLAUDE_VOICE_DIR}}/pronunciation.txt`
Format: `Begriff = Lautschrift`, eine Regel pro Zeile, `#` leitet einen
Kommentar ein. Die Reihenfolge in der Datei ist bedeutungslos — beim Laden
gewinnt der längere Begriff. Neue Regeln deshalb einfach anhängen.

Drei Aufrufformen, je nachdem was hinter dem Befehl steht:

**Ohne Argument** — die aktuellen Regeln auflisten:

```bash
cat "{{CLAUDE_VOICE_DIR}}/pronunciation.txt"
```

**Nur ein Begriff** (`/aussprache Slice`) — Schreibweise gemeinsam finden:

1. Drei deutsche Umschriften vorschlagen, die den englischen Klang treffen.
   Piper liest deutsch: „Slice" wird zu „Slaiß", nicht zu „slaɪs". Keine IPA,
   keine englische Schreibweise.
2. Vorsprechen lassen:
   ```bash
   {{CLAUDE_VOICE_DIR}}/pronounce.sh "Sleis" "Slaiß" "Sleiß"
   ```
   Läuft gerade der Sprachmodus, stattdessen die Kandidaten über `converse`
   sprechen — sonst redet die Hörprobe dem Zuhören dazwischen.
3. Auswählen lassen. Nie selbst entscheiden, welche Umschrift gewinnt: das
   hört der Nutzer, nicht du.
4. Die gewählte Regel anhängen.

**Begriff und Lautschrift** (`/aussprache Slice = Slaiß`) — direkt eintragen,
ohne Hörprobe.

Vor jedem Eintrag prüfen, ob der Begriff schon eine Regel hat:

```bash
grep -n "^[[:space:]]*Slice[[:space:]]*=" "{{CLAUDE_VOICE_DIR}}/pronunciation.txt"
```

Gibt es einen Treffer, die bestehende Lautschrift zeigen und fragen, bevor sie
ersetzt wird.

**Nach dem Eintrag nicht committen.** Ein Aussprache-Fund passiert mitten in
anderer Arbeit; ein Commit landete sonst ungefragt auf einem fremden
Feature-Branch. Stattdessen sagen, was eingetragen wurde und dass die Änderung
uncommitted in `pronunciation.txt` liegt.

Die Regel wirkt sofort — Hook wie Sprachmodus lesen die Datei bei jedem
Aufruf neu. Eine Neuinstallation ist nicht nötig.
```

- [ ] **Schritt 4: Tests laufen lassen und grün sehen**

```bash
./tests/test-commands.sh
```

Erwartet: `Alle Pruefungen bestanden.` — insbesondere Fall 5, der prüft, dass
kein `{{CLAUDE_VOICE_DIR}}` nach dem Ausrollen zurückbleibt.

- [ ] **Schritt 5: Ausrollen von Hand prüfen**

```bash
./install.sh
grep -c "CLAUDE_VOICE_DIR" ~/.claude/commands/aussprache.md
```

Erwartet: `0` — jeder Platzhalter ist durch den Repo-Pfad ersetzt. Die Frage
des Installers nach dem Installationsziel wie gewohnt beantworten.

- [ ] **Schritt 6: Committen**

```bash
git add commands/aussprache.md tests/test-commands.sh
git commit -m "feat: /aussprache pflegt das Lexikon per Hörprobe

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Sprachmodus und README

**Dateien:**
- Ändern: `commands/sprich.md` (Heartbeat und Korrektur-Regel)
- Ändern: `README.md` (Dateiübersicht, Tests, Aussprache-Abschnitt)

**Schnittstellen:**
- Konsumiert: `speakable.sh` aus Task 3, `pronunciation.txt` aus Task 1
- Produziert: nichts für andere Aufgaben

- [ ] **Schritt 1: Heartbeat in `commands/sprich.md` erweitern**

Den Codeblock in Zeile 7-9 ersetzen:

````markdown
```bash
touch "/tmp/claude-voice-mute-$(echo -n "$PWD" | md5 -q)" \
  && {{CLAUDE_VOICE_DIR}}/speakable.sh "<dein Sprechtext>"
```
````

Und den Absatz darunter (Zeile 11-14) ersetzen:

```markdown
**Denselben Befehl vor jedem `converse`-Aufruf wiederholen**, und die Ausgabe
von `speakable.sh` als `message` übergeben statt deines Rohtexts. Zwei Dinge
hängen daran: Der Marker verfällt zehn Minuten nach der letzten Auffrischung,
dieser Heartbeat hält ihn am Leben. Und `speakable.sh` setzt die
Aussprache-Regeln aus `pronunciation.txt` ein, damit die Stimme englische
Begriffe im Sprachmodus so ausspricht wie im Vorlese-Hook. Bricht die Session
ab, bleibt die Auffrischung aus und der Hook findet von allein zurück zu
seiner Stimme.
```

- [ ] **Schritt 2: Korrektur-Regel in `commands/sprich.md` ergänzen**

In der Liste unter „Protokoll:" nach dem Whisper-Punkt (Zeile 45-46) einfügen:

```markdown
- **Aussprache-Korrekturen mitnehmen.** Weist der Nutzer auf einen falsch
  gesprochenen Begriff hin („das heißt nicht Sleike, das heißt Slice"), biete
  von selbst an, die Schreibweise festzuhalten: drei deutsche Umschriften über
  `converse` vorsprechen, auswählen lassen, als `Begriff = Lautschrift` an
  `{{CLAUDE_VOICE_DIR}}/pronunciation.txt` anhängen. Nicht committen, nur
  Bescheid geben. Nie selbst entscheiden, welche Umschrift gewinnt — das hört
  der Nutzer.
```

- [ ] **Schritt 3: Command-Ausrollen prüfen**

```bash
./tests/test-commands.sh
```

Erwartet: `Alle Pruefungen bestanden.` — Fall 5 fängt einen vergessenen
Platzhalter ab.

- [ ] **Schritt 4: README ergänzen**

In der Dateiübersicht (um Zeile 105-111) die neuen Zeilen einfügen, im Format
der bestehenden Tabelle:

```markdown
| `pronunciation.txt` | Aussprache-Regeln: `Begriff = Lautschrift` |
| `speakable.sh` | reicht Sprechtext des Sprachmodus durch die Regeln |
| `pronounce.sh` | spricht Aussprache-Kandidaten zum Vergleich vor |
```

Den Tests-Abschnitt (Zeile 113-118) erweitern:

````markdown
```bash
./tests/test-mute-marker.sh    # Verfall des Stumm-Markers
./tests/test-commands.sh       # Ausrollen der Slash-Commands
./tests/test-pronunciation.sh  # Regelanwendung des Lexikons
./tests/test-pronounce.sh      # Vorsprechen der Kandidaten
```
````

Und einen eigenen Abschnitt vor „## Tests" einfügen:

```markdown
## Aussprache

Das Thorsten-Modell liest deutsch und verunstaltet englische Begriffe.
`pronunciation.txt` hält dagegen:

```
Claude = Klod
Slice  = Slaiß
```

Die Regeln gelten für den Vorlese-Hook wie für den Sprachmodus. Die
Reihenfolge in der Datei ist bedeutungslos — beim Laden gewinnt der längere
Begriff, damit `Slices` nicht von der Regel für `Slice` zerlegt wird.

Neue Regeln kommen über `/aussprache <Begriff>`: Claude schlägt Umschriften
vor, spricht sie zum Vergleich, und trägt die gewählte ein. Im Sprachmodus
genügt der Hinweis, dass ein Wort falsch klang. Änderungen wirken sofort,
ohne Neuinstallation.
```

- [ ] **Schritt 5: Vollständigen Testlauf**

```bash
./tests/test-mute-marker.sh && \
./tests/test-commands.sh && \
./tests/test-pronunciation.sh && \
./tests/test-pronounce.sh && echo "ALLE GRUEN"
```

Erwartet: `ALLE GRUEN` als letzte Zeile.

- [ ] **Schritt 6: Committen und Branch pushen**

```bash
git add commands/sprich.md README.md
git commit -m "docs: Sprachmodus und README auf das Lexikon eingestellt

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git push -u origin user/gemu/tts-aussprache
```

- [ ] **Schritt 7: Pull Request eröffnen**

```bash
gh pr create --title "Aussprache-Lexikon für beide Sprachrohre" --body "$(cat <<'EOF'
## Warum

Das Thorsten-Modell verunstaltet englische Begriffe. Die Gegenmittel steckten
als `sed`-Zeilen in `tts_clean_markdown` — unerreichbar für den Sprachmodus,
und jede neue Regel war ein Code-Change.

## Was

- `pronunciation.txt` als einzige, versionierte Regelquelle
- `tts_apply_pronunciation` als eigene Funktion neben der Markdown-Bereinigung
- `speakable.sh` bringt die Regeln in den Sprachmodus
- `/aussprache` und die Korrektur-Regel in `/sprich` nehmen neue Begriffe im
  Gespräch auf, mit Hörprobe statt Rateversuch

Spec: `.claude/.tmp/specs/2026-08-11-spec-aussprache-lexikon.md`

## Geprüft

Vier Testskripte, alle grün — darunter Längensortierung in beiden
Dateireihenfolgen und `sed`-Sonderzeichen auf beiden Seiten der Regel.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Review und Merge bleiben Teamaufgabe — der PR wird offen und grün übergeben.

---

## Abhängigkeiten

```
Task 1 (Regeldatei + Funktionen)
  ├── Task 2 (Sprachrohre umstellen)
  ├── Task 3 (speakable.sh) ──── Task 6 (sprich.md, README)
  └── Task 4 (pronounce.sh) ──── Task 5 (/aussprache)
```

Task 2, 3 und 4 hängen nur an Task 1 und sind untereinander unabhängig.
Task 6 braucht Task 3, Task 5 braucht Task 4.
