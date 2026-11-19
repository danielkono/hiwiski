---
title: Administration
description: 'Administering a Hiwiski server: resetting passwords, reading the log, a database shell, stopping and starting.'
weight: 70
---

| Task | How |
| --- | --- |
| Reset the administrator's password | `docker compose exec app hiwiski reset-admin-password` |
| The server's log | `docker compose logs -f app` |
| A database shell | `docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'` |
| Stop / start | `docker compose stop` / `docker compose up -d` |

The other members' passwords are reset by the administrator in the app, under *Account → Family*.
