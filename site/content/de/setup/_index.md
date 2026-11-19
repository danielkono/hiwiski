---
title: Einrichtung
url: /de/einrichtung/
---

Hiwiski steht unter der [PolyForm Noncommercial License]({{< relref "license" >}}) und ist für die private Nutzung frei.

## Was du brauchst

- Einen Rechner mit **Docker** und **Docker Compose v2** (`docker compose`, nicht `docker-compose`). Das Image gibt es für **amd64** und **arm64** – ein NAS oder ein Mini-PC reicht.
- **Zwei freie Ports**, standardmäßig 80 und 443. Beide lassen sich in der `.env` ändern.
- **Eine Shell** auf dem Rechner, zum Beispiel per SSH.

Hiwiski muss außerhalb deines Heimnetzes nicht erreichbar sein. Die App funktioniert offline und synchronisiert sich mit dem Server, sobald sie ihn wieder erreicht.

## Erst mal ohne Server

Wer erst ausprobieren will: Die App läuft auch ganz allein auf einem Gerät. In der App **Ohne Server nutzen** wählen, einen Namen eingeben, fertig. Später kannst du dich mit einem Server verbinden und alles mitnehmen. Wer nichts installieren will, probiert die [Demo]({{< param "demo" >}}) im Browser.

## Was läuft

| Dienst | Aufgabe |
| --- | --- |
| `postgres` | die Datenbank |
| `app` | der Server, mit der Web-App |
| `caddy` | nimmt die Anfragen im Heimnetz an, auf Wunsch mit TLS |

Dazu kommt `init`, das beim Start einmal die Rechte am Datenverzeichnis setzt und sich dann beendet.

## Die Schritte

1. [Installation]({{< relref "setup/installation" >}}) – Dateien holen, `.env` ausfüllen, starten.
2. [Apps verbinden]({{< relref "setup/apps" >}}) – anmelden und die Familie einladen.
3. Danach: [Backups]({{< relref "setup/backups" >}}) und [Updates]({{< relref "setup/updates" >}}).
