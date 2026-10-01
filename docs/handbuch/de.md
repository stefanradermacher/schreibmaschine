<!--
Texte des Handbuchs. Daraus erzeugt `swift scripts/make_manual.swift` das PDF
(mit „en“ die englische Fassung).

Oben stehen die Angaben für Titelseite und Dokumentinformationen, danach der Inhalt:
  # Kapitel             beginnt eine neue Seite und einen Eintrag in der Gliederung
  ## Überschrift        Zwischenüberschrift
  Text                  Absatz; Zeilenumbrüche sind egal, eine Leerzeile trennt Absätze
                        (das gilt auch für die Angaben oben)
  - Punkt               Aufzählungspunkt
  > Hinweis             Text im farbigen Kasten
  ![Text](Pfad)         Bildschirmfoto über die ganze Breite, darunter der Text;
                        fehlt die Datei, wird es ausgelassen
  | Befehl | Kürzel |   Zeile der Tastaturkürzel-Tabelle

Im Fließtext heißt die App „die Schreibmaschine“, in Menünamen und Titeln steht der Name allein.
-->

Dokumenttitel: Schreibmaschine – Handbuch
Thema: Texteditor für macOS
Untertitel: Handbuch zum Texteditor für macOS
Leitsatz: Für Text und Code.
Einleitung: Kein IDE-Ersatz, sondern ein Werkzeug zum Schreiben: mit Suchleiste, Textbefehlen und einer Sitzung, die nichts vergisst.
Kostenlos, werbefrei und ohne Datensammlung.

# Über dieses Handbuch

Die Schreibmaschine ist ein Texteditor für macOS: vor allem für einfachen Text, der oft umgeformt wird, aber genauso brauchbar für Code. Sie will keine Entwicklungsumgebung sein, sondern ein Werkzeug zum Schreiben. Dieses Handbuch beschreibt in wenigen Kapiteln, was sie kann und wie sie sich bedienen lässt.

## Was die Schreibmaschine ausmacht

- Suchen und Ersetzen in einer Leiste über dem Text, nicht in einem eigenen Fenster
- Ein Menü voller Textbefehle und eine Befehlspalette, die jeden Befehl findet
- Eine eigene Sitzung, die Fenster, Tabs und ungesicherte Texte nie verliert
- Syntaxhervorhebung, Einrückung, Klammern und Faltung für Code
- Mehrere Einfügemarken, Lesezeichen und eine geteilte Ansicht
- Kostenlos und quelloffen unter der Apache-Lizenz 2.0, ohne Werbung und ohne Datensammlung
- Nur Apple-Frameworks, keine Fremdkomponenten
- Deutsch und Englisch

# Dokumente und Fenster

Textdateien öffnest du per Doppelklick, über „Ablage → Öffnen …“ (⌘O) oder indem du sie auf das Symbol der Schreibmaschine im Dock ziehst. Ein neues Dokument legst du mit ⌘N an.

## Tabs oder Fenster

Neue Dokumente kommen als Tab ins vordere Fenster oder in ein eigenes Fenster, so wie es in den Einstellungen unter „Neue Dokumente öffnen“ steht. Die Einstellung „Tabs bevorzugen“ von macOS spielt dabei keine Rolle. Tabs lassen sich wie überall auf dem Mac zu Fenstern machen und wieder zusammenführen.

## Zwischen Dokumenten wechseln

⌥⌘→ und ⌥⌘← gehen zum nächsten und vorigen Dokument, über alle Fenster hinweg. ⌘1 bis ⌘8 springen zu den ersten acht Dokumenten, ⌘9 zum letzten. Die Reihenfolge zeigt „Fenster → Dokumente“. ⌃⇥ wechselt wie gewohnt zwischen den Tabs eines Fensters.

## Die Dokumentliste

Mit ⌃⌘S erscheint links eine Liste aller offenen Dokumente, bei mehreren Fenstern nach Fenster gegliedert. Ein Punkt hinter dem Namen zeigt ungesicherte Änderungen, ein Klick holt das Dokument nach vorn.

