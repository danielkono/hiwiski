---
title: Backups
description: 'Backups of a Hiwiski server: the nightly archive, backups on demand, and restoring them.'
weight: 50
---

- **The server backs up on a schedule** — daily at 02:00 by default, or weekly; the time, and how many archives are kept (1–30, default 7), are set in the app under *Account → Settings → Backup*. A night the server was asleep is caught up as soon as it wakes.
- **Before every update** it backs up by itself, before it touches the database ([Updates]({{< relref "setup/updates" >}})).
- **On demand** under *Back up now*, and **before every restore**, so a restore by mistake can be undone.
- An archive holds the database's content and all pictures, as one file `<id>.hiwiski`.

## Where the archives go

Into a directory **on the host**, the one `HIWISKI_BACKUP_DIR` in `.env` names (`./backups` next to the compose file by default). It can be a USB disk or a NAS share mounted on the host. The server checks at start that it can write there, and does not start otherwise.

**A backup on the disk it protects is not a backup.** It survives a deletion by mistake, not a dead disk or a stolen NAS. Keep a second copy elsewhere, one of them away from home (3-2-1): the server sends nothing anywhere itself, so let a tool you already have copy the directory — Hyper Backup on a Synology, rsync, restic, or a disk in a drawer now and then.

In the app every archive can also be **downloaded** — in the browser as an ordinary download, on a phone through the save dialog.

## Encryption and the backup password

**Every archive is encrypted** ([age](https://age-encryption.org), X25519). The setup wizard asks for a **backup password**; without it no archive can be opened — not by the server, not by us. Keep it in your password manager.

The server backs up at night without knowing the password: it keeps a public key to encrypt with and the private key only wrapped with the password. Every archive carries that wrapped key, so the file and the password are all a restore needs — on a new machine, too.

- **Changing it** (*Backup password → Change*, with the current one) re-locks the archives on the server with the new password. Copies you downloaded before keep the old one.
- **Forgotten?** *Set a new one* makes a new key: backups from then on use the new password; the ones made before open only with the old one. There is no way around that.

An archive and its password together are the family's data. If both got out: set a new backup password, create new addresses for the wall boards and calendar feeds, and have every member change their password.

## Restoring

Under *Account → Settings → Backup*, **Restore** an archive from the list or **Restore from a file**. The password comes first, then a preview — when, which version, how large, how many members — and only then *Replace everything*. The current state is backed up before. Afterwards every device syncs anew.

Only **this family's** archives restore here; another family's is refused — set up a new instance for it and restore it in the setup wizard. An archive restores on the version it came from and **on every newer one**: the server brings it up to its own schema on the way in. One from a newer version is refused with the version to install.

**Devices that were offline, or saw more than the backup holds, lose nothing.** What a device had not sent yet goes to the server by itself. What it had sent and the restored server no longer has, it keeps aside and says so — *"After a backup was restored, 12 entries are only on this device"* — to bring back with one tap. After a lost server, that is the week between the backup and the loss, from the phones.

Who may sign in is not taken from the archive: passwords, disabled members and signed-out devices stay as they are now. A phone signed out after the backup was made stays signed out, and a password changed since stays changed. Devices that are signed in stay signed in, however old the archive is. The same goes for the addresses of wall boards and calendar feeds that still exist, and for the backup password: a restore keeps the ones they have now.
