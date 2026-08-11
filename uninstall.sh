#!/usr/bin/env bash
# Claude Voice - Uninstaller

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_SETTINGS="$(pwd)/.claude/settings.local.json"
GLOBAL_SETTINGS="$HOME/.claude/settings.json"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }

# shellcheck source=commands.sh
. "$SCRIPT_DIR/commands.sh"

echo ""
echo -e "${BOLD}Claude Voice Uninstaller${NC}"
echo "========================"
echo ""

# 1. Erkennen wo der Hook installiert ist
HAS_LOCAL=false
HAS_GLOBAL=false

jq -e '.hooks.Stop' "$LOCAL_SETTINGS"  &>/dev/null 2>&1 && HAS_LOCAL=true  || true
jq -e '.hooks.Stop' "$GLOBAL_SETTINGS" &>/dev/null 2>&1 && HAS_GLOBAL=true || true

echo -e "${BOLD}Erkannte Installationen:${NC}"
if [ "$HAS_LOCAL" = "true" ];  then echo -e "  ${GREEN}✓${NC} Lokal:  $LOCAL_SETTINGS"; fi
if [ "$HAS_GLOBAL" = "true" ]; then echo -e "  ${GREEN}✓${NC} Global: $GLOBAL_SETTINGS"; fi
if [ "$HAS_LOCAL" = "false" ] && [ "$HAS_GLOBAL" = "false" ]; then
  warn "Kein aktiver Hook gefunden."
fi
echo ""

# 2. Auswahl welche Installation entfernen
echo -e "${BOLD}Was soll entfernt werden?${NC}"
echo ""
echo "  [1] Lokal  — $(basename "$(pwd)") ($LOCAL_SETTINGS)"
echo "  [2] Global — alle Projekte ($GLOBAL_SETTINGS)"
echo "  [3] Beide"
echo ""

# Vorauswahl basierend auf erkannter Installation
DEFAULT="1"
if [ "$HAS_GLOBAL" = "true" ] && [ "$HAS_LOCAL" = "false" ]; then DEFAULT="2"; fi
if [ "$HAS_GLOBAL" = "true" ] && [ "$HAS_LOCAL" = "true" ];  then DEFAULT="3"; fi

read -rp "Auswahl [1/2/3] (Standard: $DEFAULT): " CHOICE
CHOICE="${CHOICE:-$DEFAULT}"

remove_hook() {
  local file="$1"
  if [ ! -f "$file" ]; then
    warn "Datei nicht vorhanden: $file"
    return
  fi
  if ! jq -e '.hooks.Stop' "$file" &>/dev/null; then
    warn "Kein Stop-Hook gefunden in: $file"
    return
  fi
  UPDATED=$(jq 'del(.hooks.Stop) | if .hooks == {} then del(.hooks) else . end' "$file")
  echo "$UPDATED" > "$file"
  ok "Hook entfernt aus: $file"
}

case "$CHOICE" in
  1) remove_hook "$LOCAL_SETTINGS" ;;
  2) remove_hook "$GLOBAL_SETTINGS" ;;
  3) remove_hook "$LOCAL_SETTINGS"; remove_hook "$GLOBAL_SETTINGS" ;;
  *) warn "Ungültige Auswahl — nichts geändert"; exit 1 ;;
esac

echo ""

# 3. Slash-Commands entfernen?
# Sicherungen (.bak) bleiben liegen — darin stecken eigene Anpassungen.
if [ -d "$SCRIPT_DIR/commands" ]; then
  echo -e "${BOLD}Slash-Commands entfernen?${NC}"
  echo ""
  read -rp "  /sprich und /read-msg entfernen? [j/N]: " RM_COMMANDS
  if [[ "$(echo "$RM_COMMANDS" | tr '[:upper:]' '[:lower:]')" == "j" ]]; then
    case "$CHOICE" in
      1) commands_uninstall "$SCRIPT_DIR/commands" "$(pwd)/.claude/commands" ;;
      2) commands_uninstall "$SCRIPT_DIR/commands" "$HOME/.claude/commands" ;;
      3) commands_uninstall "$SCRIPT_DIR/commands" "$(pwd)/.claude/commands"
         commands_uninstall "$SCRIPT_DIR/commands" "$HOME/.claude/commands" ;;
    esac
  else
    warn "Commands behalten"
  fi
  echo ""
fi

# 4. Fallback-Modelle entfernen?
# Der TTS-Server gehört nicht zu dieser Installation und bleibt unangetastet.
if [ -d "$SCRIPT_DIR/models" ] && [ -n "$(ls -A "$SCRIPT_DIR/models" 2>/dev/null)" ]; then
  echo -e "${BOLD}Fallback-Modelle entfernen?${NC}"
  echo ""
  MODELS_SIZE=$(du -sh "$SCRIPT_DIR/models" 2>/dev/null | cut -f1)
  read -rp "  Modelle entfernen ($MODELS_SIZE)? [j/N]: " RM_MODELS
  if [[ "$(echo "$RM_MODELS" | tr '[:upper:]' '[:lower:]')" == "j" ]]; then
    rm -rf "$SCRIPT_DIR/models"
    ok "Modelle entfernt"
  else
    warn "Modelle behalten"
  fi
fi

# 5. Temp-Dateien aufräumen
echo ""
rm -f /tmp/claude-voice-*.wav /tmp/claude-voice-*-lastmsg.txt /tmp/claude-voice-*-skip \
      /tmp/claude-voice-*.pid /tmp/claude-voice-cwd-* /tmp/claude-voice-mute-*
ok "Temp-Dateien entfernt"
rm -f "$SCRIPT_DIR/speak.log" && ok "Log entfernt" || true
pkill -x afplay 2>/dev/null && ok "Wiedergabe gestoppt" || true

echo ""
echo -e "${GREEN}Deinstallation abgeschlossen.${NC}"
echo "  Claude Code neu starten damit die Änderung wirksam wird."
echo ""
