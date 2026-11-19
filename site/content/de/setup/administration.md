---
title: Verwaltung
url: /de/einrichtung/verwaltung/
weight: 70
---

| Aufgabe | Wie |
| --- | --- |
| Das Passwort des Admins zurücksetzen | `docker compose exec app hiwiski reset-admin-password` |
| Das Protokoll des Servers | `docker compose logs -f app` |
| Eine Shell in der Datenbank | `docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'` |
| Anhalten / starten | `docker compose stop` / `docker compose up -d` |

Passwörter der anderen Mitglieder setzt der Admin in der App zurück, unter *Konto → Familie*.
