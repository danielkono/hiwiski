---
title: Warum Hiwiski
url: /de/warum/
lead: Wofür Hiwiski gebaut ist – und wofür bewusst nicht.
---

## Wie es dazu kam

Mit der Geburt meines Sohnes wurde es nötig, unseren Alltag besser zu organisieren. Inspiriert von Immich wollte ich etwas Ähnliches selbst bauen. Da ich nicht viel freie Zeit habe, wollte ich herausfinden, wie weit ich mit KI komme, und das Projekt nutzen, um alle Bereiche einer solchen Software kennenzulernen: vom Hosting einer Website über einen VPS bis zur Veröffentlichung in den App Stores. Als Nebenprodukt haben wir jetzt zu Hause eine App, mit der wir im chaotischen Alltag weniger vergessen, den Einkauf vorausplanen und wichtige Informationen lokal statt in irgendeiner Cloud haben. Mein NAS ist nicht öffentlich erreichbar, deshalb konzentriere ich mich auf die Offline-Funktionalität.

— Daniel

## Grundsätze

**Offline nutzbar.** Die Apps sollen auch ohne den Server funktionieren. Abends sind alle zu Hause, dann synchronisieren sich alle Geräte.

**Plattformunabhängig.** Jede Plattform soll abgedeckt sein, damit alle Hiwiski nutzen können. Web-Version und App sind nahezu identisch. Auch unterschiedliche Versionen sollen weiterhin zusammen funktionieren.

**Einfachheit.** Ein einfaches Docker-Setup, alles andere wird in der App eingerichtet. Wenn du möchtest, kannst du die App auch ohne Server nutzen.

## Deine Daten bleiben bei dir

Keine Cloud, kein Konto bei einem Anbieter, keine Telemetrie. Die Protokolle bleiben auf deinem Server und verlassen ihn nur, wenn du sie selbst verschickst. Wie Backups und ein Umzug auf einen anderen Rechner funktionieren, steht unter [Einrichtung]({{< relref "setup" >}}).

## Was Hiwiski nicht ist

- **Keine Dateiablage.** Bilder an Rezepten und Seiten ja, ein Ordnerbaum für beliebige Dateien nein. Dafür gibt es bessere Projekte.
- **Keine Push-Nachrichten.** Keine zusätzlichen Dienste: Benachrichtigungen erzeugt die App selbst.
- **Eine Instanz pro Familie.** Der Server ist nicht mandantenfähig. Es ist ein Hobbyprojekt für Familien.
- **Keine Werbung und keine Pro-Version.**

## Lizenz und Projekt

Hiwiski steht unter der [PolyForm Noncommercial License]({{< relref "license" >}}): frei für die private und nicht kommerzielle Nutzung. Pull Requests nehme ich derzeit nicht an. Alles zur Entwicklung – Fehler, Wünsche, Fragen – läuft über [GitHub]({{< param "github" >}}).
