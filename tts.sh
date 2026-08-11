#!/usr/bin/env bash
# Claude Voice - gemeinsame TTS-Bausteine für speak.sh und replay.sh
# Wird gesourct, nicht direkt ausgeführt.

TTS_DEFAULT_URL="http://127.0.0.1:8881/v1/audio/speech"
TTS_DEFAULT_VOICE="de_DE-thorsten-high"

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
    | sed -E 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | sed 's/Claude/Klod/g' \
    | sed 's/[Kk]eycloak/Kii klooug/g'
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