## Sichern, Kodierung und Zeilenenden

Die Schreibmaschine schreibt eine Datei nur, wenn du sie mit ⌘S sicherst. Zeichenkodierung und Zeilenenden erkennt sie beim Öffnen und behält sie beim Sichern bei. Beides steht in der Statusleiste und lässt sich dort per Klick ändern. Erscheinen Umlaute falsch, liest „Ablage → Erneut öffnen mit Kodierung“ die Datei in einer anderen Kodierung.

# Die Sitzung

Viele Mac-Apps überlassen es macOS, nach dem Neustart wieder zu öffnen, was offen war. Ob das klappt, hängt von Systemeinstellungen und der Art des Beendens ab. Die Schreibmaschine führt deshalb ihre eigene Sitzung: alle Fenster mit ihren Tabs, die Dateien darin und alle ungesicherten Texte.

## Nichts geht verloren

Ungesicherte Texte und Änderungen sichert die Schreibmaschine laufend in ihrem eigenen Bereich auf dem Mac, nicht in deinen Dateien. Beim Beenden fragt sie deshalb nicht nach. Beim nächsten Start kommt alles zurück, als geändert markiert, auch nach einem Absturz.

## Start mit einer Datei

Startest du die Schreibmaschine ohne Datei, stellt sie die letzte Sitzung wieder her, öffnet ein neues Dokument oder nichts, je nach Einstellung. Öffnest du dagegen eine Datei aus dem Finder, erscheint nur diese. Die Sitzung davor bleibt als „vorige Sitzung“ erhalten: „Fenster → Sitzung → Vorige Sitzung wiederherstellen“ holt sie zurück.

> „Fenster → Sitzung“ zeigt jederzeit, was zur Sitzung gehört und was beim nächsten Start wiederkommt.

## Jede Datei merkt sich ihren Zustand

Für jede Datei merkt sich die Schreibmaschine Auswahl, sichtbaren Ausschnitt, Umbruch, Zeilennummern, Schriftgröße, Lesezeichen, Faltungen und eine geteilte Ansicht. Beim nächsten Öffnen ist alles wieder so, wie du es verlassen hast. Die Datei selbst bleibt dabei unverändert.

# Suchen und Ersetzen

⌘F öffnet die Suchleiste über dem Text, ⌥⌘F zusätzlich die Ersetzen-Zeile. Gesucht wird beim Tippen. Alle Treffer sind im Text markiert und am rechten Rand als Striche zu sehen, daneben steht, der wievielte Treffer gerade ausgewählt ist.

![Die Suchleiste mit allen Treffern im Text](docs/screenshots/2-suche.jpg)

## Weitersuchen

↩ und ⇧↩ springen zum nächsten und vorigen Treffer, ⌘G und ⇧⌘G auch bei geschlossener Leiste. Eine Auswahl wird beim Öffnen zum Suchbegriff, ⌘E übernimmt sie ohne die Leiste zu öffnen. Die letzten 20 Begriffe stehen im Menü der Lupe im Suchfeld, ↓ öffnet es ebenfalls. Esc schließt die Leiste.

## Schalter

- Aa: Groß- und Kleinschreibung beachten
- W: nur ganze Wörter
- .*: reguläre Ausdrücke; ein ungültiger Ausdruck wird rot gemeldet
- Nur in der Auswahl suchen

## Ersetzen

„Ersetzen“ ersetzt den aktuellen Treffer und geht zum nächsten, „Alle ersetzen“ ersetzt alle in einem einzigen Widerrufen-Schritt. Bei regulären Ausdrücken setzt $1 Gruppen ein, \n und \t stehen für Zeilenumbruch und Tab, und eine Vorschau zeigt das Ergebnis.

## In allen offenen Dokumenten

⇧⌘F sucht in allen offenen Dokumenten. Die Treffer stehen in einer Seitenleiste, nach Dokument gegliedert; ein Klick springt zur Stelle. „Alle ersetzen“ gilt für alle Dokumente, jedes kann es einzeln widerrufen. In Ordnern sucht die Schreibmaschine bewusst nicht.

