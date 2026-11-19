---
title: Why Hiwiski
description: 'Why Hiwiski exists: a family organiser that runs at home, without a cloud and without tracking, inspired by Immich.'
lead: What Hiwiski is built for — and what it deliberately is not.
---

## How it came about

With the birth of my son it became necessary to organise our everyday life better. Inspired by Immich, I wanted to build something similar myself. As I do not have much free time, I wanted to find out how far I would get with AI, and to use the project to learn every part of such a piece of software: from hosting a website and a VPS to publishing in the app stores. As a by-product we now have an app at home that helps us forget fewer things in a chaotic everyday life, plan the shopping ahead, and keep important information locally instead of in some cloud. My NAS is not reachable from the internet, so I concentrate on working offline.

— Daniel

## Principles

**Usable offline.** The apps should keep working without the server. In the evening everyone is at home, and then all devices sync.

**Platform-independent.** Every platform should be covered, so everyone can use Hiwiski. The web version and the app are nearly identical. Different versions should keep working together too.

**Simplicity.** A simple Docker setup; everything else is set up in the app. If you like, you can also use the app without a server.

## Your data stays with you

No cloud, no account with a provider, no telemetry. The logs stay on your server and leave it only when you send them yourself. How backups and moving to another machine work is under [Setup]({{< relref "setup" >}}).

## What Hiwiski is not

- **No file storage.** Images on recipes and pages, yes — a folder tree for any file, no. There are better projects for that.
- **No push notifications.** No additional services: the app creates notifications itself.
- **One instance per family.** The server is not multi-tenant. It is a hobby project for families.
- **No ads and no Pro tier.**

## License and project

Hiwiski is under the [PolyForm Noncommercial License]({{< relref "license" >}}): free for private and non-commercial use. I do not take pull requests at the moment. Everything about development — bugs, wishes, questions — goes through [GitHub]({{< param "github" >}}).
