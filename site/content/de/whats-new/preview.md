---
title: Vorschau
url: /de/neuigkeiten/vorschau/
weight: 10
layout: preview
description: 'Die nächste Version von Hiwiski, bevor sie erscheint: was sie bringt und wie du sie vorab ausprobierst – im Browser, als App oder auf deinem Server.'
lead: Die nächste Version, bevor sie erscheint – was sie bringt und wie du sie vorab ausprobierst.
try:
  - icon: language
    name: Im Browser
    text: Die Demo der Vorschau, mit den Beispieldaten einer erfundenen Familie. Sie läuft komplett in deinem Browser; nichts wird gesendet oder gespeichert.
    buttons:
      - link: preview.demo
        text: Demo der Vorschau öffnen
  - icon: phone_iphone
    name: iPhone und iPad
    text: Über die Gruppe der Vorschau in TestFlight. Öffne ihren Testlink auf dem iPhone oder iPad und tippe auf **Annehmen** – auch wenn du die Testversion schon hast. TestFlight installiert dann die jeweils neueste Version.
    buttons:
      - link: preview.ios
        text: Testlink der Vorschau öffnen
  - icon: android
    name: Android
    text: Tritt mit dem Google-Konto deines Handys der Testergruppe der Vorschau bei und tippe dann auf der Testseite auf **Tester werden**. Google Play bietet dir danach die Vorschau an, sobald es sie gibt.
    buttons:
      - link: preview.android
        text: Gruppe der Vorschau öffnen
      - link: apps.android.test
        text: Testseite öffnen
  - icon: dns
    name: Server
    text: Das Image der Vorschau, eingetragen in der `.env` deines Servers. Der Rest ist ein Update wie jedes andere; die Dateien dazu hat die Vorabversion auf GitHub.
    version: true
    buttons:
      - link: release
        text: Vorabversion auf GitHub
soonText: Noch nicht eingerichtet.
---

## Zurück zur veröffentlichten Version

**Die Apps lassen sich nicht auf eine ältere Version zurückstellen.** Wer von der Vorschau zurück will, löscht die App und installiert die veröffentlichte Version neu:

1. Warte, bis alles synchronisiert ist – was nur auf dem Gerät liegt, geht mit der App verloren. Nutzt du die App ohne Server, ist das alles.
2. Verlass die Gruppe der Vorschau in TestFlight oder bei Google Play, sonst kommt die Vorschau gleich wieder.
3. Lösch die App und installiere sie neu, wie unter [Apps]({{< relref "/apps" >}}). Nach der Anmeldung kommt alles vom Server wieder.

**Der Server geht zurück wie nach jedem Update:** die ältere Version in der `.env` eintragen und neu starten ([Updates]({{< relref "/setup/updates" >}})). Er startet auch auf der Datenbank der Vorschau; was erst die Vorschau kann, zeigt er nicht.

## Gut zu wissen

- **Neue Funktionen brauchen oft beides,** die App und den Server der Vorschau. Mit einem älteren Server zeigt die App sie nicht oder nur eingeschränkt.
- **Die Vorschau kann Fehler haben,** die die veröffentlichte Version nicht hat – dafür ist sie da. Vor dem Update sichert der Server von selbst.
- **Bist du in beiden Tests,** dem der veröffentlichten Version und dem der Vorschau, bekommst du jeweils den neuesten Build. Erscheint während der Vorschau ein Update der veröffentlichten Version, kann es die Vorschau ersetzen – die App ist dann wieder auf einer älteren Version. Lösch sie und installiere sie neu, wie oben unter „Zurück zur veröffentlichten Version“.
- **Feedback** wie bei der Testversion: per E-Mail an [{{< param "feedback" >}}](mailto:{{< param "feedback" >}}) oder als Issue auf GitHub – was dabei hilft, steht unter [Hilfe]({{< relref "/support" >}}).