## Gehe zu Zeile

⌘L öffnet dieselbe Leiste zum Springen: 120 geht zu Zeile 120, 120:15 zusätzlich zu Spalte 15, +10 und -10 springen relativ.

# Text umformen

Das Menü „Text“ enthält Befehle, die Text in einem Schritt umformen. Jeder Befehl lässt sich mit ⌘Z widerrufen, ⌘R führt den letzten noch einmal aus.

- Zeilen: duplizieren, löschen, verschieben, verbinden, teilen, sortieren, Dubletten entfernen, umkehren, mischen, nummerieren, leere Zeilen entfernen
- Absätze: umbrechen und Umbrüche entfernen, einrücken und ausrücken, als Zitat markieren
- Leerraum: Leerzeichen am Zeilenende entfernen, Tabs und Leerzeichen umwandeln
- Schreibweise: Groß- und Kleinschreibung, auch camelCase, snake_case und kebab-case
- Spalten: an einem Zeichen ausrichten, Markdown-Tabellen formatieren
- Kodieren: URL, Base64 und HTML, JSON formatieren oder verkleinern

## Ohne Auswahl

Ohne Auswahl wirkt ein Befehl auf das, was sinnvoll ist: Sortieren und Kodieren auf das ganze Dokument, Verschieben und Einrücken auf die Zeile, Umbrechen auf den Absatz, die Schreibweise auf das Wort an der Einfügemarke.

## Die Befehlspalette

⇧⌘P öffnet die Befehlspalette. Ein paar Buchstaben genügen, „zverb“ findet zum Beispiel „Zeilen verbinden“. Die Palette kennt jeden Menübefehl und zeigt Menüpfad und Tastenkürzel; die zuletzt benutzten Befehle stehen oben.

## Auswahl erweitern

⌥↑ erweitert die Auswahl Schritt für Schritt: Wort, Text in Anführungszeichen, Text in Klammern, Zeile, Absatz, alles. ⌥↓ geht zurück.

# Mehrere Stellen zugleich

## Mehrere Einfügemarken

Mit ⌘-Klick setzt du eine weitere Einfügemarke, mit ⌘-Ziehen eine weitere Auswahl. Tippen, Löschen, ↩, ⇥, die Pfeiltasten und Einsetzen wirken an allen Stellen zugleich. Stehen so viele Zeilen in der Zwischenablage wie Einfügemarken, bekommt jede ihre eigene Zeile. Esc oder ein einfacher Klick führt zu einer Einfügemarke zurück.

- ⌥-Ziehen wählt einen Block, mit einer Einfügemarke oder Auswahl in jeder Zeile
- ⌃G wählt das Wort an der Einfügemarke und dann jeweils das nächste Vorkommen dazu
- ⇧⌘L setzt ans Ende jeder Zeile der Auswahl eine Einfügemarke
- ⌃⌘G macht aus allen Treffern der Suche Auswahlen

## Lesezeichen

⌘B oder ein Klick auf die Zeilennummer setzt ein Lesezeichen, ein zweiter entfernt es. ⌥⌘↓ und ⌥⌘↑ springen zum nächsten und vorigen. „Bearbeiten → Lesezeichen“ listet alle mit dem Text ihrer Zeile. Lesezeichen wandern beim Bearbeiten mit ihrer Zeile und werden für jede Datei gemerkt.

## Die geteilte Ansicht

„Darstellung → Nebeneinander teilen“ (⌃⌘T) oder „Untereinander teilen“ (⌃⌥⌘T) zeigt den Text ein zweites Mal, mit eigener Auswahl und eigenem Ausschnitt. So lässt sich an einer Stelle schreiben und eine andere im Blick behalten. ⌥⌘J wechselt zur anderen Hälfte, ⌃⇧⌘W hebt die Teilung auf.

