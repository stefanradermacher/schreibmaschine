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

Die Schreibmaschine schreibt eine Datei nur, wenn du sie mit ⌘S sicherst. Zeichenkodierung und Zeilenenden erkennt sie beim Öffnen und behält sie beim Sichern bei. Beides steht in der Statusleiste und lässt sich dort per Klick ändern. Die gängigen Kodierungen stehen direkt im Menü, alle übrigen, die macOS kennt, unter „Weitere Kodierungen“, nach Schriftraum geordnet. Erscheinen Umlaute falsch, liest „Ablage → Erneut öffnen mit Kodierung“ die Datei in einer anderen Kodierung.

Ändert ein anderes Programm eine offene Datei, etwa git oder ein zweiter Editor, lädt die Schreibmaschine sie von selbst neu, solange du nichts Ungesichertes darin hast; Einfügemarke und Scrollposition bleiben, wo sie waren. Hast du ungesicherte Änderungen, fragt eine Leiste unter der Titelleiste: „Neu laden“ übernimmt die Datei, „Behalten“ bleibt bei deinem Text, den ⌘S dann über die Datei schreibt, und „Vergleichen“ stellt beides nebeneinander: Unterschiede aus der Datei übernimmst du in deinen Text und sicherst das Ergebnis. Wird eine offene Datei gelöscht oder verschoben, bleibt dein Text erhalten und gilt als ungesichert; „Sichern unter …“ legt ihn wieder ab.

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

# Schreiben

## Zählen

Links in der Statusleiste steht, wie viele Wörter der Text hat, bei einer Auswahl etwa „12 von 1.234 Wörtern“. Ein Klick darauf zeigt alle Zählungen, also Wörter, Zeichen, Zeichen ohne Leerzeichen, Zeilen und Absätze, und lässt wählen, welche in der Leiste steht.

## Schreibmaschinen-Modus

Unter „Darstellung → Schreibmaschinen-Modus“ bleibt die Zeile mit der Einfügemarke in der Mitte des Fensters stehen, und der Text läuft an ihr vorbei, wie das Papier in einer Schreibmaschine. Der Blick bleibt dabei immer an derselben Stelle.

## Ablenkungsfreier Modus

„Darstellung → Ablenkungsfreier Modus“ (⌃⇧⌘F) zeigt den Text im Vollbild in einer schmalen Spalte, ohne Statusleiste, Seitenleisten und Zeilennummern. Die Breite der Spalte steht in den Einstellungen unter „Schreiben“. Derselbe Befehl oder das Verlassen des Vollbilds bringt alles zurück, wie es vorher war.

## Fokus-Modus

Unter „Darstellung → Fokus-Modus“ bleibt nur der Absatz mit der Einfügemarke kräftig, der übrige Text tritt zurück. Genau genommen ist es die Zeile mit der Einfügemarke; in Fließtext, in dem jeder Absatz eine Zeile ist, also der ganze Absatz.

> Die drei Modi lassen sich verbinden: Im ablenkungsfreien Modus mit Schreibmaschinen- und Fokus-Modus steht der aktuelle Absatz mitten im Bildschirm, und alles andere tritt zurück.

## Markdown-Vorschau

In einer Markdown-Datei zeigt „Darstellung → Markdown-Vorschau“ (⌥⌘P) rechts neben dem Text, wie er gesetzt aussieht: Überschriften, Hervorhebungen, Listen und Aufgabenlisten, Zitate, Codeblöcke, Tabellen und Links. Die Vorschau folgt dem Tippen nach einem kurzen Augenblick und scrollt mit, ausgerichtet an den Überschriften. Links öffnen sich im Browser. Die Vorschau lädt nichts aus dem Internet; Bilder neben der Datei zeigt sie nur, wenn die Schreibmaschine sie lesen darf, sonst steht an ihrer Stelle ihre Beschreibung.

# Code

Die Schreibmaschine erkennt die Sprache einer Datei an Name, Endung oder erster Zeile und färbt sie entsprechend. Mitgeliefert werden Swift, Markdown, PHP, JavaScript und TypeScript, Python, JSON, YAML, INI und TOML, Shell, HTML, XML, CSS, SQL und Lua. Die Sprache lässt sich unter „Format → Sprache“ oder in der Statusleiste wählen.

