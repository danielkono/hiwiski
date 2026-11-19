---
title: Server & administration
description: 'Running the family server: encrypted backups, updates, the archive, the trash, history and devices.'
weight: 70
scene: settings-backup
lead: Backups, updates, archive, trash, history and devices.
---

## Backup

One encrypted archive of the database and the images, on a schedule you set, before every update and on demand. Download it, restore it in the settings — on this version or a newer one — or set a new server up from it.

{{< scene name="settings-backup" height=480 >}}The backup settings.{{< /scene >}}

## Updates

Change the version in `.env`, `docker compose up -d`. Going back works the same way, with the old version. Apps and server of different versions work together — not every device has to update at once.

## Archive

Finished pages and lists go to the archive: read-only and restorable at any time. Archived items are not deleted automatically.

{{< scene name="archive" height=440 >}}The archive.{{< /scene >}}

## Trash

Deleted items from every area, restorable along with their sharing. Kept 30 days by default.

{{< scene name="trash" height=440 >}}The trash.{{< /scene >}}

## History

Who changed what and when, for every item. Pages also keep versions to restore.

## Devices

Every member sees their devices with their sync state and can sign one out remotely. A device that is signed out loses access at once.

{{< scene name="devices" height=440 >}}My devices.{{< /scene >}}

## How to

{{< steps id="archive-and-trash" title="Archive and restore" >}}
1. Archive a finished list or page with **Archive list** or **Archive page** at the bottom of its info bar. It stays readable, but is hidden from the regular views.
2. **Account → Archive** holds everything archived; **Restore** brings it back.
3. Deleted things wait under **Account → Trash** until their time is up, and **Restore** brings them back with their sharing.
{{< /steps >}}

{{< steps id="lost-device" title="A device is lost: sign it out remotely" >}}
1. On another device open **Account → My devices**.
2. Tap **Sign out** next to the lost one.
3. It loses access at once and clears its data the next time it gets through. Whatever it had not synced yet is lost.
{{< /steps >}}

## Good to know

- Backups go to a directory on the server's machine; the server sends them nowhere. Copy that directory to another place regularly (→ [Backups]({{< relref "setup/backups" >}})).
- A restore replaces everything; afterwards every device syncs anew.
- How far the history reaches back is a setting.
- Settings, backups and members are changed by the administrator only.
