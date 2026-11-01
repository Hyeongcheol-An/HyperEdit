# HyperEdit – Benutzerhandbuch

<p align="center"><a href="USER_GUIDE.md">English</a> · <a href="USER_GUIDE.ko.md">한국어</a> · <a href="USER_GUIDE.zh-Hans.md">简体中文</a> · <a href="USER_GUIDE.ja.md">日本語</a> · <a href="USER_GUIDE.vi.md">Tiếng Việt</a> · <a href="USER_GUIDE.hi.md">हिन्दी</a> · Deutsch · <a href="USER_GUIDE.fr.md">Français</a> · <a href="USER_GUIDE.es.md">Español</a> · <a href="USER_GUIDE.pt.md">Português</a> · <a href="USER_GUIDE.ar.md">العربية</a></p>

HyperEdit ist ein schneller Editor für reinen Text unter macOS, gebaut um eine große Notizdatei – die Art Datei, an die du jahrelang immer weiter anhängst. Dieses Handbuch erklärt alles, was du damit tun kannst, in der Reihenfolge, in der du es wahrscheinlich antriffst. Kurzbefehle sind mit den Mac-Symbolen geschrieben: ⌘ Befehlstaste, ⇧ Umschalttaste, ⌥ Wahltaste, ⌃ Steuerungstaste.

## Inhalt