![Swift mit Syntaxhervorhebung, Zeilennummern und Lesezeichen](docs/screenshots/1-code.jpg)

## Einrückung

Ob eine Datei mit Tabs oder Leerzeichen eingerückt ist und wie breit, erkennt die Schreibmaschine aus dem Text. Ändern lässt es sich unter „Format → Einrückung“ oder in der Statusleiste. ⇥ und ⇧⇥ rücken eine Auswahl über mehrere Zeilen ein und aus, ↩ übernimmt die Einrückung der Zeile davor.

## Kommentare und Klammern

⌘/ setzt oder entfernt Kommentarzeichen vor den Zeilen der Auswahl. ⌥⌘/ schließt die Auswahl, ohne Auswahl die Zeile, in einen Blockkommentar wie /* … */ oder <!-- … --> ein; steht die Einfügemarke in einem Blockkommentar, nimmt es ihn wieder heraus. Sprachen ohne Blockkommentare bekommen Zeilenkommentare. Die Klammer neben der Einfügemarke und ihr Gegenstück werden hervorgehoben, ⇧⌘M springt zum Gegenstück.

## Faltung

Blöcke, die tiefer eingerückt sind als die Zeile davor, lassen sich falten. ⌃⌘← faltet den Block um die Einfügemarke, ⌃⌘→ entfaltet ihn, mit ⇧ dazu gilt es für alles. Im Zeilenlineal erscheinen Pfeile, sobald die Maus darüber ist. Hinter einer gefalteten Zeile steht ⋯, ein Klick darauf entfaltet sie.

# Eigene Sprachen

Jede Sprache ist eine kleine YAML-Datei mit regulären Ausdrücken. „Format → Sprache → Definition dieser Sprache bearbeiten“ öffnet eine Kopie der mitgelieferten Definition, die du anpassen kannst. Neue Sprachen legst du in den Ordner, den „Ordner mit eigenen Sprachen zeigen“ öffnet. Beim Sichern wird eine Änderung sofort wirksam; enthält die Datei einen Fehler, nennt die Schreibmaschine die Zeile.

## Aufbau einer Definition

- name, extensions, filenames und interpreters: wie die Sprache heißt und woran sie erkannt wird
- comment: Zeichen für Zeilen- und Blockkommentare, für ⌘/ und ⌥⌘/
- indent: Breite der Einrückung und ob mit Tabs eingerückt wird
- rules: die Regeln zum Färben, jede mit einem scope wie keyword, string oder comment

## Regeln

Eine Regel nennt entweder Wörter (words), ein Muster in einer Zeile (match) oder einen Bereich von begin bis end, der auch über mehrere Zeilen gehen darf. In jeder Zeile gewinnt die Regel, die am frühesten trifft; Kommentare und Zeichenketten gehören deshalb nach oben.

> Reguläre Ausdrücke stehen am besten in einfachen Anführungszeichen, darin gilt der Backslash als gewöhnliches Zeichen: '\d+' bleibt \d+.

# Vergleichen

„Ablage → Vergleichen“ stellt zwei Texte nebeneinander: das Dokument mit seiner gesicherten Fassung, mit dem Inhalt der Zwischenablage, mit einem anderen offenen Dokument oder mit einer Datei. Der Vergleich öffnet sich in einem eigenen Fenster, das sich wie jedes andere zu den Tabs ziehen lässt.

Beide Seiten scrollen gemeinsam. Wo auf einer Seite Zeilen fehlen, lässt die Schreibmaschine Platz, sodass zusammengehörige Zeilen auf gleicher Höhe stehen. Keine Seite gilt als die ältere: Zeilen, die es nur auf einer Seite gibt, sind blau, egal auf welcher; Zeilen, die sich unterscheiden, sind rot, die abweichenden Zeichen darin kräftiger. Auf Wunsch sind auch die gleichen Zeilen grün („Gleiche Zeilen grün“ unten rechts), sonst bleiben sie weiß. Die Leiste am rechten Rand zeigt alle Unterschiede im ganzen Text, ein Klick springt hin.

## Unterschiede abarbeiten

