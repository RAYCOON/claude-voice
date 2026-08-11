#!/usr/bin/env bash
# Claude Voice - TTS via Thorsten-Voice
# Stop-Hook: Liest letzten Absatz der Antwort vor
# Primär über den TTS-Server der voicemode-Installation (OpenAI-kompatibel),
# als Fallback über ein lokal installiertes Piper-Binary.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
LOG="$SCRIPT_DIR/speak.log"

# shellcheck source=tts.sh
. "$SCRIPT_DIR/tts.sh"

tts_load_config "$CONFIG"
TTS_MODEL_PATH="$SCRIPT_DIR/models/${MODEL_NAME}.onnx"

# JSON von stdin lesen
INPUT=$(cat)
echo "$(date): Hook triggered, input keys: $(echo "$INPUT" | jq -r 'keys | join(", ")' 2>/dev/null)" >> "$LOG"
tail -100 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"

# Session-ID für Isolation paralleler Sessions
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"')

# cwd→Session-ID Mapping für /read-msg persistieren
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
if [ -n "$CWD" ]; then
  echo "$SESSION_ID" > "/tmp/claude-voice-cwd-$(echo -n "$CWD" | md5 -q)"
fi

# Endlosschleifen verhindern
HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# Session-spezifischen Skip-Marker prüfen (gesetzt von replay.sh)
SKIP_MARKER="/tmp/claude-voice-${SESSION_ID}-skip"
if [ -f "$SKIP_MARKER" ]; then
  rm -f "$SKIP_MARKER"
  echo "$(date): Skipped (replay marker)" >> "$LOG"
  exit 0
fi

# Stumm bleiben, solange der Sprachmodus läuft — sonst käme jede Antwort
# doppelt: einmal von voicemode, einmal von hier. Den Marker setzt /sprich
# beim Eintritt und löscht ihn bei "Feierabend". Bleibt er nach einem
# Session-Abbruch liegen, verfällt er über die voicemode-Aktivität.
if [ -n "$CWD" ]; then
  MUTE_MARKER="/tmp/claude-voice-mute-$(echo -n "$CWD" | md5 -q)"
  if [ -f "$MUTE_MARKER" ]; then
    EVENTS=$(ls -t "$HOME"/.voicemode/logs/events/*.jsonl 2>/dev/null | head -1)
    if [ -n "$EVENTS" ] && [ -n "$(find "$EVENTS" -mmin -30 2>/dev/null)" ]; then
      echo "$(date): Skipped (Sprachmodus aktiv)" >> "$LOG"
      exit 0
    fi
    rm -f "$MUTE_MARKER"
    echo "$(date): Stumm-Marker verfallen, keine voicemode-Aktivität" >> "$LOG"
  fi
fi

# Letzte Assistenten-Nachricht extrahieren
MESSAGE=$(echo "$INPUT" | jq -r '.last_assistant_message // ""')

if [ -z "$MESSAGE" ]; then
  exit 0
fi

# Volle Nachricht für /read-msg persistieren
echo "$MESSAGE" > "/tmp/claude-voice-${SESSION_ID}-lastmsg.txt"

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

CLEAN_TEXT=$(echo "$SPEAK_TEXT" | tts_clean_markdown)

if [ -z "$CLEAN_TEXT" ]; then
  exit 0
fi

# Projektname aus Hook-JSON (cwd-Feld zuverlässiger als $PWD)
PROJECT_NAME=$(echo "$INPUT" | jq -r '.cwd // ""' | xargs basename)
FINAL_TEXT="Neues von Projekt ${PROJECT_NAME}. ${CLEAN_TEXT}"

# Session-isolierte Dateipfade
WAVFILE="/tmp/claude-voice-${SESSION_ID}.wav"
PIDFILE="/tmp/claude-voice-${SESSION_ID}.pid"

if tts_synthesize "$FINAL_TEXT" "$WAVFILE" "$LOG"; then
  tts_play "$WAVFILE" "$PIDFILE"
fi

exit 0
