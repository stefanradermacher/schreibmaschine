# Schreibmaschine – Konzept

Stand: 28. September 2026

Die Schreibmaschine ist ein schlichter Texteditor für macOS: vor allem für einfachen Text, der oft umgeformt wird, aber genauso brauchbar für Code. Er soll kein IDE-Ersatz und kein Alleskönner sein. Vorbilder sind KWrite und CotEditor. Von CotEditor übernimmt er den Funktionsumfang, macht aber Suchen, Fenster und Wiederherstellung anders.

Englischer Name ebenfalls „Schreibmaschine“, im App Store mit erklärendem Zusatz (etwa „Schreibmaschine – Text Editor“).

## Leitlinien

- **Gleiche Grundlinie wie Leser und Motiv:** Xcode-Projekt, macOS 15+, Sandbox, App Store, Apache 2.0, Deutsch und Englisch, nur Apple-Frameworks, keine Netzwerkverbindungen, kein Tracking.
- **Durchschaubar:** Was die App beim Beenden behält und beim Start wieder öffnet, lässt sich jederzeit sehen und steuern.
- **Im Fenster statt daneben:** Suchen, Ersetzen und „Gehe zu“ laufen in Leisten im Editor, nicht in eigenen Fenstern oder Panels.
- **Tastatur zuerst:** Jede Funktion ist über eine Befehlspalette erreichbar, die wichtigsten auch über ein Tastenkürzel.
- **Pro Datei merken:** Cursor, Scrollposition, Faltungen, Kodierung, Sprache und Umbruch gehören zur Datei und bleiben erhalten.

## 1. Suchen und Ersetzen

Eine Leiste oben im Editor, wie in PhpStorm. Kein eigenes Fenster.

- **⌘F** öffnet die Suchleiste, **⌥⌘F** klappt zusätzlich die Ersetzen-Zeile auf. Eine vorhandene Auswahl wird Suchbegriff. **Esc** schließt die Leiste und setzt den Cursor an den aktuellen Treffer.
- Die Suche läuft **live**: Alle Treffer werden im Text und in der Scrollleiste markiert, daneben steht „3 von 17“.
- **↩** und **⇧↩** springen zum nächsten und vorigen Treffer, **⌘G** und **⇧⌘G** genauso bei geschlossener Leiste.
- **Schalter** direkt im Feld: Groß-/Kleinschreibung (Aa), ganzes Wort (W), regulärer Ausdruck (.*), nur in der Auswahl. Der Zustand der Schalter ist immer sichtbar.
- Ist ein regulärer Ausdruck ungültig, färbt sich das Feld rot und ein kurzer Hinweis erklärt den Fehler. Es gibt kein Dialogfenster.
- **Ersetzen:** „Ersetzen“ ersetzt den aktuellen Treffer und geht zum nächsten (wie in PhpStorm, ↩ im Ersetzen-Feld), „Alle ersetzen“ ersetzt alle. Bei regulären Ausdrücken zeigt eine Vorschau, was aus dem aktuellen Treffer wird (`$1`, `\n`, `\t`). „Alle ersetzen“ lässt sich in einem Schritt widerrufen.
- **Alle Treffer auswählen** (⌃⌘G): Aus jedem Treffer wird eine Auswahl, an der man gleichzeitig tippt.
- Mehrzeilige Suchbegriffe sind möglich, das Feld wächst dann mit. Ein Verlauf der letzten Begriffe ist über ↓ oder ein Menü am Feld erreichbar.
- **Gehe zu Zeile** (⌘L) nutzt dieselbe Leiste: `120`, `120:15` (Spalte), `+10`, `-10`.
- **In allen offenen Dokumenten suchen** (⇧⌘F): eine Trefferliste in einer Seitenleiste, gegliedert nach Dokument, jeweils mit Zeilennummer und Zeile. Ein Klick springt zum Treffer. „Alle ersetzen“ gilt für alle offenen Dokumente und lässt sich in jedem Dokument einzeln widerrufen. Eine Suche in Ordnern oder Projekten gibt es bewusst nicht.

## 2. Fenster, Tabs und Wiederherstellung

### Das Problem

Bei CotEditor wie bei den meisten Mac-Apps übernimmt die Fensterwiederherstellung von macOS diese Aufgabe. Ob sie greift, hängt von der Systemeinstellung „Fenster beim Beenden einer App schließen“ ab, davon, ob man mit ⌘Q oder ⌥⌘Q beendet, und davon, ob die App abgestürzt ist. Deshalb ist es undurchsichtig, was nach einem Neustart wiederkommt.

