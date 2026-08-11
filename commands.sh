#!/usr/bin/env bash
# Claude Voice - Ausrollen der Slash-Commands
# Wird gesourct, nicht direkt ausgeführt.
#
# Die Commands sind die zweite Hälfte des Vorlese-Vertrags: /sprich setzt den
# Stumm-Marker und frischt ihn auf, speak.sh wertet ihn aus. Läuft beides
# auseinander, verstummt der Hook oder redet doppelt. Deshalb liegen die
# Commands im Repo und werden mitinstalliert, statt von Hand im Profil zu leben.

COMMANDS_PLACEHOLDER="{{CLAUDE_VOICE_DIR}}"

# Die Ausgabe-Helfer der Installer mitbenutzen, wenn vorhanden
if ! declare -F ok >/dev/null 2>&1; then
  ok() { printf '✓ %s\n' "$*"; }
fi
if ! declare -F warn >/dev/null 2>&1; then
  warn() { printf '! %s\n' "$*"; }
fi

# commands_install <quell-dir> <ziel-dir> <repo-dir>
# Rollt jede *.md aus quell-dir nach ziel-dir aus und ersetzt dabei den
# Pfad-Platzhalter durch repo-dir. Weicht eine vorhandene Datei ab, entscheidet
# der Nutzer nach einem Diff; COMMANDS_ASSUME (j/n) beantwortet die Frage vorab.
commands_install() {
  local src="$1" dst="$2" repo="$3"
  local file name target rendered answer repo_escaped

  if [ ! -d "$src" ]; then
    warn "Kein Command-Verzeichnis: $src"
    return 1
  fi

  mkdir -p "$dst"

  # & und | hätten in der sed-Ersetzung Sonderbedeutung
  repo_escaped=$(printf '%s' "$repo" | sed 's/[&|\\]/\\&/g')

  for file in "$src"/*.md; do
    [ -f "$file" ] || continue
    name=$(basename "$file")
    target="$dst/$name"
    rendered="$(mktemp)"

    sed "s|$COMMANDS_PLACEHOLDER|$repo_escaped|g" "$file" > "$rendered"

    if [ ! -f "$target" ]; then
      cp "$rendered" "$target"
      ok "$name angelegt"
    elif cmp -s "$rendered" "$target"; then
      ok "$name bereits aktuell"
    else
      echo ""
      warn "$name weicht von der Vorlage ab:"
      diff -u "$target" "$rendered" | sed 's/^/    /' || true
      if [ -n "${COMMANDS_ASSUME:-}" ]; then
        answer="$COMMANDS_ASSUME"
      else
        read -rp "  Mit der Repo-Fassung überschreiben? [j/N]: " answer
      fi
      case "$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')" in
        j|y)
          cp "$target" "$target.bak"
          cp "$rendered" "$target"
          ok "$name aktualisiert (Sicherung: $name.bak)"
          ;;
        *)
          warn "$name unverändert gelassen"
          ;;
      esac
    fi

    rm -f "$rendered"
  done
}

# commands_uninstall <quell-dir> <ziel-dir>
# Entfernt genau die Commands, die aus dem Repo stammen. Sicherungen (.bak)
# bleiben liegen — darin stecken die Anpassungen des Nutzers.
commands_uninstall() {
  local src="$1" dst="$2"
  local file name target

  [ -d "$src" ] || return 0

  for file in "$src"/*.md; do
    [ -f "$file" ] || continue
    name=$(basename "$file")
    target="$dst/$name"
    if [ -f "$target" ]; then
      rm -f "$target"
      ok "$name entfernt aus $dst"
    fi
  done
}
