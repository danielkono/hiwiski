---
title: Installation
description: 'Installing the Hiwiski server with Docker Compose, step by step: the compose file, the first start and the setup wizard.'
weight: 10
---

## 1. A directory with three files

Create a directory for the instance, for example `/volume2/docker/hiwiski`, and download three files from the [latest GitHub release]({{< param "github" >}}/releases/latest) into it:

| File | For |
| --- | --- |
| `docker-compose.yml` | the services |
| `Caddyfile` | how requests come in |
| `env.example` | save as `.env` and fill in |

## 2. Fill in `.env`

| Variable | What |
| --- | --- |
| `HIWISKI_VERSION` | **Only the version**, for example `2026.1.0` — the image name is already in the compose file. |
| `HIWISKI_HOSTNAME` | The machine's name on the home network. |
| `HIWISKI_HTTP_PORT`, `HIWISKI_HTTPS_PORT` | The ports on the machine (see [What you need]({{< relref "setup" >}})). |
| `HIWISKI_DB_PASSWORD`, `HIWISKI_DB_ADMIN_PASSWORD` | Two long random passwords: `openssl rand -hex 24`. The first is the server's, the second that of Postgres's superuser, which only creates the database. |
| `HIWISKI_TIMEZONE` | The family's time zone, default `Europe/Berlin`. |
| `HIWISKI_BACKUP_DIR` | Where the backups go on the machine, default `./backups` next to the compose file. A USB disk or a mounted NAS share is better (→ [Backups]({{< relref "setup/backups" >}})). |

**The database passwords are set once:** Postgres takes them when its volume is created. If one is changed in `.env` afterwards, the server can no longer sign in to the database.

## 3. Start

```sh
docker compose up -d
docker compose ps          # app and postgres "healthy", init "exited (0)"
```

The first start takes about a minute: the server waits for Postgres and creates the database schema.

## 4. The setup wizard

Open `http://<address>:<HIWISKI_HTTP_PORT>` in a browser. The wizard asks for the family name and the time zone, creates your account as the administrator and creates the first groups, such as "Parents".

{{< scene name="setup-wizard" height=520 >}}The setup wizard.{{< /scene >}}

Next: [Connecting the apps]({{< relref "setup/apps" >}}).

### A server on the internet: the setup code {#setup-code}

Until the wizard has run, **whoever opens it first becomes the administrator.** On a home network that is you: nobody else reaches the server. So by default the wizard asks for nothing more.

Is the server reachable from the internet — a port forwarded on the router, a VPS, a tunnel? Then switch the **setup code** on **before the first start**, in `.env`:

```sh
HIWISKI_SETUP_CODE_REQUIRED=true
```

The server then prints a code to its log at every start until the setup is done, and the wizard asks for it. Only whoever can read the log — whoever runs the server — can set it up:

```sh
docker compose logs app | grep "Setup code"
# ... WARN ... Setup code: K7M4-2QXP -- the setup wizard asks for it. ...
```

The code changes with every restart until the setup is done; take the one from the latest start. Once the setup has run, the wizard is closed for good, and the setting no longer matters.

| Variable | What |
| --- | --- |
| `HIWISKI_SETUP_CODE_REQUIRED` | `true`: the wizard asks for the setup code from the log. Default `false`. |
| `HIWISKI_SETUP_CODE` | Rarely needed: a fixed code instead of a new one at every start, for an automated install. Set, it switches the code on as well. |
