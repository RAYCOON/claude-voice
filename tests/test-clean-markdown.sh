#!/usr/bin/env bash
# Prüft tts_clean_markdown: Listen verlieren ihre Marker, behalten aber eine
# Satzgrenze — sonst liest Piper Aufzählungen als atemlosen Fließtext ohne
# Pausen (gemessen: ~24 statt ~18 Zeichen/s).

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0

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

clean() { printf '%s\n' "$1" | tts_clean_markdown; }

echo "Fall 1: Listen-Item ohne Satzzeichen bekommt einen Punkt"
check "bullet-item" "Punkt eins." "$(clean "- Punkt eins")"
check "nummeriertes item" "Deckel nachziehen." "$(clean "3. Deckel nachziehen")"

echo
echo "Fall 2: Item mit Satzzeichen bleibt unveraendert"
check "endet mit punkt" "Alles gut." "$(clean "- Alles gut.")"
check "endet mit fragezeichen" "Passt das?" "$(clean "2. Passt das?")"

echo
echo "Fall 3: Ueberschrift mit Doppelpunkt bekommt keinen zweiten Schluss"
check "doppelpunkt bleibt" "Nächste Schritte:" "$(clean "**Nächste Schritte:**")"

echo
echo "Fall 4: Fliesstext ohne Listenmarker bleibt unangetastet"
check "fliesstext" "Kein Listenpunkt ohne Ende" "$(clean "Kein Listenpunkt ohne Ende")"

echo
echo "Fall 5: jede Zeile einer mehrzeiligen Liste endet als Satz"
IN="- eins
- zwei
1. drei"
EXPECTED="eins.
zwei.
drei."
check "mehrzeilige liste" "$EXPECTED" "$(clean "$IN")"

echo
if [ "$fails" -gt 0 ]; then
  echo "$fails Check(s) fehlgeschlagen"
  exit 1
fi
echo "Alle Checks bestanden"
