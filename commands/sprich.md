Wechsle in den Sprachmodus und führe das Gespräch ab jetzt gesprochen weiter,
bis der Nutzer „Feierabend" sagt oder im Text ausdrücklich etwas anderes will.

**Zuerst** den Vorlese-Hook stummschalten, sonst kommt jede Antwort doppelt —
einmal gesprochen von dir, einmal vom Stop-Hook aus claude-voice:

```bash
touch "/tmp/claude-voice-mute-$(echo -n "$PWD" | md5 -q)"
```

**Denselben Befehl vor jedem `converse`-Aufruf wiederholen.** Der Marker
verfällt zehn Minuten nach der letzten Auffrischung; dieser Heartbeat hält
ihn am Leben. Bricht die Session ab, bleibt die Auffrischung aus und der
Hook findet von allein zurück zu seiner Stimme.

Bei „Feierabend" wieder aufheben:

```bash
rm -f "/tmp/claude-voice-mute-$(echo -n "$PWD" | md5 -q)"
```

Verwende `mcp__voicemode__converse` mit diesen Einstellungen:

- `vad_aggressiveness: 0` — die geduldigste Stille-Erkennung. Wer beim Sprechen
  nachdenkt, wird sonst mitten im Satz abgeschnitten.
- `listen_duration_min: 2` — bei einem kurzen „Ja" soll niemand warten.
  Die Geduld kommt aus der Stille-Erkennung, nicht aus der Mindestdauer.
- `listen_duration_max: 180` oder mehr, wenn auf etwas gewartet wird.

Protokoll:

- **„Roger"** am Ende einer Äußerung heißt: Ansage vollständig, du darfst
  antworten. **Fehlt es**, wurde der Nutzer abgeschnitten — dann still
  weiterhören (`message: "(warte)"` plus `skip_tts: true`) statt zu antworten
  oder nachzuhaken. `message: null` lehnt das Tool ab.
  Beim Warten `listen_duration_min` auf **mindestens 20 Sekunden** setzen —
  kürzer wirkt ungeduldig. Liefert das Transkript nur Geräusche
  („Stimmengewirr"), ist der Nutzer abgelenkt: weiter warten, nicht nachhaken —
  und in der Zwischenzeit an dem weiterarbeiten, was ohne dessen Antwort
  möglich ist.
- **„Feierabend"** beendet den Sprachmodus; danach im Text weiter.
- **Kurz sprechen.** Zwei bis drei Sätze pro Beitrag. Alles über etwa zwanzig
  Sekunden Playback lässt den Nutzer zu lange warten — Details gehören in den
  Text.
- Whisper transkribiert oft fehlerhaft. Bei unklarem Transkript **nie** eine
  irreversible Aktion ausführen, sondern nachfragen.
- Schreibe vor jedem Aufruf `> **ASSISTANT (voicemode):** <Text>` und nach
  einer Antwort `> **USER (voicemode):** <Antwort>` in den Chat, damit das
  Gespräch im Transkript lesbar bleibt.
