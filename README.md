# Schreibmaschine

Schlichter Texteditor für macOS 15+, gebaut mit AppKit und TextKit 2. Vor allem für einfachen Text, der oft umgeformt wird, aber genauso brauchbar für Code. Kein IDE-Ersatz; Vorbilder sind KWrite und CotEditor.

Die Schreibmaschine ist quelloffen (Apache-Lizenz 2.0, siehe `LICENSE`), werbefrei und übermittelt keine Daten: kein Tracking, keine Analyse, keine eigenen Netzwerkverbindungen.

Nicht Teil des lizenzierten Werks sind die Kennzeichen des Projekts: der Name „Schreibmaschine“, das App- und das Dokumentsymbol und `scripts/make_icon.swift`, das diese Symbole zeichnet. Was damit erlaubt ist, steht in `TRADEMARKS.md`. `NOTICE` hält den Umfang fest und ist nach Abschnitt 4(d) der Lizenz bei jeder Weitergabe mitzuführen.

Die Oberfläche gibt es auf Deutsch und Englisch. Die Texte liegen im String-Katalog `Resources/Localizable.xcstrings`; die Schlüssel sind die deutschen Sätze.

Was die App werden soll und in welcher Reihenfolge, steht in `docs/konzept.md`.

## Stand: Meilenstein 5

