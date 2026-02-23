#!/usr/bin/env bash
# Claude Voice - TTS via Piper + Thorsten-Voice
# Stop-Hook: Liest letzten Absatz der Antwort vor

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
LOG="$SCRIPT_DIR/speak.log"

# Config lesen (mit Fallback-Defaults)
if [ -f "$CONFIG" ]; then
  SPEED=$(jq -r '.speed // 1.0'     "$CONFIG")
  VOLUME=$(jq -r '.volume // 1.0'   "$CONFIG")
  MODEL_NAME=$(jq -r '.model // "de_DE-thorsten-high"' "$CONFIG")
  PARAGRAPH=$(jq -r '.paragraph // "last"' "$CONFIG")
else
  SPEED=1.0
  VOLUME=1.0
  MODEL_NAME="de_DE-thorsten-high"
  PARAGRAPH="last"
fi

MODEL="$SCRIPT_DIR/models/${MODEL_NAME}.onnx"
PIPER="/Library/Frameworks/Python.framework/Versions/3.13/bin/piper"

# JSON von stdin lesen
INPUT=$(cat)
echo "$(date): Hook triggered, input keys: $(echo "$INPUT" | jq -r 'keys | join(", ")' 2>/dev/null)" >> "$LOG"
tail -100 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"

# Session-ID für Isolation paralleler Sessions
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"')

# Endlosschleifen verhindern
HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# Modell muss vorhanden sein
if [ ! -f "$MODEL" ]; then
  echo "$(date): Modell nicht gefunden: $MODEL" >> "$LOG"
  exit 0
fi

# Letzte Assistenten-Nachricht extrahieren
MESSAGE=$(echo "$INPUT" | jq -r '.last_assistant_message // ""')

if [ -z "$MESSAGE" ]; then
  exit 0
fi

# Absatz(e) extrahieren
if [ "$PARAGRAPH" = "all" ]; then
  SPEAK_TEXT="$MESSAGE"
else
  # Letzten nicht-leeren Absatz
  SPEAK_TEXT=$(echo "$MESSAGE" | awk '
    /^[[:space:]]*$/ { if (para != "") { last = para; para = "" } next }
    { para = (para == "") ? $0 : para "\n" $0 }
    END { if (para != "") last = para; print last }
  ')
fi

if [ -z "$SPEAK_TEXT" ]; then
  exit 0
fi

# Markdown bereinigen (macOS sed mit -E für extended regex)
CLEAN_TEXT=$(echo "$SPEAK_TEXT" \
  | sed -E 's/```[^`]*```//g' \
  | sed -E 's/`[^`]*`//g' \
  | sed -E 's/\*\*([^*]*)\*\*/\1/g' \
  | sed -E 's/\*([^*]*)\*/\1/g' \
  | sed -E 's/^#{1,6}[[:space:]]*//' \
  | sed -E 's/\[([^]]*)\]\([^)]*\)/\1/g' \
  | sed -E 's/!\[([^]]*)\]\([^)]*\)//' \
  | sed -E 's/^[[:space:]]*[-*+][[:space:]]*//' \
  | sed -E 's/^[[:space:]]*[0-9]+\.[[:space:]]*//' \
  | tr -s ' ' \
  | sed -E 's/^[[:space:]]*//;s/[[:space:]]*$//' \
  | sed 's/Claude/Klod/g')

if [ -z "$CLEAN_TEXT" ]; then
  exit 0
fi

# Projektname aus Hook-JSON (cwd-Feld zuverlässiger als $PWD)
PROJECT_NAME=$(echo "$INPUT" | jq -r '.cwd // ""' | xargs basename)
FINAL_TEXT="Neues von Projekt ${PROJECT_NAME}. ${CLEAN_TEXT}"
# echo "$(date): PROJECT=${PROJECT_NAME}" >> "$LOG"

# Session-isolierte Dateipfade
WAVFILE="/tmp/claude-voice-${SESSION_ID}.wav"
PIDFILE="/tmp/claude-voice-${SESSION_ID}.pid"

# Piper synchron (WAV erzeugen), dann afplay detached abspielen
echo "$FINAL_TEXT" | "$PIPER" \
  --model "$MODEL" \
  --length-scale "$SPEED" \
  --volume "$VOLUME" \
  --output-file "$WAVFILE" \
  2>> "$LOG"

if [ -f "$WAVFILE" ] && [ -s "$WAVFILE" ]; then
  # Nur eigene Session stoppen, nicht alle afplay-Prozesse
  if [ -f "$PIDFILE" ]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
  fi
  # osascript spawnt einen echten unabhängigen Prozess (überlebt Hook-Exit)
  # Nach Wiedergabe WAV + PID aufräumen
  osascript -e "do shell script \"afplay '$WAVFILE'; rm -f '$WAVFILE' '$PIDFILE'\"" >/dev/null 2>&1 &
  echo $! > "$PIDFILE"
fi

exit 0
