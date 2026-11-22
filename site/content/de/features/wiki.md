---
title: Wiki & Rezepte
url: /de/funktionen/wiki/
weight: 30
scene: wiki-page
lead: Verschachtelte Seiten in Markdown, Rezepte und Verlinkungen.
---

## Seiten in einem Baum

Beliebig tief verschachtelt, per Ziehen umsortiert. Du schreibst eine Seite so, wie sie danach aussieht – Überschriften, Listen, Checkboxen und Bilder erscheinen schon beim Schreiben wie auf der Seite – oder als Markdown, einen Tipp in der Werkzeugleiste entfernt. Mehrere Bilder hintereinander werden als Stapel angezeigt, durch den du wischen kannst.

{{< scene name="wiki-page" live=true height=560 >}}Papas Anleitung, wie man den Router neu startet.{{< /scene >}}

## Verlinkungen

Tippe `#` und eine Nummer oder einen Titel, um auf eine andere Seite, eine Aufgabe, eine Liste oder einen Termin zu verlinken. Der Link erscheint als Chip mit Vorschau.

## Rezepte

Die Portionen werden mit −/+ eingestellt, die Mengen der Zutaten passen sich an. Die Zubereitung steht darunter, mit Bildern.

{{< scene name="recipe" live=true height=600 >}}Käsespätzle aus Omas Klassikern.{{< /scene >}}

## Auf die Einkaufsliste

„Auf die Einkaufsliste“ übernimmt die Zutaten mit den umgerechneten Mengen. Vorratszutaten wie Salz oder Öl sind bereits abgewählt.

## Rezept aus einer Webseite

Der Server holt ein Rezept von einer Adresse. Vor dem Speichern markiert ein Prüfbildschirm, was er nicht sicher erkannt hat.

{{< scene name="recipe-import" height=760 >}}Der Prüfbildschirm beim Import.{{< /scene >}}

## Mindmaps

Eine Seite der Art *Mindmap* hat unter ihrem Text eine Leinwand. Im Vollbild bewegst du dich mit den Fingern, dem Trackpad oder dem Mausrad darauf und zoomst hinein und heraus. **Bearbeiten** bringt drei Knöpfe in die untere rechte Ecke — Hinzufügen, Zeichnen, Werkzeuge —, deren Auswahl auf einen Ring herauskommt, den du für mehr weiterdrehst; auf dem Handy nimmt sie den Platz der Knöpfe ein, und der Knopf in der Mitte führt zurück. Text, Notiz, Bild, Link oder Familienmitglied tippst du an, dann liegen sie in der Mitte, oder du hältst sie und ziehst sie auf die Leinwand; Text tippst du direkt an Ort und Stelle. **Verbindung** bietet Linie, Pfeil, Doppelpfeil, gestrichelte und gepunktete Linie, in Farbe und Stärke, die du vorher wählst: Du ziehst von einem Element zum anderen oder tippst sie nacheinander an und machst von dort aus weiter; eine Verbindung kann eine Beschriftung tragen. Elemente bekommen eine Farbe — eine der acht oder eine eigene, auf Wunsch durchscheinend —, eine Textfarbe, eine Form und eine Textgröße — oder eine eigene — und lassen sich dort, wo sie sich überlagern, nach vorne oder nach hinten legen; eine Verbindung ist so dick, wie du willst. Mit Lasso oder Rechteck wählst du mehrere Elemente aus und verschiebst, färbst oder löschst sie gemeinsam — oder richtest sie aus, verteilst sie gleichmäßig und gibst ihnen eine Breite, Höhe oder Größe. Was du verschiebst oder in der Größe änderst, rastet an Kanten, Mitten, Abständen und Größen der Elemente ringsum ein, eine dünne Hilfslinie zeigt es; ein neues Bild, eine Notiz, ein Link oder ein Mitglied ist so groß wie das letzte seiner Art. Unter Werkzeuge schaltest du das Einrasten ab oder ein Raster ein, an dem alles einrastet; am Computer setzt ⌘ oder Strg beim Ziehen das Einrasten aus. Ein Text ist genau so groß wie seine Worte, ein Bild behält seine Form, und ein Link zeigt den Titel seines Ziels oder dessen Inhalt. Mit dem **Stift** zeichnest du in Farbe und Strichstärke deiner Wahl auf die Karte, frei oder als Rechteck, Ellipse, Dreieck, Raute, Linie oder Pfeil — eine Form lässt sich danach in der Größe ändern; der **Radierer** nimmt jeden Strich weg, über den du wischst, und ein Tipp blendet die Zeichnungen aus. **Rückgängig** nimmt eine Änderung zurück. Der Knauf über einem ausgewählten Element dreht es. Zweimal tippen und nach oben oder unten ziehen zoomt mit einem Finger. Eine Suche auf der Leinwand hebt hervor, was sie findet, und listet es auf — wie auf der Karte, alphabetisch oder nach Datum. **Als Bild sichern** speichert die ganze Karte als PNG, und der Export einer Seite nimmt ihre Mindmaps auf Wunsch als Bilder mit.