- **Dokumente:** Öffnen, Sichern, Sichern unter, Zurück zur gesicherten Version, Drucken. Gesichert wird nur mit ⌘S; die Datei ändert sich nie von selbst.
- **Kodierung:** wird beim Öffnen erkannt (Byte Order Mark, UTF-16, UTF-8, dann die eingestellte Standardkodierung, bei anderen Schriften Foundations Schätzung, zuletzt Windows-1252 und ISO Latin 1) und beim Sichern beibehalten. Umstellen über Format → Zeichenkodierung oder die Statusleiste; lässt sich ein Zeichen in der neuen Kodierung nicht darstellen, nennt die App es vorher. Ablage → Erneut öffnen mit Kodierung liest die Datei in einer anderen Kodierung neu. Dateien mit Nullbytes gelten als Binärdateien und werden nicht geöffnet.
- **Zeilenenden:** Im Editor endet jede Zeile mit LF. Die Zeilenenden der Datei (LF, CRLF, CR) werden erkannt und beim Sichern wieder eingesetzt; gemischte Zeilenenden zeigt die Statusleiste an. Eingesetzter Text bekommt ebenfalls LF.
- **Editor:** Zeilennummern, Zeilenumbruch, unsichtbare Zeichen (jeweils pro Fenster im Menü Darstellung), aktuelle Zeile hervorgehoben, Schrift vergrößern und verkleinern (⌘+, ⌘−, ⌘0). Einrücken mit Leerzeichen oder Tabs, Einrückung der vorigen Zeile übernehmen, die Rücktaste springt im Einzug zum vorigen Tabstopp.
- **Statusleiste:** Zeile und Spalte, Größe der Auswahl, Sprache, Einrückung, Kodierung und Zeilenenden zum Anklicken.
- **Fenster:** Neue Dokumente öffnen als Tab im vorderen Fenster oder in einem eigenen Fenster (Einstellung), das erste Fenster mitten auf dem Bildschirm, weitere versetzt zum vorderen. Die Tab-Einstellung von macOS („Tabs bevorzugen: Immer“) greift nicht; ob ein Dokument als Tab kommt, entscheidet die Einstellung der App.
- **Dokumente wechseln:** ⌥⌘→ und ⌥⌘← (Fenster → Nächstes/Vorheriges Dokument) gehen zum nächsten und vorigen Dokument, über alle Fenster hinweg, am Ende wieder von vorn. ⌘1 bis ⌘8 springen zu den ersten acht Dokumenten, ⌘9 zum letzten. Die Reihenfolge ist die unter Fenster → Dokumente: Fenster in der Reihenfolge, in der sie geöffnet wurden, darin die Tabs von links nach rechts. ⌃⇥ und ⌃⇧⇥ wechseln wie überall auf dem Mac zwischen den Tabs eines Fensters.
- **Sitzung:** Die Fensterwiederherstellung von macOS ist abgeschaltet; die App führt eine eigene Sitzung aus Fenstern, Tabs und je Tab einer Datei oder einem ungesicherten Text (`Session.swift`). Sie wird wenige Sekunden nach jeder Änderung geschrieben und übersteht so auch einen Absturz. Beim Beenden fragt die App nie nach: Ungesicherte Texte und Änderungen bleiben als Pufferdateien im Container und kommen beim nächsten Mal wieder, als geändert markiert. Was zur Sitzung gehört, zeigt Fenster → Sitzung.
- **Start:** Ohne Datei gestartet, stellt die App die letzte Sitzung wieder her, öffnet ein neues Dokument oder nichts (Einstellung „Beim Start ohne Datei“); nach einem Absturz kommt die Sitzung in jedem Fall zurück. Mit einer Datei gestartet (Doppelklick, Öffnen mit, Dock, `open`), erscheint nur diese Datei. Die Sitzung davor wird zur vorigen Sitzung, die sich unter Fenster → Sitzung wiederherstellen oder verwerfen lässt; enthält sie ungesicherte Texte, wird sie nie stillschweigend ersetzt, sondern um die nächste ergänzt.
- **Fehlende Dateien:** Ist eine Datei der Sitzung gelöscht oder verschoben, nennt die App sie beim Start. Hatte sie ungesicherte Änderungen, kommt der Text als neues Dokument unter ihrem Namen zurück.
- **Zustand pro Datei:** Auswahl, oberste sichtbare Zeile, Umbruch, Zeilennummern, unsichtbare Zeichen und Schriftgröße merkt sich die App für jede Datei, ebenso eine Kodierung, die mit Erneut öffnen mit Kodierung gewählt wurde (`FileState.swift`, als JSON im Container, nach Pfad; die Datei selbst bleibt unberührt).
- **Suchen und Ersetzen:** eine Leiste oben im Editor (⌘F, mit Ersetzen ⌥⌘F), kein eigenes Fenster. Gesucht wird beim Tippen; alle Treffer sind im Text gelb hinterlegt und am rechten Rand als Striche markiert, daneben steht „3 von 17“. ↩ und ⇧↩ (oder ⌘G und ⇧⌘G, auch bei geschlossener Leiste) springen weiter, am Ende geht es vorn weiter. Schalter für Groß-/Kleinschreibung, ganze Wörter, reguläre Ausdrücke und die Suche nur in der Auswahl; ein ungültiger Ausdruck wird rot gemeldet. ⌥↩ setzt einen Zeilenumbruch in den Suchbegriff, das Feld wächst mit. Eine Auswahl wird beim Öffnen zum Suchbegriff; der Begriff wird wie auf dem Mac üblich mit anderen Apps geteilt (⌘E), die letzten 20 stehen im Verlauf (Uhr-Symbol oder ↓). Ersetzen ersetzt den aktuellen Treffer und geht zum nächsten, Alle ersetzen lässt sich in einem Schritt widerrufen; bei regulären Ausdrücken zeigt eine Vorschau das Ergebnis, `$1` setzt Gruppen ein, `\n` und `\t` Zeilenumbruch und Tab. Esc schließt die Leiste, auch aus dem Text heraus. Alle Treffer auswählen: ⌃⌘G.
- **Text umformen:** das Menü Text mit Zeilen (duplizieren ⌘D, löschen ⌘⌫, verschieben ⌥⇧↑/↓, verbinden ⌃⇧J oder mit wählbarem Trennzeichen, teilen, sortieren A–Z und Z–A mit natürlicher Zahlenfolge, nach Zahlen sortieren, Dubletten entfernen, umkehren, mischen, nummerieren, leere Zeilen entfernen), Absätze (umbrechen bei der eingestellten oder einer gewählten Spalte, Umbrüche entfernen, einrücken ⌘] und ausrücken ⌘[, als Zitat markieren), Leerraum, Schreibweise (auch camelCase, snake_case, kebab-case), Spalten (an einem Zeichen ausrichten, Markdown-Tabelle formatieren) und Kodieren (URL, Base64, HTML, JSON formatieren oder verkleinern, ohne die Reihenfolge der Schlüssel zu ändern). Die Befehle wirken auf die Auswahl; ohne Auswahl auf das, was sinnvoll ist: Sortieren und Kodieren auf das ganze Dokument, Verschieben und Einrücken auf die Zeile, Umbrechen auf den Absatz, die Schreibweise auf das Wort am Cursor. Leerraum und Zeilenumbrüche um eine Auswahl bleiben stehen. Jeder Befehl ist ein Widerrufen-Schritt mit seinem Namen; ⌘R führt den letzten noch einmal aus, mit demselben Wert. ⇥ und ⇧⇥ rücken eine mehrzeilige Auswahl ein und aus.
- **Auswahl erweitern** (⌥↑): Wort, Text in Anführungszeichen, Text in Klammern, Zeile, Absatz, alles; ⌥↓ geht zurück.
- **Befehlspalette** (⇧⌘P): jeder Menübefehl, gefunden mit ein paar Buchstaben („zverb“ für Zeilen verbinden), mit Menüpfad und Tastenkürzel; die zuletzt benutzten stehen oben. Sie liest die Menüs beim Öffnen, damit sind auch Kodierungen, Dokumente und Einstellungen dabei.
- **Syntaxhervorhebung:** für Swift, Markdown, PHP, JavaScript/TypeScript, Python, JSON, YAML, INI/TOML, Shell, HTML, XML, CSS, SQL und Lua. Die Sprache wird am Dateinamen, an der Endung oder an der ersten Zeile (`#!`, `<?xml`, `<?php`) erkannt und lässt sich unter Format → Sprache oder in der Statusleiste wählen; eine selbst gewählte Sprache merkt sich die App pro Datei. Gefärbt wird Zeile für Zeile beim Anzeigen, sodass auch lange Dateien flüssig bleiben (`SyntaxHighlighter.swift`); abschalten lässt es sich in den Einstellungen. Sprachdefinitionen sind YAML-Dateien mit regulären Ausdrücken (`Resources/Languages/`); eigene und angepasste liegen in einem Ordner im Container und ersetzen gleichnamige mitgelieferte. Das Format beschreibt `docs/sprachen.md`.
- **Einrückung pro Dokument:** Tabs oder Leerzeichen und die Breite erkennt die App aus dem Text, sonst gilt die Vorgabe der Sprache und zuletzt die Einstellung. Ändern unter Format → Einrückung oder in der Statusleiste; von Hand gewählt, merkt sie sich die App pro Datei.
- **Kommentare und Klammern:** ⌘/ setzt oder entfernt Zeilenkommentare (bei Sprachen ohne Zeilenkommentar einen Blockkommentar um die Auswahl). Die Klammer neben der Einfügemarke und ihr Gegenstück werden hervorgehoben, ⇧⌘M springt zum Gegenstück.
- **Gehe zu Zeile** (⌘L) in derselben Leiste: `120`, `120:15` (mit Spalte), `+10`, `-10`.
- **In allen offenen Dokumenten suchen** (⇧⌘F): eine Seitenleiste links mit den Treffern nach Dokument, jeweils mit Zeilennummer und Zeile; ein Klick holt das Dokument nach vorn und wählt den Treffer aus. Sie ist in allen Tabs dieselbe und bleibt sichtbar, wenn ein Klick in einen anderen Tab wechselt. Alle ersetzen gilt für alle offenen Dokumente, jedes kann es einzeln widerrufen. In Ordnern oder Projekten sucht Schreibmaschine bewusst nicht.

