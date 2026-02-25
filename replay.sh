#!/usr/bin/env bash
# Claude Voice - Replay letzter Antwort
# Aufruf: replay.sh <session-id>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
LOG="$SCRIPT_DIR/speak.log"

PROJECT_PATH="${1:?Projekt-Pfad als Argument erforderlich}"
CWD_MAP="/tmp/claude-voice-cwd-$(echo -n "$PROJECT_PATH" | md5 -q)"
SESSION_ID=$(cat "$CWD_MAP" 2>/dev/null)
if [ -z "$SESSION_ID" ]; then
  echo "Keine Session für Projekt '${PROJECT_PATH}' gefunden."
  exit 1
fi

LASTMSG_FILE="/tmp/claude-voice-${SESSION_ID}-lastmsg.txt"
SKIP_MARKER="/tmp/claude-voice-${SESSION_ID}-skip"
WAVFILE="/tmp/claude-voice-${SESSION_ID}.wav"
PIDFILE="/tmp/claude-voice-${SESSION_ID}.pid"

# Skip-Marker setzen, damit der Stop-Hook die nächste Antwort überspringt
touch "$SKIP_MARKER"

# Nachricht lesen
if [ ! -f "$LASTMSG_FILE" ]; then
  echo "Keine gespeicherte Nachricht für Session '${SESSION_ID}' gefunden."
  rm -f "$SKIP_MARKER"
  exit 1
fi

MESSAGE=$(cat "$LASTMSG_FILE")

if [ -z "$MESSAGE" ]; then
  echo "Gespeicherte Nachricht ist leer."
  rm -f "$SKIP_MARKER"
  exit 1
fi

# Config lesen (mit Fallback-Defaults)
if [ -f "$CONFIG" ]; then
  SPEED=$(jq -r '.speed // 1.0'     "$CONFIG")
  VOLUME=$(jq -r '.volume // 1.0'   "$CONFIG")
  MODEL_NAME=$(jq -r '.model // "de_DE-thorsten-high"' "$CONFIG")
else
  SPEED=1.0
  VOLUME=1.0
  MODEL_NAME="de_DE-thorsten-high"
fi

MODEL="$SCRIPT_DIR/models/${MODEL_NAME}.onnx"
PIPER="/Library/Frameworks/Python.framework/Versions/3.13/bin/piper"

if [ ! -f "$MODEL" ]; then
  echo "Modell nicht gefunden: $MODEL"
  rm -f "$SKIP_MARKER"
  exit 1
fi

# Markdown bereinigen — gleiche Logik wie speak.sh, mit Inline-Code-Fix
# Code-Blöcke komplett entfernen (mehrzeilig), Inline-Code-Inhalt behalten
CLEAN_TEXT=$(echo "$MESSAGE" \
  | sed -E 's/```[^`]*```//g' \
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
  | sed 's/Claude/Klod/g')

if [ -z "$CLEAN_TEXT" ]; then
  echo "Nach Bereinigung kein Text übrig."
  rm -f "$SKIP_MARKER"
  exit 1
fi

echo "$(date): replay.sh — Session ${SESSION_ID}, Länge: ${#CLEAN_TEXT} Zeichen" >> "$LOG"

# Laufende Wiedergabe dieser Session stoppen
if [ -f "$PIDFILE" ]; then
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
fi

# WAV via Piper erzeugen
echo "$CLEAN_TEXT" | "$PIPER" \
  --model "$MODEL" \
  --length-scale "$SPEED" \
  --volume "$VOLUME" \
  --output-file "$WAVFILE" \
  2>> "$LOG"

if [ -f "$WAVFILE" ] && [ -s "$WAVFILE" ]; then
  osascript -e "do shell script \"afplay '$WAVFILE'; rm -f '$WAVFILE' '$PIDFILE'\"" >/dev/null 2>&1 &
  echo $! > "$PIDFILE"
  echo "Vorlesen gestartet."
else
  echo "Fehler: WAV-Datei konnte nicht erzeugt werden."
  rm -f "$SKIP_MARKER"
  exit 1
fi

exit 0
