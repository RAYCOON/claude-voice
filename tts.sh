#!/usr/bin/env bash
# Claude Voice - gemeinsame TTS-Bausteine für speak.sh und replay.sh
# Wird gesourct, nicht direkt ausgeführt.

TTS_DEFAULT_URL="http://127.0.0.1:8881/v1/audio/speech"
TTS_DEFAULT_VOICE="de_DE-thorsten-high"

# Die Regeldatei liegt neben tts.sh, nicht im Arbeitsverzeichnis — beim
# Hook-Aufruf ist das cwd ein fremdes Projekt. Eine von außen gesetzte
# Variable gewinnt, damit Tests gegen eigene Regeldateien laufen können.
TTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRONUNCIATION_FILE="${PRONUNCIATION_FILE:-$TTS_DIR/pronunciation.txt}"

# tts_load_config <config.json>
# Setzt SPEED, VOLUME, PARAGRAPH, TTS_URL, VOICE, MODEL_NAME
tts_load_config() {
  local config="$1"
  if [ -f "$config" ]; then
    SPEED=$(jq -r '.speed // 1.0' "$config")
    VOLUME=$(jq -r '.volume // 1.0' "$config")
    PARAGRAPH=$(jq -r '.paragraph // "last"' "$config")
    TTS_URL=$(jq -r ".tts_url // \"$TTS_DEFAULT_URL\"" "$config")
    VOICE=$(jq -r ".voice // \"$TTS_DEFAULT_VOICE\"" "$config")
    MODEL_NAME=$(jq -r ".model // \"$TTS_DEFAULT_VOICE\"" "$config")
  else
    SPEED=1.0
    VOLUME=1.0
    PARAGRAPH="last"
    TTS_URL="$TTS_DEFAULT_URL"
    VOICE="$TTS_DEFAULT_VOICE"
    MODEL_NAME="$TTS_DEFAULT_VOICE"
  fi
}

# tts_clean_markdown — liest stdin, schreibt sprechbaren Text nach stdout
# Code-Blöcke fliegen raus, Inline-Code behält seinen Inhalt.
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
    | sed -E 's/^[[:space:]]*[-*+][[:space:]]*//' \
    | sed -E 's/^[[:space:]]*[0-9]+\.[[:space:]]*//' \
    | tr -s ' ' \
    | sed -E 's/^[[:space:]]*//;s/[[:space:]]*$//'
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
  local line term repl broken

  # grep -c meldet Exit 1, wenn es nichts zählt — hier ist das der Normalfall
  broken=$(grep -vE '^[[:space:]]*(#|$)' "$rules" | grep -vc '=' || true)
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
