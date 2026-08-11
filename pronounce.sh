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