## Bauen

Die Schreibmaschine ist ein Xcode-Projekt (`Schreibmaschine.xcodeproj`, Xcode 27 oder neuer, macOS 15+). In Xcode öffnen und mit ⌘R starten; für einen signierten Build unter „Signing & Capabilities“ das eigene Team eintragen.

Ohne Xcode-Oberfläche:

```
./build.sh
```

Das baut `build/Schreibmaschine.app` mit `xcodebuild` (mit derselben Sandbox wie im App Store) und installiert die App nach `/Applications`. Läuft die Schreibmaschine gerade, wird sie vorher beendet und danach wieder geöffnet. Stammt die installierte App aus dem App Store, lässt `build.sh` sie unangetastet und meldet nur den Build. Nur bauen, ohne zu installieren: `./build.sh --no-install`.

Nennt `Config/Local.xcconfig` eine Team-ID, signiert `build.sh` mit diesem Team; Xcode legt App-ID und Entwicklungsprofil bei Bedarf im Entwicklerkonto an. Ohne Team-ID, oder mit `--adhoc`, signiert es ad hoc; die App läuft dann genauso.

Die Versionsnummer steht im Projekt unter „Version“ (`MARKETING_VERSION`) und wird von Hand erhöht. Die Build-Nummer steht als `CURRENT_PROJECT_VERSION` in `Config/Schreibmaschine.xcconfig` und ist damit eingecheckter Zustand: Xcode und `build.sh` lesen dieselbe Zahl, sie kann nicht sinken, und im Verlauf sieht man, welcher Commit welchen Build ergeben hat.

