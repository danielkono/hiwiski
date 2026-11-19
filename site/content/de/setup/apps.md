---
title: Apps verbinden
url: /de/einrichtung/apps/
weight: 20
---

## Die Adresse

Die Serveradresse in der App lautet `http://<Adresse>:<HIWISKI_HTTP_PORT>`. Ist der Port 80, kann er weggelassen werden.

{{< scene name="server-address" height=520 >}}Die erste Frage der App.{{< /scene >}}

- **Verwende die IP-Adresse** oder einen Namen, den der Router auflöst. Android kann Namen auf `.local` oft nicht auflösen.
- **iOS fragt nach dem Zugriff auf das lokale Netzwerk.** Ohne „Erlauben“ erreicht die App den Server nicht. Nachträglich lässt sich der Zugriff unter *Einstellungen → Hiwiski → Lokales Netzwerk* erlauben.
- **Im Heimnetz ist die Verbindung standardmäßig unverschlüsselt.** Die App und die Anmeldung weisen darauf hin. Die Möglichkeiten für TLS stehen unter [Verschlüsselung im Heimnetz]({{< relref "setup/encryption" >}}).

## Anmelden und die Familie einladen

1. Melde dich in der App mit dem Admin-Konto aus dem Assistenten an.
2. Lade die Familie ein: **Konto → Familie → Neues Mitglied** erstellt eine Einladung mit Code und QR-Code. Die einzelnen Schritte stehen unter [Familie & Teilen]({{< relref "features/family#familie-einladen" >}}).
3. Wer die App schon ohne Server genutzt hat, verbindet sie unter **Konto → Mit einem Server verbinden**. Die Daten auf dem Gerät werden übernommen.
