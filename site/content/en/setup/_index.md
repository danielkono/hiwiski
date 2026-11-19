---
title: Setup
description: 'Self-host Hiwiski for your family with Docker Compose: one server at home, no cloud, no account with a provider, no subscription.'
---

Hiwiski is under the [PolyForm Noncommercial License]({{< relref "license" >}}) and free for private use.

## What you need

- A machine with **Docker** and **Docker Compose v2** (`docker compose`, not `docker-compose`). The image is built for **amd64** and **arm64** — a NAS or a mini PC is enough.
- **Two free ports**, 80 and 443 by default. Both can be changed in `.env`.
- **A shell** on the machine, for example over SSH.

Hiwiski does not have to be reachable from outside your home network. The app works offline and syncs with the server once it can reach it again.

## Without a server first

If you want to try it first: the app also runs on its own on a single device. Choose **Use without a server** in the app, enter a name, done. Later you can connect to a server and take everything along. If you do not want to install anything, try the [demo]({{< param "demo" >}}) in the browser.

## What runs

| Service | Job |
| --- | --- |
| `postgres` | the database |
| `app` | the server, with the web app |
| `caddy` | takes the requests on the home network, with TLS if you like |

Plus `init`, which sets the owner of the data directory once on start and then exits.

## The steps

1. [Installation]({{< relref "setup/installation" >}}) — fetch the files, fill in `.env`, start.
2. [Connecting the apps]({{< relref "setup/apps" >}}) — sign in and invite the family.
3. After that: [Backups]({{< relref "setup/backups" >}}) and [Updates]({{< relref "setup/updates" >}}).
