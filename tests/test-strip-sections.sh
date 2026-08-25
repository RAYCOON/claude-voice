#!/usr/bin/env bash
# Prüft tts_strip_trailing_sections und die Anbindung von skip_sections in
# tts_load_config: der Fussbereich mit Vorschlags-Prompts ("Nächste
# Schritte" o.ä.) darf nicht als "letzter Absatz" vorgelesen werden.
#
# Läuft gegen temporäre Config-Dateien in einem eigenen Arbeitsverzeichnis;
# config.json des Repos bleibt unberührt (dort fehlt skip_sections bewusst,
# damit Fall 10 die eingebauten Defaults prüft).

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

DEFAULT_PATTERNS=("Nächste.*Schritte" "Next steps")

# strip <text> [pattern ...]
strip() {
  local text="$1"
  shift
  printf '%s' "$text" | tts_strip_trailing_sections "$@"
}

echo "Fall 1: fette Ueberschrift mit nummerierter Liste am Ende"
IN1=$'Erster Absatz.\n\nZweiter Absatz mit Inhalt.\n\n**Nächste sinnvolle Schritte**\n\n1. „Committe“\n2. „Pushe“'
EXPECTED1=$'Erster Absatz.\n\nZweiter Absatz mit Inhalt.'
check "fette Ueberschrift geschnitten" "$EXPECTED1" "$(strip "$IN1" "${DEFAULT_PATTERNS[@]}")"

echo
echo "Fall 2: ## Nächste Schritte"
IN2=$'Text davor.\n\n## Nächste Schritte\n\n- eins\n- zwei'
EXPECTED2="Text davor."
check "h2-Ueberschrift geschnitten" "$EXPECTED2" "$(strip "$IN2" "${DEFAULT_PATTERNS[@]}")"

echo
echo "Fall 3: Ueberschrift mit Emoji und Doppelpunkt"
IN3=$'Vorheriger Text.\n\n### 🚀 Nächste Schritte:\n\n1. Erstes\n2. Zweites'
EXPECTED3="Vorheriger Text."
check "Emoji-Ueberschrift geschnitten" "$EXPECTED3" "$(strip "$IN3" "${DEFAULT_PATTERNS[@]}")"

echo
echo "Fall 4: englisch Next steps"
IN4=$'Some content here.\n\n## Next steps\n\n1. Do X\n2. Do Y'
EXPECTED4="Some content here."
check "englische Ueberschrift geschnitten" "$EXPECTED4" "$(strip "$IN4" "${DEFAULT_PATTERNS[@]}")"

echo
echo "Fall 5: keine passende Ueberschrift -> unveraendert"
IN5=$'Nur ein Absatz ohne Fussbereich.\n\nUnd noch einer.'
check "unveraendert ohne Treffer" "$IN5" "$(strip "$IN5" "${DEFAULT_PATTERNS[@]}")"

echo
echo "Fall 6: Treffer mitten im Text UND am Ende -> nur der letzte wird geschnitten"
IN6=$'Absatz eins.\n\n## Nächste Schritte\n\nMitteltext, der erhalten bleibt.\n\n## Nächste Schritte\n\n1. Vorschlag eins\n2. Vorschlag zwei'
EXPECTED6=$'Absatz eins.\n\n## Nächste Schritte\n\nMitteltext, der erhalten bleibt.'
check "nur letzter Treffer schneidet" "$EXPECTED6" "$(strip "$IN6" "${DEFAULT_PATTERNS[@]}")"

echo
echo "Fall 7: Fliesstextsatz mit den Woertern, aber nicht am Zeilenanfang -> kein Treffer"
IN7=$'Absatz eins.\n\nFür Nächste Schritte siehe unten.\n\nAbsatz zwei.'
check "Fliesstext bleibt unangetastet" "$IN7" "$(strip "$IN7" "${DEFAULT_PATTERNS[@]}")"

echo
echo "Fall 8: keine Muster uebergeben -> unveraendert"
IN8=$'Text.\n\n## Nächste Schritte\n\n1. Punkt'
check "ohne Muster unveraendert" "$IN8" "$(strip "$IN8")"

echo
echo "Fall 9: tts_load_config laedt skip_sections"

