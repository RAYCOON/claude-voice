#!/usr/bin/env bash
# Claude Voice - gemeinsame TTS-Bausteine für speak.sh und replay.sh
# Wird gesourct, nicht direkt ausgeführt.

TTS_DEFAULT_URL="http://127.0.0.1:8881/v1/audio/speech"
TTS_DEFAULT_VOICE="de_DE-thorsten-high"
# Ueberschriften, ab denen der Vorlese-Hook den Rest der Antwort abschneidet
# (siehe tts_strip_trailing_sections) — Default, falls config.json den Key
# skip_sections nicht setzt. Die Muster decken die Varianten ab, in denen
# der Fussbereich tatsaechlich erschien ("Nächste sinnvolle Schritte",
# "Vorschläge für die nächsten Tasks", "5 Prompt-Vorschläge"): fehlt eine
# Variante, liest der Hook statt der Antwort die komplette Vorschlagsliste
# vor — beobachtet am 2026-08-25.
TTS_DEFAULT_SKIP_SECTIONS=("Nächste.*(Schritte|Tasks|Prompts)" "Next steps" "Vorschläge" "([0-9]+ )?Prompt-Vorschläge")

# Die Regeldatei liegt neben tts.sh, nicht im Arbeitsverzeichnis — beim
# Hook-Aufruf ist das cwd ein fremdes Projekt. Eine von außen gesetzte
# Variable gewinnt, damit Tests gegen eigene Regeldateien laufen können.
TTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRONUNCIATION_FILE="${PRONUNCIATION_FILE:-$TTS_DIR/pronunciation.txt}"

# tts_load_config <config.json>
# Setzt SPEED, VOLUME, PARAGRAPH, TTS_URL, VOICE, MODEL_NAME, SKIP_SECTIONS
tts_load_config() {
  local config="$1"
  local line
  SKIP_SECTIONS=()
  if [ -f "$config" ]; then
    SPEED=$(jq -r '.speed // 1.0' "$config")
    VOLUME=$(jq -r '.volume // 1.0' "$config")
    PARAGRAPH=$(jq -r '.paragraph // "last"' "$config")
    TTS_URL=$(jq -r ".tts_url // \"$TTS_DEFAULT_URL\"" "$config")
    VOICE=$(jq -r ".voice // \"$TTS_DEFAULT_VOICE\"" "$config")
    MODEL_NAME=$(jq -r ".model // \"$TTS_DEFAULT_VOICE\"" "$config")
    # Der Key selbst entscheidet, nicht sein Inhalt: eine leere Liste ist ein
    # bewusstes "nie schneiden" und muss von "Key fehlt" (Default) unterscheidbar
    # bleiben. mapfile gibt es unter Bash 3.2 (macOS) nicht, daher die
    # while-read-Schleife über Prozess-Substitution (kein Sub-Shell-Verlust
    # der Array-Zuweisungen wie bei einer Pipe in while).
    if jq -e 'has("skip_sections")' "$config" > /dev/null 2>&1; then
      while IFS= read -r line; do
        SKIP_SECTIONS+=("$line")
      done < <(jq -r '.skip_sections[]?' "$config")
    else
      SKIP_SECTIONS=("${TTS_DEFAULT_SKIP_SECTIONS[@]}")
    fi
  else
    SPEED=1.0
    VOLUME=1.0
    PARAGRAPH="last"
    TTS_URL="$TTS_DEFAULT_URL"
    VOICE="$TTS_DEFAULT_VOICE"
    MODEL_NAME="$TTS_DEFAULT_VOICE"
    SKIP_SECTIONS=("${TTS_DEFAULT_SKIP_SECTIONS[@]}")
  fi
}

