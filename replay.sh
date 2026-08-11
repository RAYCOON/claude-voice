#!/usr/bin/env bash
# Claude Voice - Replay letzter Antwort
# Aufruf: replay.sh <session-id>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
LOG="$SCRIPT_DIR/speak.log"

# shellcheck source=tts.sh
. "$SCRIPT_DIR/tts.sh"

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

tts_load_config "$CONFIG"
TTS_MODEL_PATH="$SCRIPT_DIR/models/${MODEL_NAME}.onnx"

CLEAN_TEXT=$(echo "$MESSAGE" | tts_clean_markdown)

if [ -z "$CLEAN_TEXT" ]; then
  echo "Nach Bereinigung kein Text übrig."
  rm -f "$SKIP_MARKER"
  exit 1
fi

echo "$(date): replay.sh — Session ${SESSION_ID}, Länge: ${#CLEAN_TEXT} Zeichen" >> "$LOG"

if tts_synthesize "$CLEAN_TEXT" "$WAVFILE" "$LOG"; then
  tts_play "$WAVFILE" "$PIDFILE"
  echo "Vorlesen gestartet."
else
  echo "Fehler: Sprachausgabe konnte nicht erzeugt werden — Details in speak.log."
  rm -f "$SKIP_MARKER"
  exit 1
fi

exit 0
