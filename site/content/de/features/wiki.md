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
