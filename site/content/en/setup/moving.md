---
title: Moving
description: Moving a Hiwiski server to new hardware or a new address with a backup and a restore.
weight: 60
---

To move an instance to another machine — or to start again after the old one is gone:

1. **An archive of the old instance.** If it is still running, *Back up now* and download the archive in the app, or take the newest one from its `HIWISKI_BACKUP_DIR`. Otherwise, the copy you keep elsewhere.
2. **Install the new instance** ([Installation]({{< relref "setup/installation" >}})) with the same version or a newer one: an archive restores on every newer version, not on an older one.
3. **Open the setup wizard** with the setup code from its log (`docker compose logs app | grep "Setup code"`) and choose **Restore from a backup**. Pick the file, type the backup password, check the preview, **Restore**.
4. **Sign in** as before: members, groups and the administrator come from the archive, and so does the backup password.
5. **Devices:** they sync anew. If the address has changed, enter the new one in the app's settings.

Stop the old instance only once the restore on the new one is complete: `docker compose down` keeps the volumes, `docker compose down -v` deletes them.