### Die Lösung: eine eigene, sichtbare Sitzung

Die Schreibmaschine schaltet die Systemwiederherstellung ab und verwaltet ihre **Sitzung** selbst:

- Eine Sitzung ist: alle Fenster mit Position und Größe, darin die Tabs in ihrer Reihenfolge, je Tab eine Datei oder ein ungesicherter Text, und die geteilten Ansichten.
- **Einstellung „Beim Start“**, ausdrücklich und mit drei Möglichkeiten:
  - letzte Sitzung wiederherstellen,
  - leeres Dokument,
  - nichts öffnen.
- Die Einstellung gilt unabhängig von der Systemeinstellung und von der Art, wie man beendet hat. Nach einem Absturz wird immer wiederhergestellt, was da war.
- **Die Einstellung gilt nur für einen Start ohne Datei.** Startet die App, weil man eine Datei geöffnet hat (Doppelklick im Finder, „Öffnen mit“, Ziehen aufs Dock-Symbol, `open` im Terminal), öffnet sie genau diese Datei in einem Fenster und sonst nichts: keine alte Sitzung, kein leeres Dokument, keine Dateien von früher. Läuft die App schon, kommt die Datei als Tab ins vordere Fenster oder, je nach Einstellung, in ein neues Fenster. Ist sie schon offen, wird ihr Tab nach vorn geholt.
- **Die nicht wiederhergestellte Sitzung geht dabei nicht verloren.** Sie bleibt als „Vorige Sitzung“ gespeichert und lässt sich über Fenster → Sitzung → „Vorige Sitzung wiederherstellen“ zurückholen, auch zusätzlich zu dem, was gerade offen ist. Enthielt sie ungesicherte Texte, bleiben diese erhalten, bis man sie öffnet oder ausdrücklich verwirft. Nur dann wird eine alte Sitzung durch eine neue ersetzt.
- **Menü Fenster → Sitzung:** zeigt als Liste, was gerade zur Sitzung gehört und was beim nächsten Start wiederkommt. Dort gibt es außerdem „Letzte Sitzung wiederherstellen“, falls man ohne Wiederherstellung gestartet hat.
- **Ungesicherte Texte gehen nie verloren.** Unbenannte Dokumente und ungesicherte Änderungen werden laufend in den Container der App gesichert (wie bei BBEdit oder Sublime Text). Beim Beenden gibt es keine Nachfrage. Wer ein unbenanntes Dokument schließt, wird gefragt, ob er es sichern oder verwerfen will, denn Schließen ist eine bewusste Handlung, Beenden nicht.
- Dateien, die seit dem letzten Mal fehlen oder verschoben wurden, erscheinen nicht stillschweigend als leere Tabs. Stattdessen nennt ein Hinweis beim Start die fehlenden Dateien.
- In der Sandbox braucht jede Datei ein Security-Scoped Bookmark, damit sie nach dem Neustart wieder geöffnet werden darf. Die Sitzung speichert deshalb Bookmarks, keine Pfade.

### Pro Datei gemerkt

Cursor und Auswahl, Scrollposition, Faltungen, Lesezeichen, Kodierung, Zeilenenden, Sprache, Umbruch und Einrückung. Gespeichert wird das als JSON im Container, mit dem Pfad der Datei als Schlüssel (Bookmarks taugen nicht als Schlüssel, sie ändern sich bei jedem Erzeugen). Die Datei selbst bleibt unverändert, es werden auch keine erweiterten Attribute geschrieben. Die Kodierung wird nur gemerkt, wenn man sie mit „Erneut öffnen mit Kodierung“ selbst gewählt hat; sonst erkennt die App sie jedes Mal neu.

### Fenster und Tabs

- Die App verwendet die nativen Fenster-Tabs von macOS. Neue Dokumente öffnen standardmäßig als Tab im vorderen Fenster, alternativ in einem neuen Fenster (Einstellung).
- **Geteilte Ansicht** innerhalb eines Tabs, waagerecht oder senkrecht, mit zwei Ansichten desselben Dokuments.
- Eine **Dokumentliste** als optionale Seitenleiste zeigt alle offenen Dokumente aller Fenster, mit Markierung für ungesicherte Änderungen.