![Die geteilte Ansicht](docs/screenshots/3-geteilt.jpg)

# Code

Die Schreibmaschine erkennt die Sprache einer Datei an Name, Endung oder erster Zeile und färbt sie entsprechend. Mitgeliefert werden Swift, Markdown, PHP, JavaScript und TypeScript, Python, JSON, YAML, INI und TOML, Shell, HTML, XML, CSS, SQL und Lua. Die Sprache lässt sich unter „Format → Sprache“ oder in der Statusleiste wählen.

![Swift mit Syntaxhervorhebung, Zeilennummern und Lesezeichen](docs/screenshots/1-code.jpg)

## Einrückung

Ob eine Datei mit Tabs oder Leerzeichen eingerückt ist und wie breit, erkennt die Schreibmaschine aus dem Text. Ändern lässt es sich unter „Format → Einrückung“ oder in der Statusleiste. ⇥ und ⇧⇥ rücken eine Auswahl über mehrere Zeilen ein und aus, ↩ übernimmt die Einrückung der Zeile davor.

## Kommentare und Klammern

⌘/ setzt oder entfernt Kommentarzeichen vor den Zeilen der Auswahl. Die Klammer neben der Einfügemarke und ihr Gegenstück werden hervorgehoben, ⇧⌘M springt zum Gegenstück.

## Faltung

Blöcke, die tiefer eingerückt sind als die Zeile davor, lassen sich falten. ⌃⌘← faltet den Block um die Einfügemarke, ⌃⌘→ entfaltet ihn, mit ⇧ dazu gilt es für alles. Im Zeilenlineal erscheinen Pfeile, sobald die Maus darüber ist. Hinter einer gefalteten Zeile steht ⋯, ein Klick darauf entfaltet sie.

# Eigene Sprachen

Jede Sprache ist eine kleine YAML-Datei mit regulären Ausdrücken. „Format → Sprache → Definition dieser Sprache bearbeiten“ öffnet eine Kopie der mitgelieferten Definition, die du anpassen kannst. Neue Sprachen legst du in den Ordner, den „Ordner mit eigenen Sprachen zeigen“ öffnet. Beim Sichern wird eine Änderung sofort wirksam; enthält die Datei einen Fehler, nennt die Schreibmaschine die Zeile.

## Aufbau einer Definition

- name, extensions, filenames und interpreters: wie die Sprache heißt und woran sie erkannt wird
- comment: Zeichen für Zeilen- und Blockkommentare, für ⌘/
- indent: Breite der Einrückung und ob mit Tabs eingerückt wird
- rules: die Regeln zum Färben, jede mit einem scope wie keyword, string oder comment

## Regeln

Eine Regel nennt entweder Wörter (words), ein Muster in einer Zeile (match) oder einen Bereich von begin bis end, der auch über mehrere Zeilen gehen darf. In jeder Zeile gewinnt die Regel, die am frühesten trifft; Kommentare und Zeichenketten gehören deshalb nach oben.

> Reguläre Ausdrücke stehen am besten in einfachen Anführungszeichen, darin gilt der Backslash als gewöhnliches Zeichen: '\d+' bleibt \d+.

# Darstellung und Einstellungen

Zeilennummern (⌥⌘L), Zeilenumbruch (⌃⌘W) und unsichtbare Zeichen (⌥⌘I) gelten für jedes Fenster einzeln. ⌘+ und ⌘- ändern die Schriftgröße, ⌘0 stellt sie zurück.

## Die Statusleiste

Unten im Fenster stehen Zeile und Spalte, die Größe der Auswahl, Sprache, Einrückung, Zeichenkodierung und Zeilenenden. Alles außer der Position lässt sich per Klick ändern.

## Einstellungen

- Allgemein: was beim Start ohne Datei geschieht, Tabs oder Fenster, Kodierung und Zeilenenden für neue Dokumente
- Editor: Schrift, Tabbreite, Einrückung, Umbruchspalte, Vorgaben für neue Fenster, Syntaxhervorhebung und Hervorhebung der aktuellen Zeile