**Vor jedem Upload in den App Store einmal `./scripts/bump-build.sh` ausführen und mitcommitten** — App Store Connect verlangt für jeden Upload eine höhere Nummer als für den vorigen.

Das App-Icon und das Dokumentsymbol zeichnet `scripts/make_icon.swift`: das App-Icon in den Asset-Katalog, das Dokumentsymbol nach `Resources/TextDocument.icns`. Das App-Icon zeigt eine schwarze Schreibmaschine auf Stahlblau; Stahlblau ist auch die Akzentfarbe der App, und die Einfügemarke im Editor hat das Orange des Cursors im Symbol. Das Dokumentsymbol zeigt macOS nur, wenn Schreibmaschine die Standard-App für eine Dateiart ist. Nach Änderungen an der Zeichnung im Projektordner `swift scripts/make_icon.swift` ausführen.

### Projektstruktur

- `Sources/Schreibmaschine/`: Quellcode; neue Dateien gehören automatisch zum Projekt
  - `AppDelegate.swift`, `MainMenu.swift`: Start der App und Menüleiste, ohne Storyboard
  - `DocumentController.swift`, `TextDocument.swift`: Dokumente; jede Datei ist ein Textdokument, Kodierung, Byte Order Mark und Zeilenenden gehören zum Dokument
  - `TextEncoding.swift`, `LineEnding.swift`: Erkennen und Umwandeln von Kodierungen und Zeilenenden
  - `LineIndex.swift`: Zeilenanfänge, bei jeder Änderung schrittweise nachgeführt
  - `DocumentWindowController.swift`, `EditorViewController.swift`: Fenster und Tabs, Editoransicht
  - `DocumentNavigation.swift`: zwischen den offenen Dokumenten wechseln, Fenster → Dokumente
  - `Session.swift`, `FileState.swift`: die eigene Sitzung mit ungesicherten Texten, der Zustand pro Datei
  - `TextSearch.swift`, `FindBar.swift`, `SearchController.swift`: Suchen, Ersetzen und Gehe zu Zeile in der Leiste über dem Text
  - `AllDocumentsSearch.swift`: Suche in allen offenen Dokumenten mit der Seitenleiste
  - `TextTransforms.swift`, `TextCommands.swift`: die Umformungen des Menüs Text als reine Funktionen und ihre Anwendung auf die Auswahl
  - `CommandPalette.swift`: die Befehlspalette
  - `EditorTextView.swift`: Textansicht mit Einrückung, hervorgehobener Zeile, Kommentaren und Klammern
  - `Languages.swift`, `YAML.swift`: Sprachdefinitionen aus YAML-Dateien, mitgeliefert und eigene
  - `SyntaxHighlighter.swift`: Färben Zeile für Zeile, mit dem Zustand am Zeilenanfang
  - `Indentation.swift`: Einrückung eines Dokuments und ihr Erkennen
  - `LineNumberRuler.swift`, `InvisiblesLayoutFragment.swift`, `StatusBar.swift`: Zeilennummern, unsichtbare Zeichen, Statusleiste
  - `Preferences.swift`, `Settings.swift`: Einstellungen und ihr Fenster
- `Resources/`: Asset-Katalog mit App-Icon und Akzentfarbe, Dokumentsymbol, Lokalisierung, `PrivacyInfo.xcprivacy`, die mitgelieferten Sprachen in `Languages/`
- `Config/`: `Info.plist`, Entitlements, Build-Einstellungen
- `docs/`: Konzept, Format der Sprachdefinitionen (`sprachen.md`), App-Store-Unterlagen
