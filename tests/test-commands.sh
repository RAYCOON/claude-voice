#!/usr/bin/env bash
# Prüft commands.sh — das Ausrollen der Slash-Commands.
#
# Die vier Zustände am Ziel (fehlt / identisch / abweichend+ja / abweichend+nein),
# die Ersetzung des Pfad-Platzhalters und das Abräumen. Läuft gegen temporäre
# Verzeichnisse; das Profil des Nutzers bleibt unberührt.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAKE_REPO="/opt/irgendwo/claude-voice"
fails=0

# shellcheck source=../commands.sh
. "$REPO/commands.sh" || { echo "commands.sh nicht sourcebar"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SRC="$WORK/src"
mkdir -p "$SRC"
printf 'Rufe {{CLAUDE_VOICE_DIR}}/replay.sh auf.\n' > "$SRC/probe.md"

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $name"
  else
    echo "  FAIL: $name — erwartet '$expected', war '$actual'"
    fails=$((fails + 1))
  fi
}

fresh_dst() { local d="$WORK/dst-$1"; rm -rf "$d"; mkdir -p "$d"; echo "$d"; }
state()     { [ -f "$1" ] && cat "$1" || echo "<fehlt>"; }
bak_state() { [ -f "$1.bak" ] && cat "$1.bak" || echo "<kein-bak>"; }

echo "Fall 1: Ziel fehlt — Datei wird angelegt, Platzhalter ersetzt"
DST=$(fresh_dst 1)
commands_install "$SRC" "$DST" "$FAKE_REPO" > /dev/null 2>&1
check "Datei angelegt" "Rufe $FAKE_REPO/replay.sh auf." "$(state "$DST/probe.md")"
check "kein Backup"    "<kein-bak>"                     "$(bak_state "$DST/probe.md")"

echo
echo "Fall 2: Ziel identisch — nichts passiert"
DST=$(fresh_dst 2)
printf 'Rufe %s/replay.sh auf.\n' "$FAKE_REPO" > "$DST/probe.md"
commands_install "$SRC" "$DST" "$FAKE_REPO" > /dev/null 2>&1
check "Inhalt unverändert" "Rufe $FAKE_REPO/replay.sh auf." "$(state "$DST/probe.md")"
check "kein Backup"        "<kein-bak>"                     "$(bak_state "$DST/probe.md")"

echo
echo "Fall 3: Ziel weicht ab, Antwort ja — überschrieben mit Sicherung"
DST=$(fresh_dst 3)
printf 'Lokal angepasst.\n' > "$DST/probe.md"
COMMANDS_ASSUME=j commands_install "$SRC" "$DST" "$FAKE_REPO" > /dev/null 2>&1
check "überschrieben"      "Rufe $FAKE_REPO/replay.sh auf." "$(state "$DST/probe.md")"
check "Sicherung angelegt" "Lokal angepasst."               "$(bak_state "$DST/probe.md")"

echo
echo "Fall 4: Ziel weicht ab, Antwort nein — bleibt unangetastet"
DST=$(fresh_dst 4)
printf 'Lokal angepasst.\n' > "$DST/probe.md"
COMMANDS_ASSUME=n commands_install "$SRC" "$DST" "$FAKE_REPO" > /dev/null 2>&1
check "Inhalt unverändert" "Lokal angepasst." "$(state "$DST/probe.md")"
check "kein Backup"        "<kein-bak>"       "$(bak_state "$DST/probe.md")"

echo
echo "Fall 5: echte commands/ des Repos — kein Platzhalter bleibt zurück"
DST=$(fresh_dst 5)
if [ -d "$REPO/commands" ]; then
  COMMANDS_ASSUME=n commands_install "$REPO/commands" "$DST" "$FAKE_REPO" > /dev/null 2>&1
  leftover=$(grep -rl "CLAUDE_VOICE_DIR" "$DST" 2>/dev/null | wc -l | tr -d ' ')
  check "keine Platzhalter uebrig" "0" "$leftover"
  installed=$(find "$DST" -name '*.md' | wc -l | tr -d ' ')
  check "beide Commands installiert" "2" "$installed"
else
  echo "  FAIL: $REPO/commands fehlt"
  fails=$((fails + 1))
fi

echo
echo "Fall 6: Deinstallation entfernt die Commands, behaelt Sicherungen"
DST=$(fresh_dst 6)
commands_install "$SRC" "$DST" "$FAKE_REPO" > /dev/null 2>&1
printf 'alte Fassung\n' > "$DST/probe.md.bak"
commands_uninstall "$SRC" "$DST" > /dev/null 2>&1
check "Command entfernt"   "<fehlt>"      "$(state "$DST/probe.md")"
check "Sicherung behalten" "alte Fassung" "$(bak_state "$DST/probe.md")"

echo
if [ "$fails" -eq 0 ]; then
  echo "Alle Pruefungen bestanden."
else
  echo "$fails Pruefung(en) fehlgeschlagen."
fi
exit "$fails"
