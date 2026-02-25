#!/usr/bin/env bash
# Claude Voice - Installer
# Richtet Piper TTS + Thorsten-Voice als Claude Code Stop-Hook ein

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$SCRIPT_DIR/models"
CONFIG_FILE="$SCRIPT_DIR/config.json"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
fail() { echo -e "${RED}✗${NC} $*"; exit 1; }

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
    SETTINGS_FILE="$HOME/.claude/settings.json"
    SETTINGS_DIR="$HOME/.claude"
    ok "Installiere global: $SETTINGS_FILE"
    ;;
  *)
    INSTALL_MODE="local"
    SETTINGS_DIR="$(pwd)/.claude"
    SETTINGS_FILE="$SETTINGS_DIR/settings.local.json"
    ok "Installiere lokal: $SETTINGS_FILE"
    ;;
esac

echo ""

# 2. Prerequisites installieren
echo -e "${BOLD}Prüfe und installiere Prerequisites...${NC}"

# jq
if command -v jq &>/dev/null; then
  ok "jq bereits vorhanden ($(jq --version))"
else
  if command -v brew &>/dev/null; then
    echo "  Installiere jq via Homebrew..."
    brew install jq || fail "jq Installation fehlgeschlagen"
    ok "jq installiert"
  else
    fail "jq nicht gefunden und Homebrew nicht verfügbar. Installieren mit: brew install jq"
  fi
fi

# python3
if command -v python3 &>/dev/null; then
  ok "python3 bereits vorhanden ($(python3 --version))"
else
  if command -v brew &>/dev/null; then
    echo "  Installiere python3 via Homebrew..."
    brew install python3 || fail "python3 Installation fehlgeschlagen"
    ok "python3 installiert"
  else
    fail "python3 nicht gefunden. Installieren mit: brew install python3"
  fi
fi

# piper-tts und alle Abhängigkeiten
if python3 -c "import piper" &>/dev/null 2>&1; then
  PIPER_VER=$(pip3 show piper-tts 2>/dev/null | grep Version | cut -d' ' -f2)
  ok "piper-tts bereits vorhanden (v${PIPER_VER})"
else
  echo "  Installiere piper-tts via pip..."
  pip3 install piper-tts || fail "piper-tts Installation fehlgeschlagen"
  ok "piper-tts installiert"
fi

# Fehlende Abhängigkeiten nachinstallieren
for dep in pathvalidate onnxruntime; do
  if ! python3 -c "import $dep" &>/dev/null 2>&1; then
    echo "  Installiere fehlende Abhängigkeit: $dep..."
    pip3 install "$dep" || fail "$dep Installation fehlgeschlagen"
    ok "$dep installiert"
  else
    ok "$dep vorhanden"
  fi
done

# Piper-Binary finden
PIPER_BIN=$(python3 -c "import shutil; print(shutil.which('piper') or '')" 2>/dev/null)
if [ -z "$PIPER_BIN" ]; then
  for p in \
    "$(python3 -c 'import sys; print(sys.prefix)')/bin/piper" \
    "$HOME/.local/bin/piper" \
    "/usr/local/bin/piper"; do
    if [ -f "$p" ]; then
      PIPER_BIN="$p"
      break
    fi
  done
fi
if [ -z "$PIPER_BIN" ]; then
  fail "piper Binary nicht gefunden. Pfad in speak.sh manuell eintragen."
fi
ok "piper Binary: $PIPER_BIN"

# piper-Pfad in speak.sh und replay.sh eintragen
sed -i '' "s|PIPER=.*|PIPER=\"$PIPER_BIN\"|" "$SCRIPT_DIR/speak.sh"
sed -i '' "s|PIPER=.*|PIPER=\"$PIPER_BIN\"|" "$SCRIPT_DIR/replay.sh"

# 3. Modell bestimmen und herunterladen
MODEL_NAME="de_DE-thorsten-high"
if [ -f "$CONFIG_FILE" ]; then
  MODEL_NAME=$(jq -r '.model // "de_DE-thorsten-high"' "$CONFIG_FILE")
fi

ONNX_FILE="$MODELS_DIR/${MODEL_NAME}.onnx"
JSON_FILE="$MODELS_DIR/${MODEL_NAME}.onnx.json"

mkdir -p "$MODELS_DIR"

if [ -f "$ONNX_FILE" ] && [ -f "$JSON_FILE" ]; then
  ok "Modell bereits vorhanden: $MODEL_NAME"
else
  echo ""
  echo "Lade Modell herunter: $MODEL_NAME (~100MB)..."

  LANG=$(echo "$MODEL_NAME" | cut -d- -f1)
  LANG_SHORT=$(echo "$LANG" | cut -d_ -f1)
  SPEAKER=$(echo "$MODEL_NAME" | cut -d- -f2)
  QUALITY=$(echo "$MODEL_NAME" | cut -d- -f3)
  BASE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main/${LANG_SHORT}/${LANG}/${SPEAKER}/${QUALITY}"

  curl -L --progress-bar -o "$ONNX_FILE" "${BASE_URL}/${MODEL_NAME}.onnx" \
    || fail "Download fehlgeschlagen: ${MODEL_NAME}.onnx"
  curl -L -o "$JSON_FILE" "${BASE_URL}/${MODEL_NAME}.onnx.json" \
    || fail "Download fehlgeschlagen: ${MODEL_NAME}.onnx.json"

  ok "Modell heruntergeladen"
fi

# 4. speak.sh und replay.sh ausführbar machen
chmod +x "$SCRIPT_DIR/speak.sh"
ok "speak.sh ausführbar"
chmod +x "$SCRIPT_DIR/replay.sh"
ok "replay.sh ausführbar"

# 5. config.json anlegen falls nicht vorhanden
if [ ! -f "$CONFIG_FILE" ]; then
  jq 'del(to_entries[] | select(.key | startswith("_"))) | from_entries' \
    "$SCRIPT_DIR/config.defaults.json" > "$CONFIG_FILE" 2>/dev/null \
    || cp "$SCRIPT_DIR/config.defaults.json" "$CONFIG_FILE"
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

echo ""
echo -e "${GREEN}Installation abgeschlossen!${NC}"
echo ""
if [ "$INSTALL_MODE" = "global" ]; then
  echo "  Der Hook ist jetzt in allen Claude Code Projekten aktiv."
else
  echo "  Der Hook ist aktiv im Projekt: $(basename "$(pwd)")"
fi
echo ""
echo "  Nächste Schritte:"
echo "  1. Claude Code neu starten"
echo "  2. Einstellungen anpassen: $CONFIG_FILE"
echo "     speed  : Sprechgeschwindigkeit (0.5=schnell, 1.0=normal, 2.0=langsam)"
echo "     volume : Lautstärke (0.5=leise, 1.0=normal, 2.0=laut)"
echo ""