⌃⌘↓ und ⌃⌘↑ oder die Pfeile unten links springen zum nächsten und vorigen Unterschied; daneben steht „Unterschied 3 von 12“. Beide Seiten sind gewöhnliche Editoren, der Vergleich folgt dem Tippen. Ein Klick in die linke Hälfte eines Blocks im Mittelstreifen übernimmt ihn von rechts nach links, ein Klick in die rechte Hälfte umgekehrt; ⌘Z nimmt das zurück. ⌘S sichert die Seite, in der die Einfügemarke steht. Gesicherte Fassung und Zwischenablage sind nur zum Lesen da.

## Optionen und Ergebnis

Unten rechts lassen sich Leerraum und Groß-/Kleinschreibung ignorieren. „Unterschiede kopieren“ und „Unterschiede als neues Dokument“ geben den Vergleich als Unified Diff weiter, wie ihn `diff -u` schreibt.

# Skripte

Eigene Umformungen lassen sich als Skripte in jeder Sprache schreiben, die auf dem Mac läuft: Shell, Perl, Ruby, Swift oder was sonst installiert ist. Sie liegen im Skriptordner, den „Skripte → Skriptordner öffnen“ im Finder zeigt, und erscheinen im Menü „Skripte“ und in der Befehlspalette. Neue Skripte sind sofort da. Unterordner werden zu Untermenüs, eine Nummer vor dem Namen bestimmt nur die Reihenfolge: „01 Sortieren.sh“ heißt im Menü „Sortieren“. „Beispielskripte installieren …“ legt drei Beispiele in den Ordner.

Ein Skript bekommt Text über die Standardeingabe und gibt Text über die Standardausgabe zurück. Es muss ausführbar sein (im Terminal: chmod +x) und mit einer Zeile wie #!/bin/zsh beginnen. Ohne weitere Angaben bekommt es die Auswahl, ohne Auswahl das ganze Dokument, und sein Ergebnis ersetzt genau das. Ein Zweizeiler mit sort ist so schon ein eigener Sortierbefehl. Den Pfad der Datei bekommt es als erstes Argument.

## Eingabe und Ausgabe

Zwei Zeilen am Anfang des Skripts, in seiner Kommentarschreibweise, ändern das:

- @input selection: die Auswahl, ohne Auswahl das Dokument (so ohne Angabe)
- @input document: immer das ganze Dokument
- @input none: nichts
- @output replace-selection: ersetzt, was hineinging (so ohne Angabe)
- @output replace-document: ersetzt das ganze Dokument
- @output insert: fügt hinter der Auswahl ein
- @output new-document: öffnet ein neues Dokument
- @output copy: legt das Ergebnis in die Zwischenablage
- @output none: verwirft das Ergebnis

Ein Ergebnis zu ersetzen ist ein Schritt, den ⌘Z zurücknimmt. Endet ein Skript mit einem Fehler, zeigt die Schreibmaschine, was es auf die Fehlerausgabe geschrieben hat. Ändert sich der Text, während ein Skript läuft, setzt sie das Ergebnis nicht ein, sondern bietet es als neues Dokument an.

> Skripte laufen außerhalb der Sandbox der Schreibmaschine, mit deinen Rechten; sie können alles, was ein Programm im Terminal kann. Lege nur Skripte in den Ordner, denen du traust.

# Darstellung und Einstellungen

Zeilennummern (⌥⌘L), Zeilenumbruch (⌃⌘W) und unsichtbare Zeichen (⌥⌘I) gelten für jedes Fenster einzeln. Neben den Zeilennummern zeigt ein schmaler Balken, welche Zeilen seit dem letzten Sichern neu oder geändert sind, und ein kleiner Keil, wo Zeilen gelöscht wurden; nach dem Sichern verschwinden die Marken. Ob und in welchen Farben sie erscheinen, legt „Einstellungen → Editor → Änderungen im Lineal“ fest. ⌘+ und ⌘- ändern die Schriftgröße, ⌘0 stellt sie zurück.

## Blättern und springen

Bild ↑ und Bild ↓ blättern um eine Fensterhöhe und nehmen die Einfügemarke mit. Pos1 und Ende gehen an Anfang und Ende der Zeile, ⌘Pos1 und ⌘Ende (wie ⌘↑ und ⌘↓) an Anfang und Ende des Dokuments; mit ⇧ wird jeweils ausgewählt. Pos1 und ⌘← springen zuerst hinter die Einrückung, ein zweites Mal an den echten Zeilenanfang. Wer das Verhalten von macOS bevorzugt, bei dem diese Tasten nur blättern, schaltet es in den Einstellungen unter Editor aus.

