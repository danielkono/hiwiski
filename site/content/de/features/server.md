---
title: Server & Verwaltung
url: /de/funktionen/server/
weight: 70
scene: settings-backup
lead: Backups, Updates, Archiv, Papierkorb, Verlauf und Geräte.
---

## Backup

Ein verschlüsseltes Archiv aus Datenbank und Bildern, nach deinem Zeitplan, vor jedem Update und auf Anforderung. Herunterladen, in den Einstellungen wiederherstellen — auf dieser Version oder einer neueren — oder einen neuen Server daraus einrichten.

{{< scene name="settings-backup" height=480 >}}Die Backup-Einstellungen.{{< /scene >}}

## Updates

Version in der `.env` ändern, `docker compose up -d`. Zurück geht es genauso, mit der alten Version. Apps und Server unterschiedlicher Versionen arbeiten zusammen – nicht jedes Gerät muss gleichzeitig aktualisiert werden.

## Archiv

Fertige Seiten und Listen kommen ins Archiv: schreibgeschützt und jederzeit wiederherstellbar. Archiviertes wird nicht automatisch gelöscht.

{{< scene name="archive" height=440 >}}Das Archiv.{{< /scene >}}

## Papierkorb

Gelöschtes aus allen Bereichen, samt Freigabe wiederherstellbar. Standardmäßig 30 Tage lang.

{{< scene name="trash" height=440 >}}Der Papierkorb.{{< /scene >}}

## Verlauf

Wer hat was wann geändert, für jedes Element. Seiten haben dazu Versionen zum Wiederherstellen.

## Geräte

Jedes Mitglied sieht seine Geräte mit ihrem Abgleich-Stand und kann eines aus der Ferne abmelden. Ein abgemeldetes Gerät verliert sofort den Zugriff.

{{< scene name="devices" height=440 >}}Meine Geräte.{{< /scene >}}

## So geht's

{{< steps id="archiv-papierkorb" title="Archivieren und wiederherstellen" >}}
1. Eine fertige Liste oder Seite archivierst du über **Liste archivieren** bzw. **Seite archivieren** unten in der Infoleiste. Sie bleibt lesbar, wird aber aus den normalen Ansichten ausgeblendet.
2. Unter **Konto → Archiv** findest du alles Archivierte und holst es mit **Wiederherstellen** zurück.
3. Gelöschtes liegt unter **Konto → Papierkorb**, bis die Frist abläuft, und kommt mit **Wiederherstellen** samt Freigabe zurück.
{{< /steps >}}

{{< steps id="geraet-verloren" title="Ein Gerät ist verloren: aus der Ferne abmelden" >}}
1. Öffne auf einem anderen Gerät **Konto → Meine Geräte**.
2. Tippe beim verlorenen Gerät auf **Abmelden**.
3. Das Gerät verliert sofort den Zugriff und löscht beim nächsten Kontakt seine Daten. Was dort noch nicht abgeglichen war, ist verloren.
{{< /steps >}}

## Gut zu wissen

- Backups landen in einem Verzeichnis auf dem Rechner des Servers; der Server schickt sie nirgendwohin. Kopiere dieses Verzeichnis regelmäßig an einen anderen Ort (→ [Backups]({{< relref "setup/backups" >}})).
- Eine Wiederherstellung ersetzt alles; danach synchronisieren sich alle Geräte neu.
- Wie weit der Verlauf zurückreicht, ist eine Einstellung.
- Einstellungen, Backups und Mitglieder ändert nur der Admin.