# tts_clean_markdown — liest stdin, schreibt sprechbaren Text nach stdout
# Code-Blöcke fliegen raus, Inline-Code behält seinen Inhalt.
# Listen-Items ohne Satzzeichen enden als Satz (Punkt angehängt): sonst liest
# Piper eine Aufzählung als atemlosen Fließtext ohne Pausen durch — gemessen
# ~24 statt ~18 Zeichen/s, und genau das macht Listen unverständlich.
# Aussprache-Regeln gehören nicht hierher, dafür gibt es
# tts_apply_pronunciation — sonst schleppt der Sprachmodus die
# Markdown-Bereinigung mit, die er nicht braucht.
tts_clean_markdown() {
  sed -E 's/```[^`]*```//g' \
    | sed -E 's/`([^`]*)`/\1/g' \
    | sed -E 's/\*\*([^*]*)\*\*/\1/g' \
    | sed -E 's/\*([^*]*)\*/\1/g' \
    | sed -E 's/^#{1,6}[[:space:]]*//' \
    | sed -E 's/\[([^]]*)\]\([^)]*\)/\1/g' \
    | sed -E 's/!\[([^]]*)\]\([^)]*\)//' \
    | sed -E 's/^[[:space:]]*[-*+][[:space:]]+(.*[^.!?:;[:space:]])[[:space:]]*$/\1./' \
    | sed -E 's/^[[:space:]]*[-*+][[:space:]]*//' \
    | sed -E 's/^[[:space:]]*[0-9]+\.[[:space:]]+(.*[^.!?:;[:space:]])[[:space:]]*$/\1./' \
    | sed -E 's/^[[:space:]]*[0-9]+\.[[:space:]]*//' \
    | tr -s ' ' \
    | sed -E 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# tts_strip_trailing_sections [pattern ...]
# Liest stdin, schreibt stdout: alles ab der LETZTEN Zeile, die (nach Abzug
# von Markdown-Dekoration) einer der uebergebenen ERE-Muster entspricht, faellt
# weg — Ueberschrift eingeschlossen. Grund: Antworten enden oft mit einem Block
# "Nächste sinnvolle Schritte" voller Vorschlagsprompts fuer den naechsten
# Turn; ohne diesen Schnitt waere genau dieser Block der "letzte Absatz", den
# speak.sh vorliest, statt der eigentlichen Antwort.
# Die LETZTE Uebereinstimmung gewinnt, nicht die erste: taucht "Nächste
# Schritte" mitten in einer Anleitung als echte Zwischenueberschrift auf, darf
# das nicht die zweite Haelfte der Antwort verschlucken — erst der Block ganz
# am Ende zaehlt als Fussbereich.
# Verglichen wird erst NACH dem Entfernen von Markdown-Dekoration (fuehrende
# Leerzeichen, #, **, uebrige nicht-alphanumerische Bytes am Zeilenanfang):
# sonst triggerte ein Fliesstextsatz wie "Für Nächste Schritte siehe unten."
# faelschlich, nur weil die Woerter irgendwo in der Zeile stehen.
# Groß-/Kleinschreibung zaehlt beim Vergleich (siehe tts_pronunciation_script:
# tolower ist in dieser awk-Version nur ASCII-faehig, Umlaute blieben also
# unveraendert — ein case-insensitiver Vergleich waere hier keiner).
# Ein awk-Durchlauf: Zeilen werden gepuffert, der Index der letzten passenden
# Zeile gemerkt, in END bis dorthin ausgegeben. Kein Treffer oder keine Muster
# -> Eingabe unveraendert. Die Muster werden in Bash mit "|" verkettet und der
# fertige String per ENVIRON an awk gereicht (nicht per -v, das zerlegt
# Backslashes in ERE-Mustern). LC_ALL=C zwingt awk auf reines Byte-Zaehlen:
# unter einer UTF-8-Locale versucht dieselbe awk-Version, substr()
# zeichenweise zu dekodieren, und stolpert (towc-Fehler), sobald die
# Byte-fuer-Byte-Schleife unten eine Mehrbyte-Sequenz (z.B. ein Emoji) mitten
# durchtrennt.
tts_strip_trailing_sections() {
  local re="" p

  for p in "$@"; do
    if [ -z "$re" ]; then re="$p"; else re="$re|$p"; fi
  done

  if [ -z "$re" ]; then
    cat
    return 0
  fi

  LC_ALL=C TTS_STRIP_RE="$re" awk '
    # Markdown-Dekoration am Zeilenanfang abziehen, nur fuer den Vergleich —
    # die Ausgabe bleibt unangetastet. Reihenfolge wichtig: "**" zuerst weg,
    # danach der Rest der nicht-alphanumerischen Fuehrung (Emoji, Doppelpunkt,
    # verbleibende Sterne), sonst bliebe z.B. bei "## 🚀 **Text**" das Emoji
    # zwischen den Dekorationen stehen und die Ueberschrift matcht nicht mehr.
    function strip_deco(line,    s) {
      s = line
      sub(/^[[:space:]]+/, "", s)
      sub(/^#+/, "", s)
      sub(/^[[:space:]]+/, "", s)
      while (substr(s, 1, 2) == "**") { s = substr(s, 3) }
      while (length(s) > 0 && substr(s, 1, 1) !~ /^[A-Za-z0-9]$/) { s = substr(s, 2) }
      return s
    }
    BEGIN { re = ENVIRON["TTS_STRIP_RE"]; cutIdx = 0 }
    { lines[NR] = $0; if (strip_deco($0) ~ ("^(" re ")")) cutIdx = NR }
    END {
      limit = (cutIdx > 0) ? cutIdx - 1 : NR
      for (i = 1; i <= limit; i++) print lines[i]
    }
  '
}

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
  local line term repl broken empty_term

  # grep -c meldet Exit 1, wenn es nichts zählt — hier ist das der Normalfall
  broken=$(grep -vE '^[[:space:]]*(#|$)' "$rules" | grep -vc '=' || true)
  # Zeilen mit '=', aber leerem Begriff nach dem Trimmen (z.B. "  = Ersatz")
  # zählen als kaputt mit: das "continue" weiter unten läuft in einer Subshell
  # der while-Pipe und könnte einen Zähler nicht nach außen durchreichen.
  empty_term=$(grep -vE '^[[:space:]]*(#|$)' "$rules" | grep '=' \
    | awk -F'=' '{ t = $1; gsub(/^[ \t]+|[ \t]+$/, "", t); if (t == "") n++ } END { print n + 0 }')
  broken=$(( ${broken:-0} + ${empty_term:-0} ))
  if [ "$broken" -gt 0 ]; then
    echo "$(date): ${broken} Zeile(n) ohne gueltigen Begriff in $rules uebersprungen" >> "$log"
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
    echo "$(date): Keine anwendbare Regel in $rules, Text bleibt unveraendert" >> "$log"
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

# tts_synthesize <text> <wavfile> [logfile]
# Erst der TTS-Server, bei Ausfall ein lokal installiertes Piper.
# Rückgabe 0, wenn eine nicht-leere WAV-Datei entstanden ist.
tts_synthesize() {
  local text="$1" wavfile="$2" log="${3:-/dev/null}"
  local url="${TTS_URL:-$TTS_DEFAULT_URL}"
  local voice="${VOICE:-$TTS_DEFAULT_VOICE}"
  local speed="${SPEED:-1.0}"

  rm -f "$wavfile"

  # config.speed folgt Pipers length-scale (kleiner = schneller),
  # die OpenAI-kompatible API erwartet den Kehrwert
  local api_speed
  api_speed=$(awk -v s="$speed" 'BEGIN { printf "%.2f", (s > 0 ? 1 / s : 1) }')

  local payload http_code
  payload=$(jq -n --arg text "$text" --arg voice "$voice" --argjson speed "$api_speed" \
    '{model: "tts-1", input: $text, voice: $voice, response_format: "wav", speed: $speed}')

  http_code=$(curl -s --max-time 60 -o "$wavfile" -w '%{http_code}' \
    -X POST "$url" \
    -H 'Content-Type: application/json' \
    --data "$payload" 2>> "$log")

  if [ "$http_code" = "200" ] && [ -s "$wavfile" ]; then
    return 0
  fi

  echo "$(date): TTS-Server lieferte HTTP ${http_code:-?}, versuche lokales Piper" >> "$log"
  rm -f "$wavfile"

  local piper model
  piper="$(command -v piper || echo /Library/Frameworks/Python.framework/Versions/3.13/bin/piper)"
  model="${TTS_MODEL_PATH:-}"

  if [ -x "$piper" ] && [ -n "$model" ] && [ -f "$model" ]; then
    echo "$text" | "$piper" \
      --model "$model" \
      --length-scale "$speed" \
      --output-file "$wavfile" \
      2>> "$log"
    [ -s "$wavfile" ] && return 0
  else
    echo "$(date): Kein Fallback verfügbar (piper oder Modell fehlt)" >> "$log"
  fi

  return 1
}

# tts_play <wavfile> <pidfile>
# Spielt detached ab, damit die Wiedergabe das Hook-Ende überlebt,
# und räumt WAV + PID danach auf.
tts_play() {
  local wavfile="$1" pidfile="$2"
  local volume="${VOLUME:-1.0}"

  [ -s "$wavfile" ] || return 1

  # Nur die eigene Wiedergabe stoppen, nicht alle afplay-Prozesse
  if [ -f "$pidfile" ]; then
    kill "$(cat "$pidfile")" 2>/dev/null || true
  fi

  osascript -e "do shell script \"afplay -v $volume '$wavfile'; rm -f '$wavfile' '$pidfile'\"" \
    >/dev/null 2>&1 &
  echo $! > "$pidfile"
}
