#!/usr/bin/env bash
# Prüft pronounce.sh — das Vorsprechen von Aussprache-Kandidaten.
#
# Ein curl-Stub verhindert, dass beim Prüfen Sprachausgabe anläuft; geprüft
# wird der Satz, den das Skript ins Log schreibt.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$REPO/speak.log"
STUB="$(mktemp -d)"
fails=0
trap 'rm -rf "$STUB"' EXIT

cat > "$STUB/curl" <<'EOF'
#!/usr/bin/env bash
echo -n "000"
exit 1
EOF
chmod +x "$STUB/curl"

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $name"
  else
    echo "  FAIL: $name — erwartet '$expected', war '$actual'"
    fails=$((fails + 1))
  fi
}

mark_log() { echo "--- TESTMARKE ---" >> "$LOG"; }

spoken_line() {
  awk '/^--- TESTMARKE ---$/ { out = ""; next }
       /pronounce\.sh — / { sub(/^.*pronounce\.sh — /, ""); out = $0 }
       END { printf "%s", out }' "$LOG"
}

echo "Fall 1: drei Kandidaten werden durchnummeriert"
mark_log
PATH="$STUB:$PATH" "$REPO/pronounce.sh" "Sleis" "Slaiß" "Sleiß" > /dev/null 2>&1
check "Satz aufgebaut" "Erstens: Sleis. Zweitens: Slaiß. Drittens: Sleiß." "$(spoken_line)"

echo
echo "Fall 2: mehr Kandidaten als Ordnungszahlen"
mark_log
PATH="$STUB:$PATH" "$REPO/pronounce.sh" a b c d e f g > /dev/null 2>&1
check "siebter faellt auf Nummer zurueck" \
  "Erstens: a. Zweitens: b. Drittens: c. Viertens: d. Fünftens: e. Sechstens: f. Nummer 7: g." \
  "$(spoken_line)"

echo
echo "Fall 3: ohne Kandidaten"
PATH="$STUB:$PATH" "$REPO/pronounce.sh" > /dev/null 2>&1
check "Exit 1" "1" "$?"

echo
echo "Fall 4: Kandidaten gehen roh in die Synthese"
mark_log
PATH="$STUB:$PATH" "$REPO/pronounce.sh" "Claude" > /dev/null 2>&1
check "keine Regel angewandt" "Erstens: Claude." "$(spoken_line)"

echo
if [ "$fails" -eq 0 ]; then
  echo "Alle Pruefungen bestanden."
else
  echo "$fails Pruefung(en) fehlgeschlagen."
fi
exit "$fails"
