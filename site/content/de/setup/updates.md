---
title: Updates
url: /de/einrichtung/updates/
weight: 40
---

## Aktualisieren

1. In der `.env` die neue Version eintragen: `HIWISKI_VERSION=<neue Version>`.
2. Das Image holen und starten:

```sh
docker compose pull app
docker compose up -d
```

**Der Server sichert von selbst**, wenn er mit einer anderen Version startet als zuletzt — bevor er die Datenbank anfasst. Bis diese Sicherung geschrieben ist, ist die App noch nicht erreichbar; im Protokoll steht *„Backing up before the update to …“*. Schlägt die Sicherung fehl (meist eine volle Platte), migriert der Server nichts und startet nicht; die alte Version startet weiter wie vorher.

Was eine Version mitbringt und ob beim Update etwas zu beachten ist, steht unter [Neuigkeiten]({{< relref "whats-new" >}}) im Abschnitt *Upgrade notes*.

## Zurück zur alten Version

Genauso, mit der alten Version in der `.env`. Schema-Änderungen sind so umgesetzt, dass der alte Server auch mit dem neuen Schema startet. Die Sicherung vor dem Update — *„Vor dem Update auf …“* in der Liste — lässt sich auf der alten Version wiederherstellen und auf jeder neueren.

## Eine eigene Rolle für den Server (optional)

Ein mit den aktuellen Dateien eingerichteter Server meldet sich mit einer eigenen Rolle bei Postgres an, die kein Superuser ist: Ließe ein Fehler je SQL durch, käme es nicht weiter als bis zur Datenbank. Ein früher eingerichteter Server behält seine eine Rolle und läuft unverändert weiter. Umstellen geht so:

1. Erst sichern (*Jetzt sichern*). Die aktuelle `docker-compose.yml` aus dem Release holen, dann `docker compose up -d postgres` und `docker compose stop app`. Hast du `HIWISKI_DB_ADMIN_USER` und `HIWISKI_DB_ADMIN_PASSWORD` aus der neuen `.env.example` schon ohne Umzug in deine `.env` übernommen, nimm diese beiden Zeilen zuerst wieder heraus.
2. Eine Datenbank-Shell öffnen: `docker compose exec postgres sh -c 'psql -U "$HIWISKI_DB_USER" -d "$POSTGRES_DB"'` (bis Schritt 3 ist das deine alte Rolle, der Superuser), und das hier einfügen, mit einem neuen langen Passwort (`openssl rand -hex 24`) und, falls deiner anders heißt, deinem `HIWISKI_DB_NAME` statt `hiwiski` in der letzten Zeile:

```sql
create role hiwiski_app login password 'NEW-PASSWORD'
  nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I owner to hiwiski_app', t.tablename);
  end loop;
end $$;
alter database hiwiski owner to hiwiski_app;
```

3. In der `.env`: `HIWISKI_DB_USER` und `HIWISKI_DB_PASSWORD` in `HIWISKI_DB_ADMIN_USER` und `HIWISKI_DB_ADMIN_PASSWORD` umbenennen, die Werte bleiben; dazu `HIWISKI_DB_USER=hiwiski_app` und `HIWISKI_DB_PASSWORD=` mit dem neuen Passwort.
4. `docker compose up -d`.

## Die Apps

Apps und Server dürfen unterschiedliche Versionen haben. Nicht jedes Gerät muss gleichzeitig aktualisiert werden.
