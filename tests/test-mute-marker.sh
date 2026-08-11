#!/usr/bin/env bash
# Prüft die Verfallslogik des Stumm-Markers in speak.sh.
#
#   frisch aufgefrischter Marker -> Hook schweigt, Marker bleibt liegen
#   seit MUTE_TTL_MIN nicht aufgefrischt -> Hook spricht, Marker wird geräumt
#
# Der Test benutzt ein eigenes cwd, damit die Marker echter Projekte unberührt
# bleiben. Der curl-Stub schaltet nur den TTS-Server aus; steht auf der
# Maschine zusätzlich ein echtes Piper samt Modell in models/ bereit (siehe
# README-Fallback), griffe sonst genau dieser Fallback in tts.sh und spielte
# hörbar Audio ab — deshalb zusätzlich ein piper-Stub im PATH und ein
# TTS_MODEL_PATH, der ins Leere zeigt.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$REPO/speak.log"
TEST_CWD="/tmp/claude-voice-testprojekt"
TEST_SESSION="mute-marker-test"
MARKER="/tmp/claude-voice-mute-$(echo -n "$TEST_CWD" | md5 -q)"
STUB="$(mktemp -d)"
FAKE_MODEL="$STUB/kein-modell.onnx"
fails=0

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

cleanup() {
  rm -rf "$STUB"
  rm -f "$MARKER" \
        "/tmp/claude-voice-cwd-$(echo -n "$TEST_CWD" | md5 -q)" \
        "/tmp/claude-voice-${TEST_SESSION}-lastmsg.txt" \
        "/tmp/claude-voice-${TEST_SESSION}.wav" \
        "/tmp/claude-voice-${TEST_SESSION}.pid"
}
trap cleanup EXIT

mark_log() { echo "--- TESTMARKE ---" >> "$LOG"; }

log_since_mark() {
  awk '/^--- TESTMARKE ---$/ { out = ""; next } { out = out $0 "\n" } END { printf "%s", out }' "$LOG"
}

run_hook() {
  printf '{"session_id":"%s","cwd":"%s","stop_hook_active":false,"last_assistant_message":"Test."}' \
    "$TEST_SESSION" "$TEST_CWD" \
    | PATH="$STUB:$PATH" TTS_MODEL_PATH="$FAKE_MODEL" "$REPO/speak.sh" > /dev/null 2>&1
}

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $name"
  else
    echo "  FAIL: $name — erwartet '$expected', war '$actual'"
    fails=$((fails + 1))
  fi
}

verdict() {
  if log_since_mark | grep -q "Skipped (Sprachmodus aktiv)"; then echo "schweigt"; else echo "spricht"; fi
}

marker_state() { [ -f "$MARKER" ] && echo "liegt" || echo "geraeumt"; }

echo "Fall 1: Marker gerade aufgefrischt (Sprachmodus laeuft)"
touch "$MARKER"
mark_log
run_hook
check "Hook schweigt"        "schweigt" "$(verdict)"
check "Marker bleibt liegen" "liegt"    "$(marker_state)"

echo
echo "Fall 2: Marker seit 30 Minuten nicht aufgefrischt"
touch "$MARKER"
touch -A -003000 "$MARKER"
mark_log
run_hook
check "Hook spricht"         "spricht"  "$(verdict)"
check "Marker wird geraeumt" "geraeumt" "$(marker_state)"

echo
if [ "$fails" -eq 0 ]; then
  echo "Alle Pruefungen bestanden."
else
  echo "$fails Pruefung(en) fehlgeschlagen."
fi
exit "$fails"