## 3. Text bearbeiten und umformen

Das ist der Kern für Plain Text. Alle Befehle wirken auf die Auswahl, ohne Auswahl auf die aktuelle Zeile oder, wo es sinnvoller ist, auf das ganze Dokument. Sie liegen in einem Menü **Text** und sind alle über die Befehlspalette erreichbar.

- **Zeilen:** verbinden (Join Lines, mit wählbarem Trennzeichen), teilen an Trennzeichen, duplizieren, löschen, nach oben und unten verschieben, sortieren (alphabetisch, numerisch, natürlich, rückwärts), Dubletten entfernen, umkehren, mischen, nummerieren, leere Zeilen entfernen.
- **Absätze:** auf Spaltenbreite umbrechen, Umbrüche innerhalb von Absätzen entfernen (Unwrap), einrücken und ausrücken, als Zitat markieren (`> `) und die Markierung wieder entfernen.
- **Leerraum:** Leerzeichen am Zeilenende entfernen, Tabs in Leerzeichen umwandeln und umgekehrt, mehrfache Leerzeichen zusammenfassen.
- **Schreibweise:** GROSS, klein, Satzanfang groß, Titel, camelCase, snake_case, kebab-case.
- **Spalten:** an einem Zeichen ausrichten (z. B. an `=` oder `|`), Markdown-Tabellen formatieren.
- **Kodieren:** URL, Base64, HTML-Entitäten, JSON formatieren und verkleinern.
- **Kommentare** umschalten (je nach Sprache).
- **Erneut ausführen** (⌘R): Der zuletzt ausgeführte Textbefehl lässt sich erneut ausführen, mit denselben Parametern.
- **Einrücken und Ausrücken:** ⌘] und ⌘[, außerdem ⇥ und ⇧⇥ bei einer Auswahl über mehrere Zeilen.

**Befehlspalette** (⇧⌘P): Man tippt ein paar Buchstaben und findet jeden Befehl, jede Sprache, jede Kodierung und jedes Benutzerskript. Zuletzt benutzte Befehle stehen oben.

**Tastenkürzel:** Grundsätzlich gilt der macOS-Standard. Dazu kommen einige Kürzel aus PhpStorm, die keine wichtige macOS-Belegung verdrängen:

| Kürzel | Befehl |
|---|---|
| ⌘D | Zeile oder Auswahl duplizieren |
| ⌥⇧↑ / ⌥⇧↓ | Zeile oder Auswahl nach oben / unten verschieben |
| ⌘⌫ | Zeile löschen (ohne Auswahl) |
| ⇧⌘J | Zeilen verbinden (wie in CotEditor) |
| ⌘/ | Kommentar umschalten |
| ⌥↑ / ⌥↓ | Auswahl erweitern / verkleinern (Wort → Zeichenkette → Klammer → Zeile → Absatz) |
| ⌃G | nächstes Vorkommen der Auswahl zusätzlich auswählen |
| ⌃⌘G | alle Vorkommen auswählen |

⌘↑ und ⌘↓ bleiben beim macOS-Standard (Anfang und Ende des Dokuments), deshalb verschiebt ⌥⇧↑/↓ die Zeilen, wie in PhpStorm auf dem Mac. Alle Kürzel lassen sich über die Systemeinstellungen („Tastatur → Tastaturkurzbefehle → App-Tastaturkurzbefehle“) ändern, weil sie ganz normale Menübefehle sind.

## 4. Code

- Zeilennummern, aktuelle Zeile hervorheben, Umbruch ein/aus, Umbruchlinie bei einer wählbaren Spalte.
- **Syntaxhervorhebung** mit eigenen, schlanken Sprachdefinitionen auf Basis regulärer Ausdrücke. Mitgeliefert werden Markdown, Swift, PHP, JSON, YAML, Shell, HTML, CSS, SQL, Lua und einige weitere.
- **Eigene Sprachen:** Sprachdefinitionen sind YAML-Dateien, damit sie sich leicht von Hand bearbeiten lassen. Eigene Definitionen legt man in einen Ordner oder importiert sie. Die mitgelieferten lassen sich duplizieren und anpassen. Das ist der „Plugin“-Weg für Sprachen.
- **Idee für später, noch nicht entschieden: Farbthemen.** Bisher gelten die Farben des Standardthemas von Xcode, hell und dunkel. Als Format für eigene Themen böte sich Base16 an: eine kleine YAML-Datei mit 16 Farben und einer festen Zuordnung zu Hintergrund, Kommentaren, Schlüsselwörtern, Zeichenketten und so weiter, die fast eins zu eins auf unsere Scopes passt. Davon gibt es Hunderte, darunter Fassungen von Solarized, Gruvbox, Nord, Dracula und Tomorrow. Eigene Themen kämen wie eigene Sprachen in einen Ordner. Mitgeliefert würden nur wenige (Xcode hell und dunkel, vielleicht Solarized); bei mitgelieferten Dateien gehört der jeweilige Lizenzhinweis dazu, meist MIT.
- Einrückung mit Tabs oder Leerzeichen und automatisches Einrücken, beides pro Sprache voreingestellt und pro Datei änderbar. Die Einrückung bestehender Dateien wird erkannt.
- Passende Klammern hervorheben, zur passenden Klammer springen.
- **Code-Faltung** nach Einrückung und nach Klammern.
- **Lesezeichen:** setzen und entfernen, zum nächsten und vorigen springen. Sie werden pro Datei gemerkt.
- **Block- und Mehrfachauswahl:** ⌥-Ziehen wählt ein Rechteck aus, ⌘-Klick setzt weitere Cursor. Tippen wirkt an allen Cursorn gleichzeitig.

## 5. Schreiben

- **Markdown-Vorschau:** neben dem Text oder in einem eigenen Tab, sie wird live aktualisiert und scrollt mit dem Text mit. Bilder neben der Datei werden gezeigt, soweit die Sandbox es erlaubt, externe Inhalte nicht geladen.
- **Schreibmaschinen-Modus:** Die aktuelle Zeile bleibt in der Mitte des Fensters stehen.
- **Ablenkungsfreier Modus:** Vollbild ohne Toolbar, Statusleiste und Seitenleisten, mit schmaler Textspalte. Auf Wunsch wird alles außer dem aktuellen Absatz abgedunkelt.
- **Idee für später: „Ganze Schreibmaschine“** als verspielter Zusatz zum ablenkungsfreien Modus, sozusagen das volle Programm; standardmäßig aus. Der Text steht auf einem Blatt fester Breite (der Textspalte) mit sichtbarem Papierrand. Die Einfügemarke bleibt fest an einer Stelle des Bildschirms, wo der Typenhebel anschlägt, und das Blatt bewegt sich: Mit jedem Anschlag rückt es eine Zeichenbreite nach links wie der Wagen, ↩ fährt es in einer kurzen Animation zurück und eine Zeile nach oben. Wahlweise bricht die Zeile am Rand von selbst um; dann fährt der Wagen in diesem Moment zurück, wie nach ↩. Pfeiltasten und Mausklicks bewegen ebenfalls das Blatt. Normale Texte sollen sich so schreiben lassen, Korrekturen inklusive. Technisch eine Erweiterung des Schreibmaschinen-Modus um die waagerechte Richtung.
- **Dazu, wahlweise: Schreibmaschinengeräusche.** Jeder Tastenschlag klingt wie eine echte Schreibmaschine, idealerweise jede Type etwas anders, die Leertaste anders als die Typen; die Glocke klingelt einige Zeichen vor dem rechten Rand, Wagenrücklauf bei ↩ und beim automatischen Umbruch. Wählbar zwischen mechanischer und elektrischer Maschine. Die Klänge kommen entweder aus eigener Synthese (`scripts/make_sounds.swift` erzeugt Hörproben nach `Klangproben/`) oder aus Aufnahmen unter CC0; dann wäre „keine Fremdkomponenten“ ehrlich einzuschränken. Abgespielt mit `AVAudioEngine` und vorgeladenen Puffern, damit schnelles Tippen nicht verzögert.
- Rechtschreibprüfung (vom System), Zählung von Wörtern, Zeichen und Zeilen in der Statusleiste, für die Auswahl getrennt.

## 6. Dateien

- **Kodierung** wird erkannt und lässt sich umstellen (UTF-8, UTF-16, ISO-8859-1, Windows-1252, Mac Roman …), auch als „erneut öffnen mit Kodierung …“. BOM ja/nein.
- **Zeilenenden** LF, CRLF oder CR werden erkannt und lassen sich umstellen. Gemischte Zeilenenden werden gemeldet.
- Unsichtbare Zeichen einblenden (Leerzeichen, Tabs, Zeilenenden, geschützte und unsichtbare Unicode-Zeichen).
- Wird eine Datei außerhalb der App geändert, lädt die App sie automatisch neu, sofern es im Editor keine ungesicherten Änderungen gibt. Sonst erscheint eine Leiste im Fenster (kein Dialog) mit „Neu laden“ und „Behalten“.
- **Große Dateien und lange Zeilen:** Beim Öffnen prüft die App die Dateigröße und die längste Zeile. Überschreitet eine davon einen Schwellenwert, fragt sie: „Normal öffnen“, „Einfach öffnen“ (ohne Hervorhebung, Umbruch und Faltung, Zeilennummern bleiben) oder „Abbrechen“. Die Schwellenwerte lassen sich einstellen. Ein Neustart wie bei KWrite ist nicht nötig, weil macOS keine feste Speichergrenze hat.

## 7. Benutzerskripte

Skripte in `~/Library/Application Scripts/<Bundle-ID>/` erscheinen in einem Menü **Skripte** und in der Befehlspalette. Das ist der Weg, den Apple für Sandbox-Apps vorsieht. Ein Skript kann in jeder Sprache geschrieben sein, die auf dem Mac läuft. Es bekommt die Auswahl oder das Dokument über die Standardeingabe und gibt Text zurück. Ein Kopfkommentar legt fest, ob der Text die Auswahl ersetzt, eingefügt wird oder ein neues Dokument wird. So lassen sich eigene Umformungen bauen, ohne dass sie in die App gehören.

## 8. Vergleichen

Zwei Texte nebeneinander vergleichen, nach dem Vorbild von Beyond Compare, aber beschränkt auf Text.

- **Was sich vergleichen lässt:** zwei Dateien, zwei offene Dokumente, ein Dokument mit seiner gesicherten Fassung auf der Platte, ein Dokument mit einer älteren Version (aus den Versionen von `NSDocument`), die Auswahl oder ein Dokument mit der Zwischenablage. Starten lässt sich der Vergleich über Ablage → Vergleichen, die Befehlspalette, die Dokumentliste (zwei Dokumente auswählen) oder indem man zwei Dateien zugleich aufs Dock-Symbol zieht und dabei ⌥ hält.
- **Darstellung:** Beide Texte stehen nebeneinander in einem eigenen Tab und scrollen gemeinsam. Leerzeilen gleichen fehlende Zeilen aus, sodass zusammengehörige Zeilen auf gleicher Höhe stehen. Geänderte Zeilen sind farbig markiert, eingefügte und gelöschte Zeilen ebenfalls. Innerhalb einer geänderten Zeile sind die abweichenden Zeichen stärker hervorgehoben. Ein Mittelstreifen verbindet die Blöcke, eine Übersichtsleiste am Rand zeigt alle Unterschiede im ganzen Text.
- **Bearbeiten:** Beide Seiten sind normale Editoren. Der Vergleich wird beim Tippen laufend neu berechnet. Pfeile im Mittelstreifen übernehmen einen Block nach links oder rechts. Beide Seiten lassen sich sichern.
- **Navigation:** ⌥⌘↓ und ⌥⌘↑ springen zum nächsten und vorigen Unterschied. Die Statusleiste zeigt „Unterschied 3 von 12“.
- **Optionen:** Leerraum ignorieren (ganz, nur am Zeilenende oder nur in der Menge), Groß-/Kleinschreibung ignorieren, Zeilenenden ignorieren, nur Unterschiede mit etwas Umgebung zeigen und gleiche Bereiche einklappen.
- **Ergebnis weitergeben:** als Unified Diff in ein neues Dokument oder in die Zwischenablage.
- **Nicht vorgesehen:** Ordnervergleich, Dreiwegevergleich und Zusammenführen, Vergleich von Binärdateien, Tabellen oder Bildern.

## Bewusst nicht

Code-Plugins (in der Sandbox nicht erlaubt), LSP, Autovervollständigung über Wörter im Dokument hinaus, Git, Terminal, Projektverwaltung, Build und Debugging, Vi-Modus, Synchronisation eigener Einstellungen über einen Server.

## Technik

- AppKit mit `NSDocument` und `NSTextView` auf TextKit 2. Die SwiftUI-Textansicht reicht dafür nicht. SwiftUI kommt für Einstellungen und kleinere Leisten zum Einsatz.
- `NSDocument` liefert Autosichern, Versionen und „Zurück auf“. Die Fensterwiederherstellung übernimmt die eigene Sitzung (siehe 2).
- Folgendes kann `NSTextView` nicht von selbst und muss gebaut werden: Zeilennummern unter TextKit 2, gleichzeitiges Tippen an mehreren Cursorn (Rechteckauswahl gibt es schon, Eingabe daran nicht), Code-Faltung (über das Ausblenden von Absätzen im `NSTextContentManager`), Markierungen in der Scrollleiste. Das sind die technisch anspruchsvollsten Teile.
- Ob die App mit einer Datei gestartet wurde, zeigt das Apple Event beim Start (`kAEOpenDocuments` statt `kAEOpenApplication`). Erst danach entscheidet die App, ob sie eine Sitzung wiederherstellt.
- Vergleich: zeilenweise mit dem Histogram-Verfahren (wie `git diff --histogram`, liefert besser lesbare Blöcke als reines Myers), innerhalb geänderter Zeilen zeichenweise mit Myers. Beides ist eigener Code und läuft im Hintergrund, damit das Tippen flüssig bleibt.
- Die Syntaxhervorhebung arbeitet inkrementell und nur auf dem sichtbaren Bereich plus Rand, damit auch große Dateien flüssig bleiben.
- Markdown-Vorschau: der Markdown-Leser, den macOS mitbringt (`AttributedString(markdown:)` mit der vollen Syntax: auch Tabellen und Durchstreichen; Aufgabenlisten ergänzt die App selbst). So braucht die App keinen fremden Parser. Die Ausgabe als HTML übernimmt eigener Code, angezeigt wird sie in einem `WKWebView`, dem eine Content-Security-Policy jeden Netzzugriff verbietet. Weil WebKit in der Sandbox nur mit der Berechtigung für ausgehende Verbindungen startet, hat die App diese Berechtigung, nutzt sie aber nicht. Ursprünglich war Apples Paket `swift-markdown` vorgesehen; es hätte genauere Positionen für das Mitscrollen geliefert, aber eine Fremdkomponente (cmark-gfm) mitgebracht.
- YAML: Apple liefert keinen YAML-Parser mit. Statt einer fremden Bibliothek liest ein eigener, kleiner Parser genau die Teilmenge, die Sprachdefinitionen brauchen: Zuordnungen, Listen, Zeichenketten in einfachen und doppelten Anführungszeichen, Block-Zeichenketten mit `|` und Kommentare. Was er nicht versteht, meldet er mit Zeilennummer.

## Meilensteine

1. **Grundgerüst:** Projekt, Dokument, Öffnen und Sichern, Kodierung, Zeilenenden, Zeilennummern, Umbruch, unsichtbare Zeichen, Schrift, Einstellungen, `build.sh` und `bump-build.sh`.
2. **Sitzung und Persistenz:** eigene Wiederherstellung, Status pro Datei, ungesicherte Texte sichern, Menü „Sitzung“.
3. **Suchleiste:** Suchen und Ersetzen, Gehe zu Zeile.
4. **Textbefehle und Befehlspalette.**
5. **Syntaxhervorhebung:** Sprachdefinitionen, Einrückung, Klammern, Kommentare.
6. **Fortgeschrittenes Bearbeiten:** Mehrfach- und Blockauswahl, Faltung, Lesezeichen, geteilte Ansicht, Dokumentliste.
7. **Schreiben:** Markdown-Vorschau, Schreibmaschinen-Modus, ablenkungsfreier Modus.
8. **Vergleichen.**
9. **Große Dateien, Benutzerskripte, Handbuch, Icon, App Store.**

Nach Meilenstein 3 ist die App schon für den Alltag mit Plain Text brauchbar.

## Entschieden

- **Markdown:** der Markdown-Leser von macOS, Vorschau in einer Webansicht ohne Netzzugriff.
- **Tastenkürzel:** macOS-Standard mit einzelnen PhpStorm-Kürzeln (siehe 3).
- **Suchen:** in allen offenen Dokumenten ja, in Ordnern oder Projekten nein.
- **Sprachdefinitionen:** YAML, gelesen von einem eigenen Parser für die benötigte Teilmenge.
