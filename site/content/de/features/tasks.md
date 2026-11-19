---
title: Aufgaben & Einkauf
url: /de/funktionen/aufgaben/
weight: 10
scene: tasks-overview
lead: Aufgabenlisten, Einkaufslisten und Kanban-Boards.
---

## Aufgabenlisten

Aufgabenlisten mit Fälligkeit, Wiederholung („jeden Montag“), Zuständigen und Tags. Die Übersicht zeigt jede Liste als Karte mit Fortschritt; die Reihenfolge legt jedes Familienmitglied für sich fest.

{{< scene name="tasks-overview" height=480 >}}Die Übersicht: Einkaufslisten, Aufgabenlisten und Boards.{{< /scene >}}

## Die Einkaufsliste

Nach Kategorien gruppiert, in einer Reihenfolge, die für die ganze Familie gilt. Ziehst du ein Produkt in eine andere Kategorie, landet es ab jetzt in jeder Liste dort. Innerhalb einer Kategorie sortierst du die Zeilen in der Reihenfolge, in der du durch den Laden gehst. Die Schnelleingabe versteht „2l Milch“: Menge, Einheit, Produkt.

{{< scene name="shopping-list" live=true height=560 >}}Die Wocheneinkaufsliste.{{< /scene >}}

## Kanban-Boards {#kanban}

Karten in Spalten, von „Zu tun“ bis „Erledigt“, die per Ziehen verschoben werden. Auf dem Handy siehst du eine Spalte nach der anderen und wischst seitwärts. Eine normale Aufgabenliste lässt sich in ein Board umwandeln.

{{< scene name="kanban-board" live=true height=520 >}}Die Badrenovierung als Board.{{< /scene >}}

## Beschreibung und Kommentare

Eine Aufgabe hat eine Beschreibung mit Checkboxen, Bildern und Links, darunter stehen Kommentare. Versehentliches Abhaken oder Löschen lässt sich mit „Rückgängig“ zurücknehmen.

{{< scene name="task-detail" height=520 >}}Eine Aufgabe mit Beschreibung und Kommentaren.{{< /scene >}}

## So geht's

{{< steps id="einkaufsliste-sortieren" title="Die Einkaufsliste nach dem eigenen Laden sortieren" >}}
Die Einkaufsliste wird in der Reihenfolge sortiert, in der du durch den Laden gehst. Die Sortierung gilt danach für jede Einkaufsliste.

*Du brauchst:* einen Server (Kategorien werden für die ganze Familie gespeichert) und das Recht, die Liste zu bearbeiten.

1. Öffne die Einkaufsliste.
2. Halte ein Produkt gedrückt, bis es sich anhebt, und ziehe es in die richtige Kategorie. Fehlt die Kategorie in der Liste, ziehe es auf „Andere Kategorie“ – dann klappen alle übrigen auf.
3. Lass ein Produkt auf der oberen oder unteren Hälfte einer anderen Zeile los, um es davor oder dahinter einzusortieren.
4. Die Reihenfolge der Kategorien selbst legst du unter **Konto → Kategorien** fest.

{{< scene name="shopping-list" live=true height=520 >}}Probier es aus: Zieh die Bananen zu den Backwaren.{{< /scene >}}

*Am Desktop* ziehst du sofort mit der Maus, ohne gedrückt zu halten.
{{< /steps >}}

{{< steps id="wiederkehrende-aufgaben" title="Wiederkehrende Aufgaben, zum Beispiel Ämtchen der Kinder" >}}
Eine wiederkehrende Aufgabe erscheint nach dem Abhaken neu, mit derselben Zuweisung.

1. Lege eine Aufgabenliste an, zum Beispiel „Ämtchen“.
2. Tippe unten in die Schnelleingabe, dann auf **Mehr Felder**.
3. Wähle unter **Wiederholung** etwa „Jede Woche, Samstag“ und unter **Zugewiesen** das Kind.
4. Ist die Aufgabe erledigt, hakt das Kind sie ab – die nächste erscheint von selbst. Unter der Aufgabe steht, wer wann erledigt hat.

{{< scene name="task-list" live=true height=520 >}}Die Ämtchen-Liste der Beispielfamilie.{{< /scene >}}
{{< /steps >}}

{{< steps id="projekt-als-board" title="Ein Projekt als Kanban-Board" >}}
Ein Board zeigt für jede Karte, in welchem Stand sie ist.

1. Tippe in der Aufgabenübersicht auf **Neue Liste** und wähle **Kanban**.
2. Die Spalten sind mit „Zu tun / In Arbeit / Erledigt“ vorbelegt. Benenne sie um, gib ihnen Farben oder füge welche hinzu (bis zu acht).
3. Unter jeder Spalte legt „+ Karte hinzufügen“ eine Karte an.
4. Halte eine Karte gedrückt und zieh sie in eine andere Spalte. Auf dem Handy wechselt die Spalte, wenn du die Karte an den Rand hältst.
{{< /steps >}}

## Gut zu wissen

- Die Kategorie eines Produkts zu ändern braucht eine Verbindung zum Server. Alles andere funktioniert auch offline.
- Fügen zwei Geräte offline beide „Milch“ hinzu, stehen danach zwei Zeilen da. Sie werden beim Abgleich nicht zusammengeführt, weil sich sonst Mengen verfälschen könnten.
- Eine Einkaufsliste bleibt eine Einkaufsliste. Nur eine Aufgabenliste kann zum Board werden; Wiederholungen fallen dabei weg.
