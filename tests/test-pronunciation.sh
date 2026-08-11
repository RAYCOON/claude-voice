#!/usr/bin/env bash
# Prüft das Aussprache-Lexikon: das Bauen und Anwenden der Regeln.
#
# Läuft gegen temporäre Regeldateien in einem eigenen Arbeitsverzeichnis;
# die pronunciation.txt des Repos bleibt unberührt.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
fails=0
trap 'rm -rf "$WORK"' EXIT

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

# apply <regeldatei> <text>
apply() { printf '%s' "$2" | tts_apply_pronunciation "$1" /dev/null; }

echo "Fall 1: einfache Ersetzung"
cat > "$WORK/simple.txt" <<'EOF'
Claude = Klod
EOF
check "Begriff ersetzt" "Klod hilft." "$(apply "$WORK/simple.txt" "Claude hilft.")"
check "Rest unberuehrt" "Nichts zu tun." "$(apply "$WORK/simple.txt" "Nichts zu tun.")"

echo
echo "Fall 2: laengerer Begriff gewinnt, unabhaengig von der Dateireihenfolge"
cat > "$WORK/order-a.txt" <<'EOF'
Slice  = Slaiß
Slices = Slaißis
EOF
cat > "$WORK/order-b.txt" <<'EOF'
Slices = Slaißis
Slice  = Slaiß
EOF
check "kurze Regel steht oben" "Slaißis und ein Slaiß" \
  "$(apply "$WORK/order-a.txt" "Slices und ein Slice")"
check "lange Regel steht oben" "Slaißis und ein Slaiß" \
  "$(apply "$WORK/order-b.txt" "Slices und ein Slice")"

echo
echo "Fall 3: sed-Sonderzeichen im Begriff"
cat > "$WORK/special-term.txt" <<'EOF'
AT&T  = Ah tee und tee
C/C++ = Zee plus plus
EOF
check "Ampersand im Begriff"    "Ah tee und tee ruft an." \
  "$(apply "$WORK/special-term.txt" "AT&T ruft an.")"
check "Schraegstrich im Begriff" "Zee plus plus ist alt." \
  "$(apply "$WORK/special-term.txt" "C/C++ ist alt.")"

echo
echo "Fall 4: sed-Sonderzeichen in der Ersetzung"
cat > "$WORK/special-repl.txt" <<'EOF'
Ampere = A&B
Pfad   = Schräg/Strich
EOF
check "Ampersand in der Ersetzung" "A&B fliesst." \
  "$(apply "$WORK/special-repl.txt" "Ampere fliesst.")"
check "Schraegstrich in der Ersetzung" "Schräg/Strich hier." \
  "$(apply "$WORK/special-repl.txt" "Pfad hier.")"

echo
echo "Fall 5: Kommentare, Leerzeilen und eine Zeile ohne ="
cat > "$WORK/messy.txt" <<'EOF'
# Kommentar

Claude = Klod
das ist keine Regel
Slice = Slaiß
EOF
check "uebrige Regeln greifen" "Klod mag Slaiß." \
  "$(apply "$WORK/messy.txt" "Claude mag Slice.")"

echo
echo "Fall 6: Regeldatei fehlt"
printf '%s' "Claude bleibt." | tts_apply_pronunciation "$WORK/gibtsnicht.txt" /dev/null > "$WORK/out.txt"
rc=$?
check "Text unveraendert" "Claude bleibt." "$(cat "$WORK/out.txt")"
check "Exit 0"            "0"              "$rc"

echo
echo "Fall 7: tts_clean_markdown raeumt nur Markdown ab, ersetzt keine Begriffe"
check "Begriff bleibt stehen" "Claude und Slice" \
  "$(printf '%s' '**Claude** und `Slice`' | tts_clean_markdown)"

echo
echo "Fall 8: speakable.sh"
out=$(PRONUNCIATION_FILE="$WORK/simple.txt" "$REPO/speakable.sh" "Claude hilft.")
check "Argument wird ersetzt" "Klod hilft." "$out"

out=$(printf '%s' "Claude hilft." | PRONUNCIATION_FILE="$WORK/simple.txt" "$REPO/speakable.sh")
check "stdin wird ersetzt" "Klod hilft." "$out"

PRONUNCIATION_FILE="$WORK/simple.txt" "$REPO/speakable.sh" "Claude hilft." > /dev/null
check "Exit 0 bei Text" "0" "$?"

printf '' | PRONUNCIATION_FILE="$WORK/simple.txt" "$REPO/speakable.sh" > /dev/null
check "Exit 0 bei leerer Eingabe" "0" "$?"

printf '' | PRONUNCIATION_FILE="$WORK/gibtsnicht.txt" "$REPO/speakable.sh" > /dev/null
check "Exit 0 ohne Regeldatei" "0" "$?"

echo
echo "Fall 9: Regeldatei ohne eine einzige Regel wird geloggt"
: > "$WORK/leer.txt"
: > "$WORK/log9.txt"
out=$(printf '%s' "Text bleibt." | tts_apply_pronunciation "$WORK/leer.txt" "$WORK/log9.txt")
check "Text unveraendert" "Text bleibt." "$out"
check "Logzeile geschrieben" "1" "$(grep -c "Keine anwendbare Regel" "$WORK/log9.txt")"

echo
echo "Fall 10: Zeile mit '=' aber leerem Begriff wird mitgezaehlt und geloggt"
cat > "$WORK/leerer-begriff.txt" <<'EOF'
   = Ersatz
EOF
: > "$WORK/log10.txt"
out=$(printf '%s' "Text bleibt." | tts_apply_pronunciation "$WORK/leerer-begriff.txt" "$WORK/log10.txt")
check "Text unveraendert" "Text bleibt." "$out"
check "kaputte Zeile gezaehlt" "1" "$(grep -c "ohne gueltigen Begriff" "$WORK/log10.txt")"

echo
if [ "$fails" -eq 0 ]; then
  echo "Alle Pruefungen bestanden."
else
  echo "$fails Pruefung(en) fehlgeschlagen."
fi
exit "$fails"
