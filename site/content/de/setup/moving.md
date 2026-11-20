---
title: Umzug
url: /de/einrichtung/umzug/
weight: 60
---

So ziehst du eine Instanz auf einen anderen Rechner um — oder fängst neu an, nachdem der alte weg ist:

1. **Ein Archiv der alten Instanz.** Läuft sie noch, in der App *Jetzt sichern* und das Archiv herunterladen, oder das neueste aus ihrem `HIWISKI_BACKUP_DIR` nehmen. Sonst die Kopie, die du woanders aufbewahrst.
2. **Die neue Instanz installieren** ([Installation]({{< relref "setup/installation" >}})), mit derselben oder einer neueren Version: Ein Archiv lässt sich auf jeder neueren Version wiederherstellen, nicht auf einer älteren.
3. **Den Einrichtungsassistenten öffnen** – mit dem Einrichtungscode aus ihrem Protokoll, falls du ihn [eingeschaltet hast]({{< relref "setup/installation#setup-code" >}}) – und **Aus einer Sicherung wiederherstellen** wählen. Datei wählen, Sicherungspasswort eingeben, Vorschau prüfen, **Wiederherstellen**.
4. **Anmelden** wie vorher: Mitglieder, Gruppen und Administrator kommen aus dem Archiv, ebenso das Sicherungspasswort.
5. **Geräte:** Sie synchronisieren sich neu. Hat sich die Adresse geändert, trägst du die neue in den Einstellungen der App ein.

Halte die alte Instanz erst an, wenn die Wiederherstellung auf der neuen abgeschlossen ist: `docker compose down` behält die Volumes, `docker compose down -v` löscht sie.