Als Schrift ist SF Mono voreingestellt, die Monospace-Schrift von macOS. Weil macOS sie in der Schriftenpalette nicht anzeigt, führt der Knopf „Standard“ zu ihr zurück.

# Tastaturkürzel

Alle Kürzel sind normale Menübefehle. In den Systemeinstellungen unter „Tastatur → Tastaturkurzbefehle → App-Tastaturkurzbefehle“ lassen sie sich ändern.

| Suchen, Suchen und ersetzen | ⌘F, ⌥⌘F |
| Weitersuchen, Rückwärts suchen | ⌘G, ⇧⌘G |
| In allen offenen Dokumenten suchen | ⇧⌘F |
| Gehe zu Zeile | ⌘L |
| Befehlspalette | ⇧⌘P |
| Letzten Textbefehl erneut ausführen | ⌘R |
| Zeile duplizieren, löschen | ⌘D, ⌘⌫ |
| Zeilen verschieben | ⌥⇧↑, ⌥⇧↓ |
| Zeilen verbinden | ⌃⇧J |
| Einrücken, Ausrücken | ⌘], ⌘[ |
| Kommentar umschalten | ⌘/ |
| Zur passenden Klammer | ⇧⌘M |
| Auswahl erweitern, verkleinern | ⌥↑, ⌥↓ |
| Nächstes Vorkommen dazu auswählen | ⌃G |
| Alle Treffer auswählen | ⌃⌘G |
| Einfügemarke in jeder Zeile der Auswahl | ⇧⌘L |
| Lesezeichen setzen, nächstes, voriges | ⌘B, ⌥⌘↓, ⌥⌘↑ |
| Falten, Entfalten (mit ⇧: alles) | ⌃⌘←, ⌃⌘→ |
| Nebeneinander, untereinander teilen | ⌃⌘T, ⌃⌥⌘T |
| Zur anderen Hälfte, Teilung aufheben | ⌥⌘J, ⌃⇧⌘W |
| Dokumentliste | ⌃⌘S |
| Nächstes, voriges Dokument | ⌥⌘→, ⌥⌘← |
| Dokument 1 bis 8, letztes Dokument | ⌘1 – ⌘8, ⌘9 |
| Schrift vergrößern, verkleinern, zurücksetzen | ⌘+, ⌘-, ⌘0 |
| Zeilennummern, Umbruch, unsichtbare Zeichen | ⌥⌘L, ⌃⌘W, ⌥⌘I |

# Fragen und Antworten

## Ist die Schreibmaschine eine Entwicklungsumgebung?

Nein, und das bleibt so. Es gibt keine Projekte, keine Autovervollständigung und kein Bauen oder Ausführen. Die Schreibmaschine ist ein Werkzeug zum Schreiben und Umformen von Text, der auch Code sein darf.

## Wo bleiben meine ungesicherten Texte, wenn ich die App beende?

Sie bleiben in der Sitzung und kommen beim nächsten Start zurück. In eine Datei geschrieben wird nur mit ⌘S. Ein unbenanntes Dokument, das du selbst schließt, fragt dagegen, ob es gesichert werden soll; Schließen ist eine bewusste Handlung, Beenden nicht.

## Ich habe eine Datei aus dem Finder geöffnet, und meine anderen Fenster sind weg.

Startet die Schreibmaschine wegen einer Datei, zeigt sie nur diese. „Fenster → Sitzung → Vorige Sitzung wiederherstellen“ holt die anderen Fenster zurück.

## Warum sucht die Schreibmaschine nicht in Ordnern?

Weil sie keine Projekte kennt. Die Suche in allen offenen Dokumenten deckt ab, was gerade in Arbeit ist; für Ordner gibt es den Finder und Werkzeuge auf der Kommandozeile.

## Was bringen mir die Trinkgelder?

Nichts außer meinem Dank. Sie schalten keine Funktionen frei; die Schreibmaschine ist und bleibt vollständig kostenlos.
