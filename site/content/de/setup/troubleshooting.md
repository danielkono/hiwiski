---
title: Fehlerbehebung
url: /de/einrichtung/fehlerbehebung/
weight: 80
---

| Meldung | Ursache und Lösung |
| --- | --- |
| `invalid reference format` | In `HIWISKI_VERSION` steht mehr als die Version, zum Beispiel der ganze Name des Images. |
| `manifest unknown` | Ein Image dieser Version gibt es nicht. Die Versionen stehen im [GitHub-Release]({{< param "github" >}}/releases). |
| `HIWISKI_… is missing` | Die Variable fehlt in der `.env`, oder die `.env` liegt nicht neben der `docker-compose.yml`. |
| `bind: address already in use` | Der Port ist von einem anderen Dienst belegt. Wähle in der `.env` einen anderen. |
| `app` bleibt bei `starting`, im Protokoll `password authentication failed` | `HIWISKI_DB_PASSWORD` wurde nach dem ersten Start geändert (siehe [Installation]({{< relref "setup/installation" >}})). |
| Wiederherstellung abgelehnt: Schema passt nicht | Das Archiv stammt von einer anderen Version. Starte die Version, mit der es gemacht wurde, stelle wieder her und aktualisiere dann. |
| Im Browser geht es, die App verbindet sich nicht (iOS) | Der Zugriff auf das lokale Netzwerk wurde abgelehnt – *Einstellungen → Hiwiski → Lokales Netzwerk*. |
| Im Browser geht es, die App verbindet sich nicht (Android) | Ein Name auf `.local`; verwende die IP-Adresse. |

Wenn nichts davon hilft: [Hilfe]({{< relref "support" >}}).
