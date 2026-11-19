---
title: Installation
url: /de/einrichtung/installation/
weight: 10
---

## 1. Ein Verzeichnis mit drei Dateien

Lege ein Verzeichnis für die Instanz an, zum Beispiel `/volume2/docker/hiwiski`, und lade aus dem [aktuellen GitHub-Release]({{< param "github" >}}/releases/latest) drei Dateien hinein:

| Datei | Wofür |
| --- | --- |
| `docker-compose.yml` | die Dienste |
| `Caddyfile` | wie Anfragen ankommen |
| `env.example` | als `.env` speichern und ausfüllen |

## 2. Die `.env` ausfüllen

| Variable | Was |
| --- | --- |
| `HIWISKI_VERSION` | **Nur die Version**, zum Beispiel `2026.1.0` – der Name des Images steht schon in der Compose-Datei. |
| `HIWISKI_HOSTNAME` | Der Name des Rechners im Heimnetz. |
| `HIWISKI_HTTP_PORT`, `HIWISKI_HTTPS_PORT` | Die Ports auf dem Rechner (siehe [Was du brauchst]({{< relref "setup" >}})). |
| `HIWISKI_DB_PASSWORD`, `HIWISKI_DB_ADMIN_PASSWORD` | Zwei lange Zufallspasswörter: `openssl rand -hex 24`. Das erste ist das des Servers, das zweite das des Postgres-Superusers, der nur die Datenbank anlegt. |
| `HIWISKI_TIMEZONE` | Die Zeitzone der Familie, Standard `Europe/Berlin`. |
| `HIWISKI_BACKUP_DIR` | Wohin die Sicherungen auf dem Rechner gehen, Standard `./backups` neben der Compose-Datei. Besser ein USB-Laufwerk oder eine eingebundene NAS-Freigabe (→ [Backups]({{< relref "setup/backups" >}})). |

**Die Datenbank-Passwörter werden nur einmal gesetzt:** Postgres übernimmt sie, wenn sein Volume angelegt wird. Wird eines danach in der `.env` geändert, kann sich der Server nicht mehr an der Datenbank anmelden.

## 3. Starten

```sh
docker compose up -d
docker compose ps          # app und postgres "healthy", init "exited (0)"
```

Der erste Start dauert etwa eine Minute: Der Server wartet auf Postgres und legt das Datenbankschema an.

## 4. Der Einrichtungsassistent

Bis der Assistent gelaufen ist, schreibt der Server bei jedem Start einen **Einrichtungscode** in sein Protokoll. Der Assistent fragt danach, damit niemand anderes deinen Server vor dir einrichtet:

```sh
docker compose logs app | grep "Setup code"
# ... WARN ... Setup code: K7M4-2QXP -- the setup wizard asks for it. ...
```

Öffne `http://<Adresse>:<HIWISKI_HTTP_PORT>` im Browser. Der Assistent fragt nach dem Einrichtungscode, Familienname und Zeitzone, legt dein Konto als Admin an und erstellt die ersten Gruppen, zum Beispiel „Eltern“. Der Code ändert sich bei jedem Neustart, bis die Einrichtung fertig ist; nimm den vom letzten Start.

{{< scene name="setup-wizard" height=520 >}}Der Einrichtungsassistent.{{< /scene >}}

Weiter geht es mit [Apps verbinden]({{< relref "setup/apps" >}}).
