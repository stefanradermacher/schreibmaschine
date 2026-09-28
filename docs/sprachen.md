# Sprachdefinitionen

Schreibmaschine färbt Text nach Sprachdefinitionen: kleinen YAML-Dateien mit regulären Ausdrücken. Die mitgelieferten liegen im Quellcode unter `Resources/Languages/`, eigene in einem Ordner im Container der App:

```
~/Library/Containers/com.stefanradermacher.schreibmaschine/Data/Library/Application Support/Schreibmaschine/Sprachen/
```

Format → Sprache → „Ordner mit eigenen Sprachen zeigen“ öffnet ihn im Finder.

## Eigene Sprachen anlegen und ändern

- **Eine mitgelieferte Sprache anpassen:** Datei in dieser Sprache öffnen, dann Format → Sprache → „Definition dieser Sprache bearbeiten“. Die App kopiert die Definition in den eigenen Ordner und öffnet die Kopie. Sie hat denselben Dateinamen und ersetzt damit die mitgelieferte. Wer die Kopie löscht und neu lädt, hat wieder das Original.
- **Eine neue Sprache:** eine `.yaml`- oder `.yml`-Datei in den Ordner legen. Der Dateiname ohne Endung ist die Kennung der Sprache (`lua.yaml` → `lua`); unter dieser Kennung merkt sich die App, welche Sprache man für eine Datei gewählt hat.
- **Wirksam werden Änderungen** beim Sichern einer Definition in diesem Ordner oder mit Format → Sprache → „Sprachdefinitionen neu laden“. Enthält eine Datei einen Fehler, nennt die App Datei, Zeile oder Regel und was fehlt. Die fehlerhafte Definition bleibt dann unwirksam, die übrigen gelten weiter.

## Aufbau

```yaml
# Kommentare beginnen mit #.
name: Lua                          # Name in Menü und Statusleiste; sonst die Kennung
extensions: [lua]                  # Dateiendungen, ohne Punkt, Groß-/Kleinschreibung egal
filenames: [.luacheckrc]           # ganze Dateinamen, genau so geschrieben
interpreters: [lua, luajit]        # Programme hinter #! in der ersten Zeile
comment:
  line: '--'                       # für ⌘/ (Kommentar umschalten)
  block: ['--[[', ']]']            # Anfang und Ende, wenn es keinen Zeilenkommentar gibt
indent:
  width: 2                         # Breite eines Einzugs
  tabs: false                      # true: mit Tabs einrücken
brackets: '()[]{}'                 # Klammerpaare, je zwei Zeichen; Voreinstellung wie hier
ignoreCase: false                  # true: alle Regeln ohne Groß-/Kleinschreibung
rules:
  - scope: comment
    begin: '--\[\['
    end: '\]\]'
  - scope: comment
    match: '--.*$'
  - scope: keyword
    words: [and, break, do, else, elseif, end, for, function, if, in, local, not, or, repeat, return, then, until, while]
```

Alle Angaben außer `rules` sind freiwillig. Ohne `indent` gilt die Einrückung aus den Einstellungen; die Einrückung einer vorhandenen Datei erkennt die App ohnehin aus dem Text.

### Erkennen der Sprache

Beim Öffnen, in dieser Reihenfolge:

1. ein Eintrag in `filenames` passt genau zum Dateinamen,
2. ein Eintrag in `extensions` passt zur Endung,
3. die erste Zeile beginnt mit `#!` und nennt ein Programm aus `interpreters`, direkt (`#!/bin/zsh`) oder über `env` (`#!/usr/bin/env python3`); Versionsnummern am Ende zählen nicht, `python3` findet also `python`,
4. die erste Zeile beginnt mit `<?xml` (XML) oder `<?php` (PHP).

Passt nichts, ist die Datei reiner Text. Wählt man die Sprache selbst (Format → Sprache oder die Statusleiste), merkt sich die App die Wahl für diese Datei.

## Regeln

Jede Regel hat einen `scope`, der die Farbe bestimmt, und eine von drei Formen.

**Wörter** – eine Liste ganzer Wörter:

```yaml
- scope: constant
  words: [true, false, nil]
```

**Muster** – ein regulärer Ausdruck innerhalb einer Zeile. Mit `group` wird nur diese Gruppe des Treffers gefärbt, der Rest gilt trotzdem als verbraucht:

```yaml
- scope: function
  match: '\b([a-z_][A-Za-z0-9_]*)(?=\()'
  group: 1
```

**Bereich** – von `begin` bis `end`, auch über mehrere Zeilen. `escape` nennt ein Zeichen, das ein folgendes Ende aufhebt (`\"` beendet keine Zeichenkette). `multiline: false` beendet den Bereich spätestens am Zeilenende:

```yaml
- scope: string
  begin: '"'
  end: '"'
  escape: '\'
  multiline: false
```

Jede Regel kann außerdem `ignoreCase: true` haben.

### Wie die Regeln angewandt werden

- Die App geht jede Zeile von links nach rechts durch. An jeder Stelle gewinnt die Regel, die am **frühesten** in der Zeile trifft; treffen mehrere an derselben Stelle, die **zuerst aufgeführte**. Der Treffer wird gefärbt, dahinter geht es weiter. Was in einem Kommentar oder einer Zeichenkette steht, wird also nicht noch einmal als Schlüsselwort gefärbt.
- Deshalb gehören Kommentare und Zeichenketten nach oben, allgemeine Muster wie Namen mit großem Anfangsbuchstaben nach unten.
- Reguläre Ausdrücke folgen `NSRegularExpression` (ICU). `^` und `$` stehen für Anfang und Ende der Zeile. Ein Muster trifft nie über ein Zeilenende hinweg; mehrzeilig sind nur Bereiche.
- Ob eine Zeile in einem Kommentar oder einer Zeichenkette beginnt, ergibt sich aus den Zeilen davor. Dafür schaut die App nur auf Bereiche und auf Muster mit `scope: comment` oder `scope: string`. Ein Muster, das den Anfang eines Bereichs verdecken soll (etwa `'//.*$'` vor einem `/*` im Zeilenkommentar), muss deshalb einen dieser beiden Scopes haben.
- Treffer der Länge null zählen nicht.

### Scopes

| Scope | Gedacht für |
|---|---|
| `keyword` | Schlüsselwörter |
| `type` | Typen, Klassen |
| `function` | Funktions- und Methodennamen |
| `string` | Zeichenketten |
| `number` | Zahlen |
| `constant` | `true`, `false`, `nil` und Ähnliches |
| `comment` | Kommentare |
| `attribute` | Attribute, Annotationen, Präprozessor |
| `variable` | Variablen, `self` |
| `tag` | Tags in HTML und XML |
| `property` | Schlüssel, Eigenschaften, Attribute in Tags |
| `heading` | Überschriften, Abschnitte |
| `emphasis` | Hervorhebungen in Markdown |
| `link` | Links (werden zusätzlich unterstrichen) |
| `code` | Code in Markdown |
| `quote` | Zitate in Markdown |

Die Farben folgen dem Standardthema von Xcode, je eine für helle und dunkle Darstellung.

## YAML

Die App liest den Teil von YAML, den Sprachdefinitionen brauchen:

- Zuordnungen (`schlüssel: wert`) und Listen (`- eintrag`), gegliedert durch Einrückung mit **Leerzeichen** (Tabs sind nicht erlaubt),
- Listen in eckigen Klammern, auch über mehrere Zeilen,
- Text ohne Anführungszeichen, in `'einfachen'` oder `"doppelten"`,
- Blocktext mit `|` und `>`,
- Kommentare mit `#` (am Zeilenanfang oder nach einem Leerzeichen).

**Reguläre Ausdrücke am besten in einfache Anführungszeichen setzen:** Darin gilt der Backslash als gewöhnliches Zeichen, `'\d+'` bleibt also `\d+`. Ein einfaches Anführungszeichen selbst wird verdoppelt (`'it''s'`) – oder man nimmt doppelte Anführungszeichen und schreibt jeden Backslash doppelt (`"\\d+"`). Ohne Anführungszeichen geht es nur, solange der Ausdruck nicht mit `[`, `{`, `'`, `"`, `|`, `>` oder `- ` beginnt und kein ` #` oder `: ` enthält.

Zuordnungen in geschweiften Klammern, Anker und Verweise (`&`, `*`) und mehrere Dokumente in einer Datei kennt der Leser nicht.