## Die Statusleiste

Unten im Fenster stehen Zeile und Spalte, die Größe der Auswahl, Sprache, Einrückung, Zeichenkodierung und Zeilenenden. Alles außer der Position lässt sich per Klick ändern.

## Einstellungen

- Allgemein: was beim Start ohne Datei geschieht, Tabs oder Fenster, die Standard-App für Text und Code, Kodierung und Zeilenenden für neue Dokumente
- Editor: Schrift, Zeilenhöhe (von +0 % bis +100 % über das, was die Schrift braucht, voreingestellt +20 %), Tabbreite, Einrückung, Umbruchspalte, Vorgaben für neue Fenster, Syntaxhervorhebung, Hervorhebung der aktuellen Zeile und Änderungen im Lineal
- Schreiben: Schreibmaschinen-Modus, Fokus-Modus und die Breite der Textspalte im ablenkungsfreien Modus

Soll die Schreibmaschine Textdateien per Doppelklick öffnen, legt „Allgemein → Standard-App → Als Standard festlegen“ sie dafür fest: für reinen Text, Markdown, JSON, YAML, XML, CSS, JavaScript, Swift, Python, PHP, Shell-Skripte, SQL, Lua, TOML und INI sowie Diff. macOS fragt dabei für jedes Format einzeln nach. „Anpassen …“ zeigt alle Formate mit der App, die sie gerade öffnet, und legt jedes einzeln fest, auch HTML, CSV und Protokolle, die sonst meist in Browser, Tabellenkalkulation und Konsole bleiben. „Zurücksetzen“ gibt die Formate der App zurück, die sie vorher hatten. Nach einigen Tagen fragt die Schreibmaschine auch selbst einmal in einem Balken unter der Titelleiste nach, höchstens zweimal.

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
| Zeilen verbinden | ⇧⌘J |
| Einrücken, Ausrücken | ⌘], ⌘[ |
| Zeilen-, Blockkommentar, passende Klammer | ⌘/, ⌥⌘/, ⇧⌘M |
| Auswahl erweitern, verkleinern | ⌥↑, ⌥↓ |
| Nächstes Vorkommen dazu auswählen | ⌃G |
| Alle Treffer auswählen | ⌃⌘G |
| Einfügemarke in jeder Zeile der Auswahl | ⇧⌘L |
| Lesezeichen setzen, nächstes, voriges | ⌘B, ⌥⌘↓, ⌥⌘↑ |
| Falten, Entfalten (mit ⇧: alles) | ⌃⌘←, ⌃⌘→ |
| Nebeneinander, untereinander teilen | ⌃⌘T, ⌃⌥⌘T |
| Zur anderen Hälfte, Teilung aufheben | ⌥⌘J, ⌃⇧⌘W |
| Dokumentliste | ⌃⌘S |
| Nächster, voriger Unterschied im Vergleich | ⌃⌘↓, ⌃⌘↑ |
| Markdown-Vorschau, ablenkungsfreier Modus | ⌥⌘P, ⌃⇧⌘F |
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

## Wie groß darf eine Datei sein?

So groß, wie der Arbeitsspeicher erlaubt. Eine Logdatei von 100 MB mit einer Million Zeilen öffnet in etwa einer Sekunde, und Sprünge an jede Stelle gehen sofort. Zeilen mit mehr als 10.000 Zeichen, etwa in minifiziertem JSON, bleiben ungefärbt. Enthält eine Datei eine Zeile mit mehr als 100.000 Zeichen, öffnet ihr Fenster mit Zeilenumbruch, weil eine so lange Zeile ohne Umbruch viel Zeit und Speicher kostet; ⌃⌘W schaltet ihn trotzdem ab.

## Warum sucht die Schreibmaschine nicht in Ordnern?

Weil sie keine Projekte kennt. Die Suche in allen offenen Dokumenten deckt ab, was gerade in Arbeit ist; für Ordner gibt es den Finder und Werkzeuge auf der Kommandozeile.

## Was bringen mir die Trinkgelder?

Nichts außer meinem Dank. Sie schalten keine Funktionen frei; die Schreibmaschine ist und bleibt vollständig kostenlos.
