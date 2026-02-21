# Claude Voice

Lässt Claude Code nach jeder Antwort den letzten Absatz vorlesen — via [Piper TTS](https://github.com/OHF-voice/piper1-gpl) mit der deutschen **Thorsten-Stimme** (CC0-Lizenz).

## Voraussetzungen

- macOS (nutzt `afplay` zur Wiedergabe)
- Python 3.10+
- `jq` (`brew install jq`)

## Installation

```bash
git clone <repo-url> ~/GitRepos/claude-voice
cd ~/GitRepos/claude-voice
./install.sh
```

Das Script:
- prüft alle Abhängigkeiten
- installiert `piper-tts` falls nötig
- lädt das Thorsten-Modell herunter (~100 MB)
- legt `config.json` an
- trägt den Stop-Hook in `.claude/settings.local.json` ein

Danach **Claude Code neu starten** — ab sofort liest Thorsten jede Antwort vor.

## Deinstallation

```bash
./uninstall.sh
```

Das Script:
- entfernt den Stop-Hook aus `.claude/settings.local.json`
- löscht heruntergeladene Modelle aus `models/`
- löscht `config.json` und `speak.log`

## Konfiguration

Einstellungen in `config.json` anpassen:

```json
{
  "speed": 0.8,
  "volume": 1.0,
  "model": "de_DE-thorsten-high",
  "paragraph": "last"
}
```

| Key | Beschreibung | Werte |
|-----|-------------|-------|
| `speed` | Sprechgeschwindigkeit | `0.5` (sehr schnell) – `1.0` (normal) – `2.0` (langsam) |
| `volume` | Lautstärke | `0.5` (leise) – `1.0` (normal) – `2.0` (laut) |
| `model` | Piper-Modellname (ohne `.onnx`) | Datei muss in `models/` liegen |
| `paragraph` | Welcher Teil der Antwort | `"last"` (letzter Absatz) oder `"all"` (alles) |

Alle verfügbaren Werte sind in `config.defaults.json` dokumentiert.

## Andere Modelle

Weitere deutsche Stimmen von [rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices):

| Modell | Geschlecht | Qualität |
|--------|-----------|----------|
| `de_DE-thorsten-high` | männlich | hoch |
| `de_DE-thorsten-medium` | männlich | mittel |
| `de_DE-kerstin-low` | weiblich | niedrig |

`.onnx` und `.onnx.json` in `models/` legen, dann `model` in `config.json` anpassen.

## Manuell testen

```bash
echo '{"stop_hook_active":false,"session_id":"test","cwd":"/tmp","last_assistant_message":"Hallo, das ist ein Test."}' | ./speak.sh
```

## Session-Isolation

Läuft in mehreren Claude-Instanzen gleichzeitig? Kein Problem — jede Session spricht unabhängig. Die `session_id` im Hook-JSON stellt sicher, dass parallele Sessions sich nicht gegenseitig stören.

## Troubleshooting

**Kein Ton nach Neustart:**
- `speak.log` prüfen: `cat speak.log`
- Modell vorhanden? `ls models/`
- Script ausführbar? `chmod +x speak.sh`

**Hook wird nicht ausgeführt:**
- Claude Code neu starten
- `.claude/settings.local.json` prüfen — muss `Stop`-Hook mit Pfad zu `speak.sh` enthalten

## Dateistruktur

```
claude-voice/
├── speak.sh                      # Hook-Script (wird von Claude aufgerufen)
├── install.sh                    # Einmal ausführen zur Ersteinrichtung
├── uninstall.sh                  # Deinstallation
├── .gitignore                    # Git-Ausschlüsse (Modelle, Logs, User-Config)
├── config.json                   # Eigene Einstellungen (nicht eingecheckt)
├── config.defaults.json          # Dokumentierte Defaults (nicht bearbeiten)
├── models/
│   ├── de_DE-thorsten-high.onnx      # Sprachmodell (~100 MB, nicht eingecheckt)
│   └── de_DE-thorsten-high.onnx.json # Modell-Metadaten (eingecheckt)
└── .claude/
    └── settings.local.json       # Claude Code Hook-Konfiguration (nicht eingecheckt)
```
