# Claude Voice

Lässt Claude Code nach jeder Antwort den letzten Absatz vorlesen — mit der deutschen **Thorsten-Stimme** (CC0-Lizenz).

Gesprochen wird über einen OpenAI-kompatiblen TTS-Endpoint. Standard ist der Thorsten-Server, den eine [voicemode](https://github.com/mbailey/voicemode)-Installation auf Port 8881 mitbringt — dadurch braucht dieses Repo weder ein eigenes Modell noch eine Piper-Installation.

## Voraussetzungen

- macOS (nutzt `afplay` zur Wiedergabe)
- `jq` (`brew install jq`)
- Ein erreichbarer TTS-Server, z.B. der von voicemode

## Installation

```bash
git clone <repo-url> ~/GitRepos/claude-voice
cd ~/GitRepos/claude-voice
./install.sh
```

Das Script:
- prüft `jq`, `curl` und `afplay`
- prüft, ob der TTS-Server erreichbar ist (warnt nur — er darf später starten)
- legt `config.json` an
- trägt den Stop-Hook ein, wahlweise lokal oder global

Danach **Claude Code neu starten** — ab sofort liest Thorsten jede Antwort vor.

## Deinstallation

```bash
./uninstall.sh
```

Entfernt den Stop-Hook, Temp-Dateien und auf Nachfrage die Fallback-Modelle. Der TTS-Server selbst bleibt unangetastet — er gehört nicht zu dieser Installation.

## Zusammenspiel mit dem Sprachmodus

Läuft ein gesprochenes Gespräch über voicemode, würde jede Antwort doppelt kommen: einmal von voicemode, einmal vom Stop-Hook. Deshalb schweigt der Hook, solange eine Stumm-Markierung für das Projekt existiert:

```bash
# stumm
touch "/tmp/claude-voice-mute-$(echo -n "$PWD" | md5 -q)"
# wieder laut
rm -f "/tmp/claude-voice-mute-$(echo -n "$PWD" | md5 -q)"
```

Der Command `~/.claude/commands/sprich.md` setzt die Markierung beim Eintritt, frischt sie vor jedem Sprech-Zug auf und löscht sie bei „Feierabend". Sie wirkt damit als Heartbeat: Bricht die Session ab, bleibt die Auffrischung aus und die Markierung verfällt zehn Minuten später von selbst — der Hook findet ohne Zutun zurück zu seiner Stimme. Die Frist steht als `MUTE_TTL_MIN` in `speak.sh`.

Die Markierung hängt bewusst am Projektpfad, nicht global: So bleibt ein Projekt im Sprachmodus stumm, während parallele Sessions in anderen Projekten weiter vorlesen.

## Konfiguration

Einstellungen in `config.json` anpassen:

```json
{
  "speed": 0.8,
  "volume": 0.4,
  "paragraph": "last",
  "tts_url": "http://127.0.0.1:8881/v1/audio/speech",
  "voice": "de_DE-thorsten-high"
}
```

| Key | Beschreibung | Werte |
|-----|-------------|-------|
| `speed` | Sprechgeschwindigkeit | `0.5` (sehr schnell) – `1.0` (normal) – `2.0` (langsam) |
| `volume` | Lautstärke | `0.5` (leise) – `1.0` (normal) – `2.0` (laut) |
| `paragraph` | Welcher Teil der Antwort | `"last"` (letzter Absatz) oder `"all"` (alles) |
| `tts_url` | OpenAI-kompatibler TTS-Endpoint | Standard: voicemode auf Port 8881 |
| `voice` | Stimme des Servers | verfügbare Namen unter `<server>/v1/audio/voices` |
| `model` | Nur für den Fallback: Piper-Modellname (ohne `.onnx`) | Datei muss in `models/` liegen |

Alle verfügbaren Werte sind in `config.defaults.json` dokumentiert.

## Fallback ohne Server

Antwortet der TTS-Server nicht, greift `speak.sh` auf ein lokal installiertes `piper` samt Modell in `models/` zurück. Beides ist optional; ohne Fallback bleibt es bei einem Eintrag in `speak.log`.

```bash
pip3 install piper-tts
mkdir -p models && cd models
curl -LO https://huggingface.co/rhasspy/piper-voices/resolve/main/de/de_DE/thorsten/high/de_DE-thorsten-high.onnx
curl -LO https://huggingface.co/rhasspy/piper-voices/resolve/main/de/de_DE/thorsten/high/de_DE-thorsten-high.onnx.json
```

## Aufbau

| Datei | Zweck |
|-------|-------|
| `speak.sh` | Stop-Hook: liest die letzte Antwort vor |
| `replay.sh` | Wiederholt die letzte Antwort (`/read-msg`) |
| `tts.sh` | Gemeinsame Bausteine: Config, Markdown-Bereinigung, Synthese, Wiedergabe |
