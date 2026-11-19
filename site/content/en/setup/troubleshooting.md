---
title: Troubleshooting
description: 'Troubleshooting a Hiwiski server: error messages from Docker Compose and the server, their causes and fixes.'
weight: 80
---

| Message | Cause and fix |
| --- | --- |
| `invalid reference format` | `HIWISKI_VERSION` holds more than the version — the whole image name, for example. |
| `manifest unknown` | There is no image with that version. The versions are in the [GitHub releases]({{< param "github" >}}/releases). |
| `HIWISKI_… is missing` | The variable is not set in `.env`, or `.env` is not next to `docker-compose.yml`. |
| `bind: address already in use` | The port is taken by another service. Pick another in `.env`. |
| `app` stays `starting`, the log says `password authentication failed` | `HIWISKI_DB_PASSWORD` was changed after the first start (see [Installation]({{< relref "setup/installation" >}})). |
| Restore refused: schema mismatch | The archive comes from another version. Run the version it was made with, restore, then update. |
| The browser works, the app does not connect (iOS) | Local network access was denied — *Settings → Hiwiski → Local Network*. |
| The browser works, the app does not connect (Android) | A `.local` name; use the IP address. |

If none of this helps: [Support]({{< relref "support" >}}).
