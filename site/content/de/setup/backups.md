---
title: Backups
url: /de/einrichtung/backups/
weight: 50
---

- **Der Server sichert nach Zeitplan** — standardmäßig täglich um 02:00, oder wöchentlich; Uhrzeit und wie viele Archive bleiben (1–30, Standard 7), stellst du in der App unter *Konto → Einstellungen → Sicherung* ein. Eine Nacht, in der der Server geschlafen hat, holt er nach, sobald er wach ist.
- **Vor jedem Update** sichert er von selbst, bevor er die Datenbank anfasst ([Updates]({{< relref "setup/updates" >}})).
- **Auf Anforderung** unter *Jetzt sichern*, und **vor jeder Wiederherstellung**, damit sich eine versehentliche rückgängig machen lässt.
- Ein Archiv enthält den Inhalt der Datenbank und alle Bilder, als eine Datei `<id>.hiwiski`.

## Wohin die Archive gehen

In ein Verzeichnis **auf dem Host**, das `HIWISKI_BACKUP_DIR` in der `.env` nennt (standardmäßig `./backups` neben der Compose-Datei). Das kann ein USB-Laufwerk oder eine auf dem Host eingebundene NAS-Freigabe sein. Der Server prüft beim Start, ob er dorthin schreiben kann, und startet sonst nicht.

**Eine Sicherung auf der Platte, die sie schützen soll, ist keine.** Sie übersteht ein versehentliches Löschen, keine kaputte Platte und kein gestohlenes NAS. Bewahr eine zweite Kopie woanders auf, eine davon außer Haus (3-2-1): Der Server schickt selbst nichts irgendwohin — lass ein Werkzeug, das du schon hast, das Verzeichnis kopieren: Hyper Backup auf einer Synology, rsync, restic, oder ab und zu eine Platte in der Schublade.

In der App lässt sich jedes Archiv auch **herunterladen** — im Browser als gewöhnlicher Download, auf dem Handy über den Speichern-Dialog.

## Verschlüsselung und Sicherungspasswort

**Jedes Archiv ist verschlüsselt** ([age](https://age-encryption.org), X25519). Der Einrichtungsassistent fragt nach einem **Sicherungspasswort**; ohne es lässt sich kein Archiv öffnen — nicht vom Server, nicht von uns. Leg es in deinen Passwortmanager.

Der Server sichert nachts, ohne das Passwort zu kennen: Er hat einen öffentlichen Schlüssel zum Verschlüsseln und den privaten nur mit dem Passwort verschlossen. Jedes Archiv trägt diesen verschlossenen Schlüssel mit, also braucht eine Wiederherstellung nur die Datei und das Passwort — auch auf einem neuen Rechner.

- **Ändern** (*Sicherungspasswort → Ändern*, mit dem bisherigen) verschließt die Archive auf dem Server neu mit dem neuen Passwort. Kopien, die du vorher heruntergeladen hast, behalten das alte.
- **Vergessen?** *Ein neues setzen* erzeugt einen neuen Schlüssel: Sicherungen ab dann nutzen das neue Passwort, die vorherigen öffnen nur mit dem alten. Einen Weg daran vorbei gibt es nicht.

Ein Archiv und sein Passwort zusammen sind die Daten der Familie. Sind beide in falsche Hände geraten: ein neues Sicherungspasswort setzen, neue Adressen für Wandtafeln und Kalender-Feeds erzeugen und alle Mitglieder ihre Passwörter ändern lassen.

## Wiederherstellen

Unter *Konto → Einstellungen → Sicherung* ein Archiv aus der Liste **wiederherstellen** oder **Aus einer Datei wiederherstellen**. Zuerst kommt das Passwort, dann eine Vorschau — wann, welche Version, wie groß, wie viele Mitglieder — und erst dann *Alles ersetzen*. Der jetzige Stand wird vorher gesichert. Danach synchronisieren sich alle Geräte neu.

Hier lassen sich nur Archive **dieser Familie** wiederherstellen; das einer anderen lehnt der Server ab — richte dafür eine neue Instanz ein und spiel es im Einrichtungsassistenten ein. Ein Archiv lässt sich auf der Version wiederherstellen, von der es stammt, und **auf jeder neueren**: Der Server bringt es beim Einspielen auf sein eigenes Schema. Eins von einer neueren Version lehnt er ab und nennt die Version, die du installieren musst.

**Geräte, die offline waren oder mehr gesehen haben als die Sicherung, verlieren nichts.** Was ein Gerät noch nicht geschickt hatte, geht von selbst zum Server. Was es geschickt hatte und der wiederhergestellte Server nicht mehr hat, legt es beiseite und sagt Bescheid — *„Nach einer Wiederherstellung sind 12 Einträge nur noch auf diesem Gerät“* — zum Zurückholen mit einem Tipp. Nach einem verlorenen Server ist das die Woche zwischen Sicherung und Verlust, von den Handys.

Wer sich anmelden darf, kommt nicht aus dem Archiv: Passwörter, gesperrte Mitglieder und abgemeldete Geräte bleiben, wie sie jetzt sind. Ein Handy, das nach der Sicherung abgemeldet wurde, bleibt abgemeldet, und ein seither geändertes Passwort bleibt geändert. Angemeldete Geräte bleiben angemeldet, egal wie alt das Archiv ist. Genauso die Adressen von Wandtafeln und Kalender-Feeds, die es noch gibt, und das Sicherungspasswort: Eine Wiederherstellung behält, was sie jetzt haben.