cat > "$WORK/no-key.json" <<'EOF'
{
  "speed": 1.0
}
EOF
tts_load_config "$WORK/no-key.json"
check "ohne Key: Default-Anzahl" "2" "${#SKIP_SECTIONS[@]}"
check "ohne Key: Default 1"      "Nächste.*Schritte" "${SKIP_SECTIONS[0]}"
check "ohne Key: Default 2"      "Next steps"        "${SKIP_SECTIONS[1]}"

cat > "$WORK/empty-list.json" <<'EOF'
{
  "skip_sections": []
}
EOF
tts_load_config "$WORK/empty-list.json"
check "leere Liste schaltet Schnitt ab" "0" "${#SKIP_SECTIONS[@]}"

cat > "$WORK/custom.json" <<'EOF'
{
  "skip_sections": ["Foo"]
}
EOF
tts_load_config "$WORK/custom.json"
check "eigene Liste: Anzahl" "1"   "${#SKIP_SECTIONS[@]}"
check "eigene Liste: Wert"   "Foo" "${SKIP_SECTIONS[0]}"

tts_load_config "$WORK/gibtsnicht.json"
check "ohne Config: Default-Anzahl" "2" "${#SKIP_SECTIONS[@]}"
check "ohne Config: Default 1"      "Nächste.*Schritte" "${SKIP_SECTIONS[0]}"
check "ohne Config: Default 2"      "Next steps"        "${SKIP_SECTIONS[1]}"

echo
echo "Fall 10: Integration ueber speak.sh — Fussbereich faellt weg, lastmsg.txt bleibt vollstaendig"

TEST_CWD="/tmp/claude-voice-testprojekt-strip"
TEST_SESSION="strip-sections-test"
STUB="$(mktemp -d)"
FAKE_MODEL="$STUB/kein-modell.onnx"
LOG="$REPO/speak.log"

cat > "$STUB/curl" <<'EOF'
#!/usr/bin/env bash
echo -n "000"
exit 1
EOF
chmod +x "$STUB/curl"

cat > "$STUB/piper" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$STUB/piper"

cleanup10() {
  rm -rf "$STUB"
  rm -f "/tmp/claude-voice-cwd-$(echo -n "$TEST_CWD" | md5 -q)" \
        "/tmp/claude-voice-${TEST_SESSION}-lastmsg.txt" \
        "/tmp/claude-voice-${TEST_SESSION}.wav" \
        "/tmp/claude-voice-${TEST_SESSION}.pid"
}
trap 'cleanup10; rm -rf "$WORK"' EXIT

mark_log() { echo "--- TESTMARKE STRIP ---" >> "$LOG"; }
log_since_mark() {
  awk '/^--- TESTMARKE STRIP ---$/ { out = ""; next } { out = out $0 "\n" } END { printf "%s", out }' "$LOG"
}

FOOTER_MESSAGE=$'Erster Absatz mit Inhalt.\n\nDie Datei ist noch nicht committet.\n\n**Nächste sinnvolle Schritte**\n\n1. „Committe“\n2. „Pushe“'
HOOK_INPUT=$(jq -n --arg msg "$FOOTER_MESSAGE" --arg session "$TEST_SESSION" --arg cwd "$TEST_CWD" \
  '{session_id: $session, cwd: $cwd, stop_hook_active: false, last_assistant_message: $msg}')

mark_log
printf '%s' "$HOOK_INPUT" | PATH="$STUB:$PATH" TTS_MODEL_PATH="$FAKE_MODEL" "$REPO/speak.sh" > /dev/null 2>&1

check "Log-Zeile fuer den Schnitt" "1" \
  "$(log_since_mark | grep -c "Abschnitt ab Ueberschrift abgeschnitten")"

LASTMSG_FILE="/tmp/claude-voice-${TEST_SESSION}-lastmsg.txt"
check "lastmsg.txt enthaelt den vollen Fussbereich" "1" \
  "$(grep -c "Nächste sinnvolle Schritte" "$LASTMSG_FILE" 2>/dev/null)"

echo
if [ "$fails" -eq 0 ]; then
  echo "Alle Pruefungen bestanden."
else
  echo "$fails Pruefung(en) fehlgeschlagen."
fi
exit "$fails"
