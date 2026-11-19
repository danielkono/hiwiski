---
title: Updates
description: Updating a self-hosted Hiwiski server with Docker Compose — with a backup first.
weight: 40
---

## Updating

1. Put the new version into `.env`: `HIWISKI_VERSION=<new version>`.
2. Pull the image and start:

```sh
docker compose pull app
docker compose up -d
```

**The server backs up by itself** when it starts with another version than it last ran — before it touches the database. Until that backup is written the app is not reachable yet; the log says *"Backing up before the update to …"*. If the backup fails (a full disk, mostly), the server migrates nothing and does not start; the old version still starts as it was.

What a version brings and whether there is anything to watch when updating is under [What's new]({{< relref "whats-new" >}}), in the *Upgrade notes*.

## Back to the old version

The same, with the old version in `.env`. Schema changes are made so that the old server still starts on the new schema. The backup made before the update — *"Before the update to …"* in the list — restores on the old version and on every newer one.

## The database's own role (optional)

A server set up with the current files signs in to Postgres with a role of its own that is no superuser: if a flaw ever let SQL through, it could not reach further than the database. One set up before keeps its single role and keeps working unchanged. To move it over:

1. Back up first (*Back up now*). Download the current `docker-compose.yml` from the release, then `docker compose up -d postgres` and `docker compose stop app`. If you already copied `HIWISKI_DB_ADMIN_USER` and `HIWISKI_DB_ADMIN_PASSWORD` from the new `.env.example` into your `.env` without moving, remove those two lines first.
2. Open a database shell: `docker compose exec postgres sh -c 'psql -U "$HIWISKI_DB_USER" -d "$POSTGRES_DB"'` (until step 3 that is your old role, the superuser), and paste this, with a new long password (`openssl rand -hex 24`) and, if yours is another, your `HIWISKI_DB_NAME` in place of `hiwiski` in the last line:

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

3. In `.env`: rename `HIWISKI_DB_USER` and `HIWISKI_DB_PASSWORD` to `HIWISKI_DB_ADMIN_USER` and `HIWISKI_DB_ADMIN_PASSWORD`, keeping their values, and add `HIWISKI_DB_USER=hiwiski_app` and `HIWISKI_DB_PASSWORD=` with the new password.
4. `docker compose up -d`.

## The apps

Apps and server may be of different versions. Not every device has to update at once.
