#!/usr/bin/env bash
# Claude Voice - Installer
# Registriert speak.sh als Claude Code Stop-Hook.
# Gesprochen wird über einen OpenAI-kompatiblen TTS-Server (Standard: die
# Thorsten-Stimme der voicemode-Installation auf Port 8881).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"
DEFAULTS_FILE="$SCRIPT_DIR/config.defaults.json"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
fail() { echo -e "${RED}✗${NC} $*"; exit 1; }

# shellcheck source=commands.sh
. "$SCRIPT_DIR/commands.sh"

echo ""
echo -e "${BOLD}Claude Voice Installer${NC}"
echo "======================"
echo ""

# 1. Installationsart wählen
echo -e "${BOLD}Wo soll der Hook installiert werden?${NC}"
echo ""
echo "  [1] Lokal  — nur im aktuellen Projekt ($(basename "$PWD"))"
echo "  [2] Global — in allen Claude Code Projekten (~/.claude/settings.json)"
echo ""
read -rp "Auswahl [1/2]: " INSTALL_CHOICE

case "$INSTALL_CHOICE" in
  2)
    INSTALL_MODE="global"
    SETTINGS_DIR="$HOME/.claude"
    SETTINGS_FILE="$SETTINGS_DIR/settings.json"
    ok "Installiere global: $SETTINGS_FILE"
    ;;
  *)
    INSTALL_MODE="local"
    SETTINGS_DIR="$(pwd)/.claude"
    SETTINGS_FILE="$SETTINGS_DIR/settings.local.json"
    ok "Installiere lokal: $SETTINGS_FILE"
    ;;
esac

# Die Commands folgen der Hook-Wahl: sonst stünde ein lokaler Hook neben
# global sichtbaren Commands.
COMMANDS_TARGET="$SETTINGS_DIR/commands"

echo ""

# 2. Abhängigkeiten prüfen
echo -e "${BOLD}Prüfe Abhängigkeiten...${NC}"

if command -v jq &>/dev/null; then
  ok "jq vorhanden ($(jq --version))"
else
  if command -v brew &>/dev/null; then
    echo "  Installiere jq via Homebrew..."
    brew install jq || fail "jq Installation fehlgeschlagen"
    ok "jq installiert"
  else
    fail "jq nicht gefunden und Homebrew nicht verfügbar. Installieren mit: brew install jq"
  fi
fi

command -v curl &>/dev/null || fail "curl nicht gefunden"
ok "curl vorhanden"

command -v afplay &>/dev/null || fail "afplay nicht gefunden — dieses Setup läuft nur auf macOS"
ok "afplay vorhanden"

# 3. TTS-Server prüfen (Warnung, kein Abbruch — er kann später starten)
TTS_URL=$(jq -r '.tts_url // "http://127.0.0.1:8881/v1/audio/speech"' "$DEFAULTS_FILE")
if [ -f "$CONFIG_FILE" ]; then
  TTS_URL=$(jq -r --arg fallback "$TTS_URL" '.tts_url // $fallback' "$CONFIG_FILE")
fi
VOICES_URL="${TTS_URL%/audio/speech}/audio/voices"

echo ""
echo -e "${BOLD}Prüfe TTS-Server...${NC}"
if VOICES=$(curl -s --max-time 5 "$VOICES_URL" 2>/dev/null) && [ -n "$VOICES" ]; then
  ok "TTS-Server erreichbar: $TTS_URL"
  echo "  Stimmen: $(echo "$VOICES" | jq -r '.voices | join(", ")' 2>/dev/null || echo "$VOICES")"
else
  warn "TTS-Server nicht erreichbar: $TTS_URL"
  warn "Der Hook wird erst sprechen, wenn der Server läuft (z.B. via voicemode)."
  warn "Alternativ ein Piper-Modell nach models/ legen — das greift als Fallback."
fi

# 4. Scripte ausführbar machen
echo ""
chmod +x "$SCRIPT_DIR/speak.sh" "$SCRIPT_DIR/replay.sh"
ok "speak.sh und replay.sh ausführbar"

# 5. config.json anlegen falls nicht vorhanden
if [ ! -f "$CONFIG_FILE" ]; then
  jq 'del(to_entries[] | select(.key | startswith("_"))) | from_entries' \
    "$DEFAULTS_FILE" > "$CONFIG_FILE" 2>/dev/null \
    || cp "$DEFAULTS_FILE" "$CONFIG_FILE"
  ok "config.json angelegt (aus Defaults)"
else
  ok "config.json bereits vorhanden"
fi

# 6. Hook eintragen
mkdir -p "$SETTINGS_DIR"

write_hook() {
  local file="$1"
  local cmd="$SCRIPT_DIR/speak.sh"

  if [ ! -f "$file" ]; then
    cat > "$file" <<EOF
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$cmd"
          }
        ]
      }
    ]
  }
}
EOF
    ok "Hook-Datei angelegt: $file"
  else
    if jq -e '.hooks.Stop' "$file" &>/dev/null; then
      warn "Stop-Hook bereits eingetragen — übersprungen: $file"
    else
      UPDATED=$(jq --arg cmd "$cmd" \
        '.hooks = (.hooks // {}) | .hooks.Stop = [{"hooks": [{"type": "command", "command": $cmd}]}]' \
        "$file")
      echo "$UPDATED" > "$file"
      ok "Hook eingetragen: $file"
    fi
  fi
}

write_hook "$SETTINGS_FILE"

# 7. Slash-Commands ausrollen
echo ""
echo -e "${BOLD}Installiere Slash-Commands...${NC}"
commands_install "$SCRIPT_DIR/commands" "$COMMANDS_TARGET" "$SCRIPT_DIR"

echo ""
echo -e "${GREEN}Installation abgeschlossen!${NC}"
echo ""
if [ "$INSTALL_MODE" = "global" ]; then
  echo "  Der Hook ist jetzt in allen Claude Code Projekten aktiv."
else
  echo "  Der Hook ist aktiv im Projekt: $(basename "$(pwd)")"
fi
echo ""
echo "  Commands: /sprich (Sprachmodus), /read-msg (letzte Antwort vorlesen)"
echo ""
echo "  Nächste Schritte:"
echo "  1. Claude Code neu starten"
echo "  2. Einstellungen anpassen: $CONFIG_FILE"
echo "     speed  : Sprechgeschwindigkeit (0.5=schnell, 1.0=normal, 2.0=langsam)"
echo "     volume : Lautstärke (0.5=leise, 1.0=normal, 2.0=laut)"
echo "     voice  : Stimme des TTS-Servers"
echo ""
