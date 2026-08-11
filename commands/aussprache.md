Pflege das Aussprache-Lexikon von claude-voice — die Regeln, mit denen das
deutsche Thorsten-Modell englische Begriffe verständlich ausspricht.

Regeldatei: `{{CLAUDE_VOICE_DIR}}/pronunciation.txt`
Format: `Begriff = Lautschrift`, eine Regel pro Zeile, `#` leitet einen
Kommentar ein. Die Reihenfolge in der Datei ist bedeutungslos — beim Laden
gewinnt der längere Begriff. Neue Regeln deshalb einfach anhängen.

Drei Aufrufformen, je nachdem was hinter dem Befehl steht:

**Ohne Argument** — die aktuellen Regeln auflisten:

```bash
cat "{{CLAUDE_VOICE_DIR}}/pronunciation.txt"
```

**Nur ein Begriff** (`/aussprache Slice`) — Schreibweise gemeinsam finden:

1. Drei deutsche Umschriften vorschlagen, die den englischen Klang treffen.
   Piper liest deutsch: „Slice" wird zu „Slaiß", nicht zu „slaɪs". Keine IPA,
   keine englische Schreibweise.
2. Vorsprechen lassen:
   ```bash
   "{{CLAUDE_VOICE_DIR}}/pronounce.sh" "Sleis" "Slaiß" "Sleiß"
   ```
   Läuft gerade der Sprachmodus, stattdessen die Kandidaten über `converse`
   sprechen — sonst redet die Hörprobe dem Zuhören dazwischen.
3. Auswählen lassen. Nie selbst entscheiden, welche Umschrift gewinnt: das
   hört der Nutzer, nicht du.
4. Die gewählte Regel anhängen.

**Begriff und Lautschrift** (`/aussprache Slice = Slaiß`) — direkt eintragen,
ohne Hörprobe.

Vor jedem Eintrag prüfen, ob der Begriff schon eine Regel hat:

```bash
grep -n "^[[:space:]]*Slice[[:space:]]*=" "{{CLAUDE_VOICE_DIR}}/pronunciation.txt"
```

Gibt es einen Treffer, die bestehende Lautschrift zeigen und fragen, bevor sie
ersetzt wird.

**Nach dem Eintrag nicht committen.** Ein Aussprache-Fund passiert mitten in
anderer Arbeit; ungefragt zu committen unterbräche sie. Die Änderung liegt in
`pronunciation.txt` im claude-voice-Repo — nicht im Projekt, an dem gerade
gearbeitet wird. Stattdessen sagen, was eingetragen wurde und dass der Commit
dort noch aussteht.

Die Regel wirkt sofort — Hook wie Sprachmodus lesen die Datei bei jedem
Aufruf neu. Eine Neuinstallation ist nicht nötig.