Mehrere können gleichzeitig an derselben Mindmap arbeiten, auch offline. Jedes Element wird für sich synchronisiert: Haben zwei dasselbe Element zur selben Zeit geändert, zeigt die Mindmap deine Version neben der, die alle sehen, und du entscheidest nur für dieses Element.

## Verlauf

Jedes Speichern erzeugt eine Version. Jede Version lässt sich ansehen und wiederherstellen.

## So geht's

{{< steps id="seiten-verlinken" title="Seiten anlegen und verlinken" >}}
1. Tippe im Seitenbaum beim gewünschten Ort auf **+** und gib einen Titel ein.
2. Tippe auf **Bearbeiten**. Der Text wird bearbeitbar, so wie er aussieht, darüber erscheint die Werkzeugleiste; ihr erster Knopf schaltet zur Markdown-Quelle und zurück.
3. Tippe `#` und den Anfang eines Titels oder eine Nummer wie `WIKI-3`. Wähle einen Vorschlag, um den Link zu setzen.
4. **Speichern**. Gespeichert wird beim Tippen auf Speichern und beim Verlassen, nicht während du schreibst.

{{< scene name="wiki-edit" live=true height=560 >}}Probier es aus: Verlinke die Seite „Heizung“.{{< /scene >}}
{{< /steps >}}

{{< steps id="rezept-einkaufen" title="Ein Rezept einkaufen" >}}
1. Öffne ein Rezept und stelle mit −/+ die Portionen ein.
2. Tippe auf **Auf die Einkaufsliste**.
3. Wähle die Liste und prüfe die Zutaten. Was ihr schon habt, wählst du ab.
4. **Übernehmen** – die Zutaten stehen in ihren Kategorien auf der Liste.

{{< scene name="recipe" live=true height=600 >}}Erst die Portionen …{{< /scene >}}

{{< scene name="shopping-list" live=true height=520 >}}… dann auf die Liste: Hier erscheinen die Zutaten. Beide Ansichten teilen sich die Daten.{{< /scene >}}
{{< /steps >}}

{{< steps id="rezept-importieren" title="Ein Rezept von einer Webseite importieren" >}}
*Du brauchst:* einen Server.

1. Tippe im Seitenbaum bei einer Rezeptsammlung auf **+** und dann auf **Rezept importieren**.
2. Füge die Adresse der Rezeptseite ein und tippe auf **Holen**.
3. Prüfe Titel, Bild, Portionen und Zutaten. Unsicher erkannte Zeilen sind markiert und lassen sich korrigieren.
4. **Prüfen und übernehmen**.
{{< /steps >}}

## Gut zu wissen

- Gespeichert werden Seiten als Markdown, wie auch immer du schreibst. Ob Texte formatiert oder als Markdown öffnen, stellst du unter **Konto → Anpassen** ein.
- Rezept-Import und Verlauf brauchen einen Server; Bilder funktionieren auch ohne.
