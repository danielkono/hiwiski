---
title: Apps
description: 'Hiwiski für Android, iPhone und iPad und im Browser. Bis die Apps in den Stores sind, kann sie jede und jeder über den öffentlichen Test bei Google Play und in TestFlight installieren.'
lead: Für Android, iPhone und iPad – und in jedem Browser. Bis die Apps im App Store und bei Google Play sind, kannst du sie als Testversion installieren.
layout: apps
platforms:
  - id: android
    icon: android
    name: Android
    requires: ab Android 8.0
    storeButton: Bei Google Play laden
    steps:
      - link: group
        text: Tritt mit dem Google-Konto deines Handys der Testergruppe bei (**Gruppe beitreten**). Google Play lässt nur ihre Mitglieder zum Test zu.
        button: Gruppe öffnen
      - link: test
        text: Öffne die Testseite und tippe auf **Tester werden**.
        button: Testseite öffnen
      - text: Installiere Hiwiski aus Google Play – die Testseite verlinkt dorthin. Bis Google Play die App anbietet, kann es ein paar Minuten dauern. Updates kommen wie bei jeder anderen App.
  - id: ios
    icon: phone_iphone
    name: iPhone und iPad
    requires: ab iOS 15
    storeButton: Im App Store laden
    steps:
      - url: https://apps.apple.com/app/testflight/id899247664
        text: Installiere Apples App **TestFlight** – über sie kommen die Testversionen.
        button: TestFlight laden
      - link: test
        text: Öffne den Testlink auf dem iPhone oder iPad und tippe auf **Annehmen**.
        button: Testlink öffnen
      - text: Tippe auf **Installieren**. Jede neue Version kommt über TestFlight.
web:
  name: Im Browser
  requires: Jeder aktuelle Browser
soonText: Noch nicht verfügbar.
qr:
  title: Auf dem Handy weiter
  text: Richte die Kamera deines Handys auf den Code, um diese Seite dort zu öffnen.
---

## Erst einmal ohne Server

Die App kann auch ohne Server genutzt werden: Alles bleibt auf dem Gerät, nichts wird irgendwohin gesendet. Das reicht, um Kalender, Listen und Wiki auszuprobieren. Um mit der Familie zu teilen, verbindest du die App später unter **Konto → Mit einem Server verbinden** mit eurem Server – was auf dem Gerät ist, wird übernommen. Wie ein Server eingerichtet wird, steht unter [Einrichtung]({{< relref "/setup" >}}), wie die Apps ihn finden, unter [Apps verbinden]({{< relref "/setup/apps" >}}).

## Testversionen

Bis die Apps im App Store und bei Google Play sind, gibt es sie als Testversionen – über Apples TestFlight und einen Test bei Google Play. Neue Versionen kommen von selbst; was sich geändert hat, steht unter [Neuigkeiten]({{< relref "/whats-new" >}}). Sobald die Apps in den Stores sind, verlinkt diese Seite dorthin. Die nächste Version schon vor ihrem Erscheinen gibt es in der [Vorschau]({{< relref "/whats-new/preview" >}}).

Die Testergruppe bei Google Play sagt Google Play nur, wer den Test installieren darf. In ihr wird nichts gepostet.

## Feedback

- **In TestFlight:** In der App einen Screenshot machen – TestFlight bietet an, ihn als Feedback zu senden.
- **Per E-Mail:** [{{< param "feedback" >}}](mailto:{{< param "feedback" >}})
- **Fehler und Wünsche** auch als Issue auf GitHub – was dabei hilft, steht unter [Hilfe]({{< relref "/support" >}}).