1. [Installation und Aktualisierung](#1-installation-und-aktualisierung)
2. [Erster Start](#2-erster-start)
3. [Sprache der Oberfläche](#3-sprache-der-oberfläche)
4. [Das Fenster](#4-das-fenster)
5. [Grundlagen der Bearbeitung](#5-grundlagen-der-bearbeitung)
6. [Suchen und Ersetzen](#6-suchen-und-ersetzen)
7. [Lesezeichen](#7-lesezeichen)
8. [Spaltenmodus und Multi-Cursor](#8-spaltenmodus-und-multi-cursor)
9. [Zeilen- und Textwerkzeuge](#9-zeilen--und-textwerkzeuge)
10. [Snippets](#10-snippets)
11. [Makros](#11-makros)
12. [Code-Faltung und Scrollbalken-Marker](#12-code-faltung-und-scrollbalken-marker)
13. [Geteilter Editor](#13-geteilter-editor)
14. [Schnelleingabe](#14-schnelleingabe)
15. [Markdown-Vorschau und Syntaxfarben](#15-markdown-vorschau-und-syntaxfarben)
16. [Themes, Schriften und CJK-Text](#16-themes-schriften-und-cjk-text)
17. [Sichern, Schnappschüsse und Codierungen](#17-sichern-schnappschüsse-und-codierungen)
18. [Einstellungen im Überblick](#18-einstellungen-im-überblick)
19. [Tastaturkurzbefehle](#19-tastaturkurzbefehle)
20. [Dateien, die HyperEdit schreibt](#20-dateien-die-hyperedit-schreibt)
21. [Fehlerbehebung](#21-fehlerbehebung)
22. [Bekannte Einschränkungen](#22-bekannte-einschränkungen)
23. [Geheime Blöcke und App-Sperre](#23-geheime-blöcke-und-app-sperre)
24. [Hilfe erhalten](#24-hilfe-erhalten)

## 1. Installation und Aktualisierung

**Voraussetzungen:** macOS 15 (Sequoia) oder neuer. Die App ist ein Universal Binary (Apple Silicon und Intel), signiert und beglaubigt, sodass Gatekeeper sie ohne Warnung öffnet.

**Homebrew**

```sh
brew tap Hyeongcheol-An/tap
brew install --cask hyperedit
```

Später aktualisierst du mit `brew upgrade --cask hyperedit`. Homebrew 7 verlangt eventuell, dass du dem Tap zuerst vertraust: `brew trust Hyeongcheol-An/tap`.

**DMG:** Lade `HyperEdit-x.y.z-universal.dmg` von [GitHub Releases](https://github.com/Hyeongcheol-An/HyperEdit/releases), öffne es und ziehe `HyperEdit.app` nach `Programme`. Um einen Download zu prüfen, lege `SHA256SUMS` neben das DMG und führe `shasum -a 256 -c SHA256SUMS` aus.

HyperEdit enthält keinen Netzwerkcode und keine Telemetrie: Es „telefoniert nie nach Hause“, und Updates sind etwas, das du tust – nicht etwas, das die App tut.

## 2. Erster Start

HyperEdit öffnet `~/Documents/HyperEdit/notes.md`. Existiert die Datei nicht, wird sie mit einem kurzen Willkommenstext in deiner Sprache angelegt – lösche den Text und fang an zu schreiben. Die Idee ist, dass du eine Datei behältst und daran anhängst, aber nichts zwingt dich dazu:

- **⌘N** legt eine neue leere Textdatei an (du wählst Namen und Ordner).
- **⌘O** öffnet jede andere Textdatei. Die zuletzt geöffnete Datei wird für den nächsten Start gemerkt.
- **Ablage › Standarddokument öffnen** bringt dich zurück zu `notes.md`.
- Binärdateien (Bilder, PDFs, Archive …) werden nie in den Editor geladen; sie öffnen sich stattdessen in ihrer Standard-App.

Cursor- und Scrollposition werden pro Datei gemerkt, sodass du beim erneuten Öffnen einer Datei mit 30.000 Zeilen genau dort landest, wo du aufgehört hast. **⌃⌘E** springt ans Ende des Dokuments – die Stelle, die du in einer Notizdatei meist willst.

## 3. Sprache der Oberfläche

Die Oberfläche gibt es in elf Sprachen: English (Englisch), 한국어 (Koreanisch), 简体中文 (vereinfachtes Chinesisch), 日本語 (Japanisch), Tiếng Việt (Vietnamesisch), हिन्दी (Hindi), Deutsch, Français (Französisch), Español (Spanisch), Português (Portugiesisch, brasilianische Schreibung) und العربية (Arabisch). Arabischer Text wird von rechts nach links geschrieben, das Fensterlayout – Menüband, Seitenleiste, Panels und Editor – bleibt aber wie in den meisten Code-Editoren von links nach rechts; der Text, den du tippst, folgt seiner eigenen Schreibrichtung.

Standardmäßig folgt HyperEdit der Systemsprache. So wählst du eine andere:

1. Öffne die **Einstellungen (⌘,)** und sieh dir den Abschnitt **Sprache** ganz oben an.
2. Wähle im Menü **Sprache der Oberfläche** eine Sprache. Jede Sprache steht dort in ihrer eigenen Schrift, sodass du deine auch dann findest, wenn dir die aktuelle Sprache fremd ist. **Systemstandard** zeigt, welche Sprache die Systemeinstellung ergeben würde.
3. Klicke auf **Jetzt neu starten**. Das Dokument wird zuerst gesichert, dann beendet sich HyperEdit und öffnet sich in der neuen Sprache wieder. (Du kannst auch weiterarbeiten und später neu starten; die Wahl ist bereits gespeichert.)

Die Wahl wird am selben Ort gespeichert wie **Systemeinstellungen › Allgemein › Sprache & Region › Apps**, sodass beide übereinstimmen. **Hilfe › Benutzerhandbuch** und die Taste **Benutzerhandbuch öffnen** in den Einstellungen öffnen dieses Handbuch in der aktuellen Sprache der Oberfläche.

Eine Sprache, die nicht in der Liste steht, fällt auf Englisch zurück (zum Beispiel traditionelles Chinesisch). Dokumenttext, Dateinamen und eingefügte Datumsangaben sind von der Sprache der Oberfläche nicht betroffen – der Wochentag im Zeitstempel folgt der Systemregion.

## 4. Das Fenster

Das Layout folgt einem klassischen Editor mit Menüband und ausgeblendeter Titelleiste.

- **Menüband-Tabs** – **Start** (Zwischenablage, Suchen, Einfügen, Modus, Datei), **Bearbeiten** (Zeilen, Groß-/Kleinschreibung, Sortieren, Leerraum, Spalten & Multi-Cursor, Werkzeuge, Makro), **Layout** (Theme, Panels, Faltung, Markdown, Schriftgröße), **Erweitert** (Optionen, Schnappschuss-Ordner, Neu laden, Standarddokument), **Fenster** (Vollbild, Panels). Ist das Fenster schmal, klappen die Gruppen von rechts her zu Symbolen zusammen; der Tooltip des Symbols zeigt die Beschriftung.
- **Dokument-Tableiste** – der aktuelle Dateiname mit den Tasten Neu (⌘N) und Öffnen (⌘O) sowie Schnellzugriff auf Sichern / Widerrufen / Wiederholen.
- **Seitenleiste (⌘1)** – **Dateien** (der Ordner der aktuellen Datei; ein Klick öffnet eine Datei), **Gliederung (⌘3)** (Überschriften, `[Titel]`-Zeilen und nummerierte Punkte, mit Filterfeld; der aktuelle Eintrag ist hervorgehoben), **Zeitleiste (⌘4)** (Zeitstempel-Überschriften nach Monat gruppiert, neueste zuerst).
- **Unteres Panel (⌘2)** – **Suchergebnisse**, **Lesezeichen** und **Ausgabe**, ein Protokoll dessen, was die App getan hat (Sichern, Ersetzungen, Fehler).
- **Statusleiste** – Zeile und Spalte (plus Länge der Auswahl; beim Überfahren erscheint der Zeichen-Offset), Zeilenende (UNIX / DOS / MAC), Zeichencodierung, **COL**, solange der Spaltenmodus an ist, Anzahl der Cursor, Zeilenzahl · Dateigröße, die letzte Statusmeldung, die Syntaxsprache (abgeblendet, solange die Syntaxfarben aus sind), ein Theme-Menü (mit „· System“ markiert, solange die App dem Erscheinungsbild des Systems folgt) und der Zoom in Prozent. Die meisten Einträge sind anklickbar.

## 5. Grundlagen der Bearbeitung

- Normales Tippen bleibt auch in Dateien mit mehreren Megabyte schnell; nur der sichtbare Teil des Dokuments wird gesetzt.
- **Zeilenumbruch** ⌥Z · **Zeilennummern** ⌥⌘L · **Zoom** ⌘= / ⌘- / ⌘0 (auch im Tab „Layout“).
- **Gehe zu Zeile** ⌘L · **Ende des Dokuments** ⌃⌘E.
- **Datum/Zeit einfügen** F7 fügt eine Zeitstempel-Überschrift wie `## 2026-10-31 (Fr.) 14:05` ein. Der Wochentag folgt deiner Systemregion. Solche Zeilen speisen die Zeitleiste.
- Die aktuelle Zeile ist hervorgehoben, und die Randspalte zeigt ihre Nummer in der Textfarbe.
- Widerrufen und Wiederholen sind innerhalb einer Sitzung unbegrenzt, und jedes der unten beschriebenen Werkzeuge ist ein einziger Widerrufen-Schritt.

## 6. Suchen und Ersetzen

- **Suchen (⌘F)** öffnet die Suchleiste. Tippe einen Suchbegriff und drücke die Eingabetaste: Jeder Treffer wird mit Zeilennummer im unteren Panel aufgelistet, und die Treffer sind im Editor hervorgehoben, solange die Liste offen ist. Schalter: Regex `.*`, Groß-/Kleinschreibung beachten `Aa`, ganzes Wort `W`. **F3 / ⇧F3** springen zum nächsten / vorherigen Treffer. Die Liste aktualisiert sich etwa eine Sekunde nach einer Bearbeitung von selbst.
- **Ersetzen (⌘R)** blendet ein Ersetzungsfeld ein: Ersetze den aktuellen Treffer und gehe weiter, oder **Alle ersetzen**. Mit eingeschaltetem Regex fügen Vorlagen wie `$1` Gruppen ein. „Alle ersetzen“ ist ein einziger Widerrufen-Schritt, selbst bei Tausenden Treffern.
- **In Dateien suchen (⇧⌘F)** durchsucht einen Ordner (Unterordner eingeschlossen). Wähle den Ordner, grenze optional mit Masken wie `*.md;*.txt` ein und klicke auf einen Treffer, um die Datei an dieser Zeile zu öffnen. Versteckte Dateien, Pakete, Binärdateien und Dateien über 20 MB werden übersprungen.
- **Alle Treffer auswählen (⌥⌘A)** verwandelt jeden Treffer in einen Cursor – siehe Multi-Cursor unten.

## 7. Lesezeichen

**⌘F2** setzt ein Lesezeichen in der aktuellen Zeile (oder entfernt es), **F2 / ⌥F2** springen zum nächsten / vorherigen Lesezeichen, und der Tab **Lesezeichen** im unteren Panel listet sie alle auf; dort kannst du einem Lesezeichen einen Namen geben. Lesezeichen wandern beim Bearbeiten mit ihren Zeilen: Das Einfügen oder Löschen von Zeilen darüber verschiebt sie, das Löschen einer Zeile mit Lesezeichen entfernt es, und Widerrufen holt es zurück. Sie werden pro Dokument unter `~/Library/Application Support/HyperEdit/bookmarks/` gespeichert, sodass nichts neben deine Dateien geschrieben wird.

## 8. Spaltenmodus und Multi-Cursor

- **Spaltenmodus (⌥C)** – halte ⌥ gedrückt und ziehe, oder benutze ⇧ mit den Pfeiltasten, um ein Rechteck auszuwählen. Tippen und Löschen wirken dann auf jede Zeile des Blocks, kurze Zeilen werden mit virtuellem Leerraum aufgefüllt, und Kopieren / Einsetzen arbeiten zeilenweise. Die Statusleiste zeigt **COL**. Erneutes ⌥C schaltet den Modus aus.
- **Nummern einfügen (⌥⌘N)** – füllt eine Spaltenauswahl (oder jeden Cursor) mit einer Zahlenfolge: Wähle Startwert und Schrittweite; die Zahlen werden mit Nullen auf gleiche Breite aufgefüllt.
- **Multi-Cursor** – ⌘-Klick fügt einen Cursor hinzu, **⌘D** fügt das nächste Vorkommen des gewählten Texts (oder des Worts am Cursor) hinzu, **⌥⌘A** wählt jeden Suchtreffer aus. Eingaben gehen an jeden Cursor; Esc kehrt zu einem zurück. Jede Multi-Cursor-Bearbeitung ist ein Widerrufen-Schritt.

## 9. Zeilen- und Textwerkzeuge

Diese Werkzeuge stehen im Menüband-Tab **Bearbeiten** und im Menü **Zeile**. Sie wirken auf die gewählten Zeilen oder, wenn nichts ausgewählt ist, auf die aktuelle Zeile.

| Gruppe | Werkzeuge |
|---|---|
| Zeilen | Zeile löschen ⇧⌘K · Zeile duplizieren ⇧⌘D · Zeile nach oben / unten ⌥↑ / ⌥↓ · Zeilen verbinden ⇧⌘J · Zeilen umkehren · Nummerieren |
| Groß-/Kleinschreibung | Großbuchstaben · Kleinbuchstaben · Wortanfang groß · Groß ↔ Klein |
| Sortieren | A–Z · Z–A · Numerisch (nach der Zahl am Zeilenanfang) · Doppelte Zeilen entfernen |
| Leerraum | Leerraum am Zeilenende entfernen · Leerraum am Zeilenanfang und -ende entfernen · Leerzeilen entfernen · Tab → Leerzeichen · Leerzeichen → Tab |

- **Berechnen (⌃⌘=)** wertet die Auswahl oder die aktuelle Zeile aus (den Teil nach dem letzten `=`, falls vorhanden) und hängt ` ⇒ Ergebnis` an: Aus `3+0.5+0.25` wird `3+0.5+0.25 ⇒ 3.75`. Ein erneuter Aufruf auf einer geänderten Zeile ersetzt das alte Ergebnis. Unterstützt: `+ - * / % ^`, Klammern, Zahlen wie `1,234` und `1_000`, `sqrt abs round floor ceil min max`, `pi` und `e`. Ein Ausdruck, der sich nicht auswerten lässt, wird im Panel „Ausgabe“ gemeldet, und der Text bleibt unverändert.
- **Tabelle ausrichten (⌃⌘T)** füllt tabulatorgetrennte Spalten auf (die gewählten Zeilen oder den Block aus Tab-Zeilen rund um den Cursor), sodass jede Spalte in derselben Anzeigespalte beginnt; koreanische, chinesische und japanische Zeichen zählen als zwei Zellen. Enthält jede Zeile ein `|`, wird der Block stattdessen als Markdown-Tabelle behandelt: Zellen werden innerhalb von ` | ` aufgefüllt, `---`-Zeilen neu gezeichnet und `--:`-Spalten rechtsbündig ausgerichtet.
- **Kommentieren (⌘/)** kommentiert die Zeilen mit dem Kommentarzeichen des Dateityps oder hebt den Kommentar wieder auf: `//`, `#`, `--` … für Code, `<!-- -->` für Markdown und HTML, `/* */` für CSS, `//` für einfache Notizen. Sind alle nicht leeren Zeilen bereits kommentiert, werden alle entkommentiert, sonst werden alle kommentiert, wobei die Zeichen an der geringsten Einrückung ausgerichtet werden. Leerzeilen werden übersprungen.
- **JSON formatieren (⌃⌘J) / JSON minifizieren** formatiert (2 Leerzeichen Einrückung) oder komprimiert die Auswahl bzw. das ganze Dokument, wenn nichts ausgewählt ist. Reihenfolge der Schlüssel und Zahlentext bleiben erhalten, Nicht-ASCII-Text bleibt unmaskiert, und die Eingabe darf Kommentare und nachgestellte Kommas enthalten (JSONC). Bei einem Syntaxfehler bleibt der Text unverändert, das Panel „Ausgabe“ zeigt `Zeile:Spalte`, und der Cursor springt dorthin.

## 10. Snippets

Tippe ein Kürzel und drücke **Tab**, um es zu expandieren. Eingebaute Kürzel: `todo`, `date`, `time`, `now`, `meeting`, `table`, `link`, `code`. **Snippet einfügen… (⇧⌘I)** listet alle mit einem Filterfeld auf, und der Tab „Start“ hat eine Taste „Snippet…“.

Ein Snippet-Text kann Variablen enthalten – `${date}`, `${time}`, `${datetime}`, `${selection}`, `${clipboard}`, `${filename}` – sowie Tabstopps `$1` … `$9`, `${1:placeholder}` und `$0`. Nach dem Expandieren springen Tab / ⇧Tab zwischen den Tabstopps (eine doppelt verwendete Nummer wird zum Multi-Cursor), und Esc oder ein Klick beendet die Sitzung.

**Snippets bearbeiten…** (Menü „Bearbeiten“ oder Tab „Start“) öffnet `~/Library/Application Support/HyperEdit/snippets.json` in HyperEdit selbst. Jeder Eintrag hat ein `trigger`, einen `name` und einen `body`; die Datei wird nach dem Sichern neu eingelesen, sodass ein neues Kürzel sofort funktioniert.

## 11. Makros

Ein Makro zeichnet auf, was du tippst, und spielt es an anderer Stelle wieder ab.

1. **Makro aufzeichnen (⇧⌘M)** startet die Aufzeichnung; die Statusleiste zeigt `● REC`. Aufgezeichnet werden Eingaben (bei Koreanisch und anderen Eingabemethoden die bestätigten Zeichen), Cursorbewegungen, Löschen, Zeilenumbrüche, Einsetzen, die Textwerkzeuge und Weitersuchen (F3, mit seinem Suchbegriff). Mausklicks, Änderungen der Auswahl und Multi-Cursor-Bearbeitungen werden nicht aufgezeichnet.
2. Erneutes **⇧⌘M** stoppt die Aufzeichnung.
3. **Makro abspielen (⌥⌘M)** spielt es am Cursor ab. **Makro mehrmals abspielen…** wiederholt es bis zu 10.000-mal und stoppt von selbst, wenn ein Suchschritt nichts findet oder ein Durchlauf nichts ändert – ein praktisches Werkzeug nach dem Motto „mach das mit jeder Zeile“. Ein ganzer Durchlauf ist ein Widerrufen-Schritt.

Die letzte Aufzeichnung bleibt nur bis zum Beenden im Speicher, sodass nichts Vertrauliches, das du während der Aufzeichnung getippt hast, jemals auf die Festplatte gelangt. **Letztes Makro sichern unter…** nimmt es dauerhaft ins Menü **Makro** auf; gesicherte Makros liegen in `~/Library/Application Support/HyperEdit/macros/macros.json`, das **Makrodatei bearbeiten…** im Editor öffnet.

## 12. Code-Faltung und Scrollbalken-Marker

**Einklappen (⌥⌘←) / Ausklappen (⌥⌘→)** verbergen oder zeigen den Bereich am Cursor; **⌥⇧⌘← / ⌥⇧⌘→** klappen alles ein oder aus. Ein Bereich ist:

- die unter der aktuellen Zeile eingerückten Zeilen (Leerzeilen werden ignoriert),
- in Markdown alles unter einer `#`-Überschrift bis zur nächsten Überschrift gleicher oder höherer Ebene (eingezäunte Codeblöcke klappen ebenfalls),
- in Code eine Zeile, die auf `{`, `[` oder `(` endet, bis zur Zeile mit der schließenden Klammer.

Klicke auf das Winkelsymbol in der Randspalte oder auf die Pille `⋯ N Zeilen` hinter einer eingeklappten Zeile, um sie mit der Maus umzuschalten. Bewegt sich der Cursor in eine eingeklappte Zeile (Suchen, Gehe zu Zeile, Lesezeichen, Widerrufen), wird sie ausgeklappt; ↑ / ↓ überspringen Faltungen. Faltungen folgen deinen Bearbeitungen und bleiben für die Sitzung erhalten.

**Scrollbalken-Marker** – ein schmaler Streifen am rechten Rand des Editors zeigt Suchtreffer (Akzentfarbe), Lesezeichen (Warnfarbe), die Cursorzeile und eingeklappte Kopfzeilen an ihrer relativen Position in der Datei. Er ist ausgeblendet, wenn das ganze Dokument auf den Bildschirm passt. Ausschalten kannst du ihn unter **Darstellung › Scrollbalken-Marker** oder in der Gruppe „Faltung“ des Tabs „Layout“.

## 13. Geteilter Editor

**⌘\\** zeigt dasselbe Dokument in zwei Editoren nebeneinander; **Darstellung › Teilen › Untereinander teilen** ordnet sie übereinander an, und der Tab „Layout“ hat dieselben Tasten. Beide Ansichten bearbeiten denselben Text und teilen sich einen Widerrufen-Verlauf – tippe in der einen, ⌘Z in der anderen –, scrollen aber unabhängig, sodass du einen Teil der Datei lesen kannst, während du in einem anderen schreibst. Befehle, die Statusleiste und die Markdown-Vorschau folgen dem Editor, in den du zuletzt geklickt hast; **⌥⌘\\** verschiebt den Fokus in den anderen. Die Statusleiste zeigt **SPLIT**, solange die Teilung aktiv ist; erneutes ⌘\\ schließt sie.

## 14. Schnelleingabe

**Schnelleingabe (⇧⌘N)** öffnet ein kleines schwebendes Fenster, um eine Notiz hinzuzufügen, ohne das zu verlassen, was du gerade tust. Tippe die Notiz, drücke **⌘↩**, und sie wird ans Ende des Dokuments angehängt – standardmäßig mit einer Zeitstempel-Überschrift –, sofort gesichert und in einem Schritt widerrufbar. Das Fenster verschwindet dann, und der Fokus kehrt zur App zurück, in der du warst. **Esc** schließt das Fenster und behält den Entwurf fürs nächste Mal.

Weil das Fenster HyperEdit nicht aktiviert, funktioniert es über einen **systemweiten Kurzbefehl** auch aus jeder anderen App heraus: standardmäßig **⌃⌥N**. In den Einstellungen kannst du ihn ausschalten oder stattdessen ⌃⌥Space, ⌃⇧Space oder ⌃⌥⌘N wählen und die Zeitstempel-Überschrift abschalten. Der Kurzbefehl nutzt den Hotkey-Dienst des Systems, daher ist keine Bedienungshilfen-Berechtigung nötig. Belegt eine andere App die Kombination bereits, meldet das Panel „Ausgabe“ dies beim Start – wähle dann eine andere.

## 15. Markdown-Vorschau und Syntaxfarben

- **Markdown-Vorschau (⇧⌘P)** teilt das Fenster und zeigt rechts eine gerenderte Ansicht der aktuellen Datei: Überschriften, Listen und Aufgabenlisten, Tabellen, eingezäunter Code, Zitate, Links und Bilder, gestaltet im aktuellen Theme. Sie folgt der Scrollposition des Editors und wird kurz nach dem Ende der Eingabe neu gerendert. Links öffnen sich in deinem Browser; rohes HTML in der Datei wird als Text angezeigt, nie ausgeführt. Dateien über 2 MB zeigen statt der Vorschau einen Hinweis. Die Statusleiste zeigt **MD**, solange sie an ist.
- **Syntaxfarben (⌃⌘H)** richten sich nach der Dateiendung und werden in der Statusleiste angezeigt. Notizen und Markdown bekommen ein leichtes Regelwerk – URLs, Datums- und Zeitangaben, Überschriften, `[Titel]`-Zeilen, Listenzeichen und `[ ]` / `[x]`-Aufgabenkästchen, `#tags`, `key:`-Beschriftungen, `**fett**`, `` `code` `` und `⇒ → ->`-Pfeile – und rund 20 Programmiersprachen bekommen Kommentare, Strings, Zahlen, Schlüsselwörter, Funktions- und Typnamen. Die Farben werden nur auf den sichtbaren Zeilen gezeichnet, sodass sie weder die Datei verändern noch das Tippen verlangsamen. Konstrukte über mehrere Zeilen behalten ihre Farbe, bis sie geschlossen werden: Blockkommentare (`/* */`, `<!-- -->`), mehrzeilige Strings (Swift und Python `"""`, JavaScript-Template-Literale, Go-Raw-Strings, Rust `r#"…"#`) und eingezäunte Markdown-Codeblöcke, die in der im Info-String genannten Sprache eingefärbt werden (```` ```python ````). Tippst du ein öffnendes oder schließendes Trennzeichen, werden die Zeilen darunter sofort neu eingefärbt.
- **Benutzerdefinierte Grammatiken.** Um eine Sprache einzufärben, die HyperEdit nicht kennt, oder eine eingebaute zu ändern, lege eine `*.json`-Datei in `~/Library/Application Support/HyperEdit/grammars/`. HyperEdit legt den Ordner beim ersten Start mit einer `example.json` zum Kopieren und einer README an, die jeden Schlüssel erklärt – `name`, `extensions` oder `filenames`, `mode`, `lineComments`, `blockComment`, `strings`, `multilineStrings`, `keywords`, `types`, `constants`, `builtins`, `caseInsensitive`. **Ablage › Grammatiken neu laden** übernimmt deine Änderungen ohne Neustart; die Statusleiste zeigt den Namen der Grammatik, Kommentieren (⌘/) verwendet ihre Kommentarzeichen, und eine Datei, die sich nicht parsen lässt, wird mit einer Meldung im Panel „Ausgabe“ übersprungen.

## 16. Themes, Schriften und CJK-Text

**Themes.** 22 Paletten – 5 helle, 17 dunkle – werden mit der App ausgeliefert. Standardmäßig folgt sie dem Erscheinungsbild des Systems: **Hyper Light** im hellen Modus, **Hyper Dark** im Dunkelmodus. Wähle ein Theme im Tab „Layout“, im Theme-Menü der Statusleiste, unter **Darstellung › Theme** oder mit ⌥⌘] / ⌥⌘[, um es festzulegen; **Erscheinungsbild des Systems folgen** steht in denselben Menüs und in den Einstellungen. Dieselben Paletten gibt es für den Editor Zed (`hyperedit-themes.json` bei jedem Release).

**Cursor und Fenster-Deckkraft.** Einstellungen › **Erscheinungsbild** wählt die Form des Cursors – **Balken** (Standard), **Block** (die Zeichenzelle wird in der Cursorfarbe getönt, damit das Zeichen lesbar bleibt) oder **Unterstrich** – und ob er blinkt; die zusätzlichen Cursor von Multi-Cursor und Spaltenmodus verwenden dieselbe Form. **Fenster-Deckkraft** (50–100 %) macht das ganze Fenster durchscheinend – Editor, Menüband, Panels und Statusleiste gleichermaßen –, während Text, Symbole und Rahmen deckend bleiben, und **Unschärfe hinter Fenster** fügt die Unschärfe des Systems hinzu. Darstellung › Fenster-Deckkraft bietet die Stufen 100 / 90 / 80 / 70 %.

**Schriften.** HyperEdit verwendet **Fira Code**, wenn sie installiert ist, und sonst die dicktengleiche Systemschrift. Koreanischer Text wird mit einer eigenen Schrift gezeichnet – standardmäßig **D2Coding**, wenn installiert –, so skaliert, dass eine Hangul-Silbe genau zwei lateinische Zellen breit ist, was tabulatorausgerichtete Tabellen gerade hält. Ligaturen, Zeilenhöhe, beide Schriftfamilien und die Hangul-Skalierung stehen in den Einstellungen. Chinesischer und japanischer Text verwendet die Ersatzschriften des Systems und zählt in „Tabelle ausrichten“ ebenfalls als zwei Zellen.

## 17. Sichern, Schnappschüsse und Codierungen

- **Automatisches Sichern** läuft zwei Sekunden nach der letzten Eingabe (⌘S sichert sofort). Beim Beenden, beim Schließen des Fensters und beim Dateiwechsel wird das Dokument sofort gesichert, sodass in den zwei Sekunden nichts verloren geht. Jeder Schreibvorgang ist atomar.
- **Schnappschüsse.** Vor dem ersten Sichern jeder Sitzung wird eine Kopie der Datei unter `~/Library/Application Support/HyperEdit/snapshots` abgelegt (**Ablage › Schnappschuss-Ordner öffnen**). Die neuesten 20 pro Datei bleiben erhalten, alles, was älter als 90 Tage ist, wird entfernt.
- **Externe Änderungen.** Ändert ein anderes Programm die Datei, während sie geöffnet ist, und du hast keine ungesicherten Bearbeitungen, lädt HyperEdit sie neu und lässt den Cursor, wo er war. Hast du ungesicherte Bearbeitungen, wird von der externen Fassung ein Schnappschuss angelegt und eine Warnung angezeigt; Sichern überschreibt sie dann.
- **Sicherheit.** Ein leerer Puffer wird nie über eine Datei geschrieben, die Inhalt hatte. Schlägt das Sichern beim Beenden fehl, wird eine Notfallkopie in den Schnappschuss-Ordner geschrieben, und du wirst gefragt, ob du trotzdem beenden willst.
- **Codierungen.** Dateien werden zuerst als UTF-8 gelesen, dann als EUC-KR (CP949), CP1252 und Latin-1, und in derselben Codierung gesichert (ein UTF-8-BOM bleibt erhalten). Tippst du ein Zeichen, das die ursprüngliche Codierung nicht speichern kann, wird die Datei als UTF-8 gesichert, und die Statusleiste sagt es dir. Eine Datei, die sich in keiner dieser Codierungen decodieren lässt, wird gar nicht erst geöffnet, statt beschädigt zu werden.
- **Zeilenenden** (UNIX / DOS / MAC) werden erkannt und beibehalten; Schnelleingabe und die Textwerkzeuge verwenden das der Datei.
- **Export.** **Ablage › Als HTML exportieren…** sichert das Dokument als eine eigenständige HTML-Datei – Markdown gerendert wie in der Vorschau, Notizen und Code als syntaxgefärbter Block –, und **Ablage › Als PDF exportieren…** druckt dieselbe Seite in ein PDF mit Seitenumbrüchen (Letter in den USA, Kanada und Mexiko, sonst A4; 36 pt Ränder; keine Kopf- oder Fußzeile). Im Sichern-Dialog wählst du das Theme (aktuell, Hyper Light, Hyper Dark) und für Notizen und Code Zeilennummern. Die exportierte Seite enthält keine Skripte und keine Stylesheets oder Schriften aus dem Netz; Bild-URLs bleiben so erhalten, wie sie geschrieben sind, daher kann ein Browser (und der PDF-Renderer) entfernte Bilder laden, und relative Bildpfade funktionieren, wenn du die HTML-Datei neben der Markdown-Datei sicherst. Der PDF-Export funktioniert für Dateien bis 2 MB. Geheime Blöcke (Abschnitt 23) werden als `••••••••` exportiert.

## 18. Einstellungen im Überblick

Öffne die Einstellungen mit **⌘,** oder über den Tab „Erweitert“.

| Abschnitt | Was er steuert |
|---|---|
| Sprache | Sprache der Oberfläche (Systemstandard oder eine von elf Sprachen), **Jetzt neu starten**, **Benutzerhandbuch öffnen** |
| Schrift | Lateinische Schriftfamilie, Größe, Ligaturen, Zeilenhöhe |
| Hangul | Hangul-Schriftfamilie, die Breitenkorrektur 2:1, Hangul-Skalierung; zeigt, ob die Schrift installiert ist |
| Theme | Erscheinungsbild des Systems folgen, Theme-Auswahl |
| Dateien | Die aktuelle Datei, das Standarddokument und der Schnappschuss-Ordner, mit Tasten zum Öffnen |
| Schnelleingabe | Systemweiter Kurzbefehl (Aus / ⌃⌥N / ⌃⌥Space / ⌃⇧Space / ⌃⌥⌘N), Zeitstempel-Überschrift ein/aus |
| Geheimnisse | Geheime Blöcke maskieren, erneut maskieren nach (10 / 30 / 60 s / Nie), Zwischenablage nach Kopieren eines Geheimnisses leeren (Aus / 10 / 30 / 60 s) |
| Erscheinungsbild | Cursorstil (Balken / Block / Unterstrich), Blinken, Fenster-Deckkraft 50–100 %, Unschärfe hinter Fenster |
| App-Sperre | Touch ID oder Passwort zum Öffnen von HyperEdit verlangen (aus), bei Inaktivität sperren (Nie / 1 / 5 / 15 / 30 Minuten), sperren, wenn der Mac in den Ruhezustand wechselt oder der Bildschirm gesperrt wird (ein; erfordert die erste Option) |

Sichtbarkeit der Panels, Zeilenumbruch, Zeilennummern, Syntaxfarben, Scrollbalken-Marker, die Teilung und der Menüband-Tab werden automatisch gemerkt.

## 19. Tastaturkurzbefehle

| Kurzbefehl | Aktion | Kurzbefehl | Aktion |
|---|---|---|---|
| ⌘N | Neues Dokument | ⌘O | Öffnen |
| ⌘S | Sichern | ⌘F | Suchen |
| ⌘R | Ersetzen | ⇧⌘F | In Dateien suchen |
| F3 / ⇧F3 | Nächster / vorheriger Treffer | ⌘L | Gehe zu Zeile |
| ⌃⌘E | Ende des Dokuments | ⌥C | Spaltenmodus |
| ⌘D | Nächstes Vorkommen hinzufügen | ⌥⌘A | Alle Treffer auswählen |
| ⌥⌘N | Nummern einfügen | F7 | Zeitstempel einfügen |
| ⌘F2 | Lesezeichen setzen/entfernen | F2 / ⌥F2 | Nächstes / vorheriges Lesezeichen |
| ⇧⌘K | Zeile löschen | ⇧⌘D | Zeile duplizieren |
| ⌥↑ / ⌥↓ | Zeile nach oben / unten | ⇧⌘J | Zeilen verbinden |
| ⌃⌘= | Berechnen | ⌃⌘T | Tabelle ausrichten |
| ⌘/ | Kommentieren | ⌃⌘J | JSON formatieren |
| ⇧⌘I | Snippet einfügen | Tab | Snippet expandieren / nächster Tabstopp |
| ⇧⌘M | Makro aufzeichnen / stoppen | ⌥⌘M | Makro abspielen |
| ⌥⌘← / ⌥⌘→ | Einklappen / Ausklappen | ⌥⇧⌘← / ⌥⇧⌘→ | Alle einklappen / alle ausklappen |
| ⌘\\ | Editor teilen | ⌥⌘\\ | Anderen Bereich aktivieren |
| ⇧⌘N | Schnelleingabe | ⌃⌥N | Schnelleingabe aus jeder App (einstellbar) |
| ⌘1 | Seitenleiste | ⌘2 | Unteres Panel |
| ⌘3 | Gliederung | ⌘4 | Zeitleiste |
| ⌥⌘L | Zeilennummern | ⌥Z | Zeilenumbruch |
| ⇧⌘P | Markdown-Vorschau | ⌃⌘H | Syntaxfarben |
| ⌥⌘] / ⌥⌘[ | Nächstes / vorheriges Theme | ⌘= / ⌘- / ⌘0 | Vergrößern / verkleinern / zurücksetzen |
| ⌥⌘S | Geheime Blöcke einblenden / maskieren | ⌘, | Einstellungen |
| ⌃⌘L | HyperEdit sperren (Touch ID) | | |
| ⌘Q | Beenden (sichert zuerst) | | |

## 20. Dateien, die HyperEdit schreibt

HyperEdit rührt nur die Dateien an, die du öffnest, und seine eigenen Daten:

| Pfad | Inhalt |
|---|---|
| `~/Documents/HyperEdit/notes.md` | Das Standarddokument (wird beim ersten Start angelegt, falls es fehlt) |
| `~/Library/Application Support/HyperEdit/snapshots/` | Schnappschüsse vor dem Sichern und Notfallkopien |
| `~/Library/Application Support/HyperEdit/bookmarks/` | Eine JSON-Datei pro Dokument mit Lesezeichen |
| `~/Library/Application Support/HyperEdit/snippets.json` | Deine Snippets |
| `~/Library/Application Support/HyperEdit/grammars/` | Benutzerdefinierte Grammatiken (`*.json`), mit `example.json` und einer README |
| `~/Library/Application Support/HyperEdit/macros/macros.json` | Gesicherte Makros |
| `~/Library/Preferences/io.github.hyeongcheol-an.hyperedit.plist` | Einstellungen, einschließlich der Sprache der Oberfläche |

Nichts wird neben deine Dokumente geschrieben, und nichts verlässt deinen Mac.

## 21. Fehlerbehebung

- **Die Sprache hat sich nicht geändert.** Die neue Sprache gilt nach einem Neustart – benutze **Jetzt neu starten** in den Einstellungen oder beende die App und öffne sie erneut. Ist die Systemsprache eine, die HyperEdit nicht hat, zeigt es Englisch; wähle in den Einstellungen ausdrücklich eine Sprache.
- **Eine Datei lässt sich nicht öffnen.** Binärdateien öffnen sich absichtlich in ihrer Standard-App. Eine Textdatei in einer anderen Codierung als UTF-8, EUC-KR, CP1252 oder Latin-1 wird abgewiesen, statt beschädigt zu werden; wandle sie zuerst mit einem anderen Werkzeug um.
- **Der systemweite Kurzbefehl für die Schnelleingabe tut nichts.** Eine andere App belegt vielleicht die Kombination, oder ⌃Space / ⌃⌥Space ist in den Systemeinstellungen › Tastatur durch den Wechsel der Eingabequelle belegt. Wähle in den Einstellungen ⌃⌥N oder ⌃⌥⌘N. Das Panel „Ausgabe“ meldet beim Start das Ergebnis der Registrierung.
- **Koreanischer Text wirkt in Tabellen zu breit oder zu schmal.** Installiere D2Coding oder passe die Hangul-Skalierung in den Einstellungen an; die Breitenkorrektur 2:1 braucht eine dicktengleiche Hangul-Schrift.
- **Ich habe versehentlich etwas gesichert.** Öffne den Schnappschuss-Ordner (**Ablage › Schnappschuss-Ordner öffnen**): Dort liegt die Kopie, die vor dem ersten Sichern der Sitzung angelegt wurde, plus alle Kopien, die beim Erkennen externer Änderungen gemacht wurden.
- **Das Menüband zeigt nur Symbole.** Das Fenster ist für diesen Tab zu schmal; verbreitere es oder fahre mit der Maus über ein Symbol, um seine Beschriftung zu sehen.

## 22. Bekannte Einschränkungen

- Syntaxfarben folgen Blockkommentaren, mehrzeiligen Strings und Markdown-Zäunen über Zeilen hinweg, unterstützt werden aber – abgesehen von Rust-Raw-Strings – nur String-Trennzeichen, die gleich öffnen und schließen, und ein Blockkommentar-Paar pro Sprache; benutzerdefinierte Grammatiken sind Wortlisten ohne Regeln mit regulären Ausdrücken. Die Markdown-Vorschau ist eine Ansicht, kein Editor.
- Makros zeichnen nur Tastaturbearbeitungen auf (keine Maus-, Auswahl- oder Multi-Cursor-Schritte). Berechnen und Tabelle ausrichten beherrschen nur einfache Arithmetik und Tab- / Pipe-Tabellen.
- Snippets, Makros und benutzerdefinierte Grammatiken werden als JSON-Dateien bearbeitet; es gibt keinen grafischen Editor dafür.
- Der Export schreibt nur das ganze Dokument – ohne Export einer Auswahl oder mehrerer Dateien, ohne Seiten- oder Schriftoptionen und ohne PDF-Inhaltsverzeichnis.
- Geheime Blöcke werden nur auf dem Bildschirm maskiert: Die Datei, automatische Sicherungen und Schnappschüsse sind reiner Text, der Maskierungsbalken zeigt, wie lang jede Zeile ist, und VoiceOver liest den Text weiterhin vor. Ein geheimer Zaun muss am linken Rand beginnen (weniger als vier Leerzeichen eingerückt, nicht in einem Listenpunkt oder Zitat), und ein eingezäunter Block innerhalb eines geheimen Blocks braucht vier Backticks am äußeren Zaun. Die App-Sperre verbirgt das Fenster und seinen Inhalt auch vor VoiceOver; sie verschlüsselt nichts.
- Blockkommentare lassen sich nicht verschachteln, und Dateien mit klassischen Mac-Zeilenenden (nur CR) werden zeilenweise eingefärbt. Innerhalb eines einzelnen Absatzes mit mehr als 20.000 Zeichen fallen Block- und Unterstrich-Cursor auf den normalen Balken-Cursor zurück.
- Faltungen bleiben für die Sitzung erhalten und werden nicht pro Datei gesichert; ein Mausziehen über eine eingeklappte Zeile wählt den verborgenen Text trotzdem aus.
- Dokumente, die aus einer einzigen Zeile von einem Megabyte oder mehr bestehen, lassen sich nur langsam öffnen und durchlaufen; „JSON minifizieren“ warnt, bevor es eine solche erzeugt.
- Nur lokale Dateien; keine Cloud-Synchronisierung und noch keine iOS-App.
- Andere als die elf aufgeführten Sprachen fallen auf Englisch zurück.

## 23. Geheime Blöcke und App-Sperre

**Geheime Blöcke.** Ein eingezäunter Codeblock, dessen Info-String mit `secret` beginnt, wird im Editor maskiert:

````markdown
```secret bank
login: me@example.com
password: hunter2
```
````

Jede Zeile zwischen den Zäunen wird als leerer Balken mit `••••••••` gezeichnet; die Zaunzeilen bleiben sichtbar, damit du siehst, wo der Block ist und wofür er dient. Die Regel gilt gleichermaßen in Markdown- und reinen Textdateien. Bewege den Cursor in den Block – per Klick, mit ↑ / ↓, Gehe zu Zeile, einem Suchtreffer oder einem Lesezeichen –, und der ganze Block wird sichtbar und bearbeitbar; verlässt der Cursor ihn, wird er wieder maskiert. Nur die Anzeige ändert sich: Der Text steht weiterhin in der Datei, sodass Suchen, Ersetzen, Widerrufen und Sichern genau wie zuvor funktionieren.

- **Geheimnisse einblenden (⌥⌘S)** im Menü „Bearbeiten“ zeigt alle Blöcke auf einmal; nach **Einstellungen › Geheimnisse › Erneut maskieren nach** (10 / 30 / 60 s, Standard 30 s, oder Nie) werden sie wieder maskiert, und das Panel „Ausgabe“ protokolliert es. Die Statusleiste zeigt währenddessen `REVEALED` und `•••• N`, solange N Blöcke maskiert sind. **Bearbeiten › Geheime Blöcke maskieren** schaltet die Maskierung ganz aus.
- Geheime Zeilen werden in den Listen „Suchergebnisse“ und „In Dateien suchen“ (Treffer und Zeilennummer funktionieren weiterhin) und in Lesezeichen-Vorschauen als `••••••••` angezeigt, von Gliederung und Zeitleiste übersprungen und in der Markdown-Vorschau sowie in HTML- / PDF-Exporten unkenntlich gemacht. Beim Beenden von HyperEdit wird ein ausstehendes Leeren der Zwischenablage sofort ausgeführt.
- **Zwischenablage automatisch leeren.** Überschneidet sich ein Kopieren oder Ausschneiden mit einer geheimen Zeile – auch beim Kopieren mit Multi-Cursor und im Spaltenmodus –, wird die Zwischenablage nach **Einstellungen › Geheimnisse › Zwischenablage nach Kopieren eines Geheimnisses leeren** (Aus / 10 / 30 / 60 s, Standard 30 s) geleert, sofern du nicht zwischendurch etwas anderes kopiert hast. **Bearbeiten › Zwischenablage leeren** leert sie sofort, und das Ausschalten der Maskierung schaltet auch das automatische Leeren aus.
- Geheime Blöcke lassen sich wie jeder eingezäunte Block einklappen (⌥⌘←).

> Maskieren ist keine Verschlüsselung. Die Datei, automatische Sicherungen und Schnappschüsse sind reiner Text, und wer die Datei hat, kann die Geheimnisse lesen. Die Funktion hält sie während der Arbeit von deinem Bildschirm, aus Bildschirmfotos, Suchergebnissen, der Vorschau und Exporten fern.

**App-Sperre (Touch ID).** **HyperEdit › HyperEdit sperren (⌃⌘L)** (das Programmmenü, unter Einstellungen…) verdeckt das ganze Fenster – Menüband, Seitenleiste, Editor, Panels und Statusleiste – mit einem undurchsichtigen Sperrbildschirm im aktuellen Theme, schließt ein offenes Einstellungsfenster und blendet das Schnelleingabe-Fenster aus. Solange gesperrt ist, wird nichts vom Dokument angezeigt, nicht einmal der Dateiname. Klicke auf **Entsperren** (oder drücke Return oder die Leertaste), um dich mit **Touch ID** zu authentifizieren; schlägt Touch ID fehl oder hat der Mac keines, greift macOS auf dein Anmeldepasswort zurück. Das Sperren schließt außerdem jeden offenen Dialog und jede Meldung, maskiert eingeblendete Geheimnisse wieder und führt ein ausstehendes Leeren der Zwischenablage sofort aus. Abbrechen lässt HyperEdit gesperrt, und die Taste versucht es erneut.

- **Einstellungen › App-Sperre.** *Touch ID oder Passwort zum Öffnen von HyperEdit verlangen* (standardmäßig aus) startet die App gesperrt: Das Dokument wird geladen und das automatische Sichern läuft weiter, aber nichts ist sichtbar, bis du dich authentifizierst. *Bei Inaktivität sperren* (Nie / 1 / 5 / 15 / 30 Minuten, Standard Nie) sperrt nach so langer Zeit ohne Tastendruck oder Klick in HyperEdit, unabhängig von der Startoption. *Sperren, wenn der Mac in den Ruhezustand wechselt oder der Bildschirm gesperrt wird* (standardmäßig ein) gilt, solange die Startoption eingeschaltet ist, und greift auch, wenn die Displays in den Ruhezustand wechseln. Ein Hinweistext sagt dir, ob Touch ID auf diesem Mac verfügbar ist.
- Im gesperrten Zustand wird die Tastatureingabe verschluckt, und die Menüleiste lässt sich nicht öffnen; nur ⌘Q, ⌘H / ⌥⌘H, ⌘M, ⌘W, ⌃⌘F und das Dock-Menü funktionieren noch. Der systemweite Kurzbefehl der Schnelleingabe zeigt statt des Fensters die Entsperrabfrage und öffnet das Fenster, sobald du dich authentifiziert hast.
- Dies ist eine Sichtschutzsperre für den Bildschirm, keine Verschlüsselung: Die Dateien auf der Festplatte bleiben unverändert und für jede andere App lesbar. Die Option *Touch ID oder Passwort … verlangen* lässt sich nicht einschalten, solange der Mac weder Touch ID noch ein Anmeldepasswort hat, sodass du dich nicht aussperren kannst.

## 24. Hilfe erhalten

- Fehlerberichte und Ideen: [GitHub Issues](https://github.com/Hyeongcheol-An/HyperEdit/issues) und [Discussions](https://github.com/Hyeongcheol-An/HyperEdit/discussions).
- Sicherheitsprobleme: siehe [SECURITY.md](../../SECURITY.md) für vertrauliche Meldungen.
- Übersetzungen: Die Texte der Oberfläche liegen im Repository unter `l10n/ui.<language>.json` und dieses Handbuch unter `docs/guide/`; Korrekturen sind als Pull Requests willkommen – siehe [CONTRIBUTING.md](../../CONTRIBUTING.md).

HyperEdit ist freie Software unter der MIT-Lizenz. Sein Layout ist vom klassischen UltraEdit-Menüband inspiriert; UltraEdit ist eine Marke von IDM Computer Solutions, Inc., und HyperEdit steht in keiner Verbindung zu IDM.
