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
