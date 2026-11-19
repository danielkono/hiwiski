# Changelog

What changed from one version to the next, for the administrator of a family's
instance. The website shows the released versions (docs/website.md, "What's new");
the GitHub release of a version carries its section.

Every `feat/…` or `fix/…` branch adds its entry under **Unreleased**, written for a
family administrator rather than as a commit subject. *Upgrade notes* say what has to
be done or known when updating: a new `.env` variable, a change to the compose file
or the Caddyfile, a rollback that is not possible, a minimum app version. A release
turns **Unreleased** into the version (`tool/changelog.sh`).

## Unreleased

## 2026.1.14 — 2026-11-19 {#2026.1.14}

### Fixed

- **2026.1.13 comes out with this version.** Its server image went out without its
  build provenance, so that release stopped halfway: no GitHub release. Everything
  listed under 2026.1.13 arrives with this version — update to this one rather than
  to 2026.1.13.

## 2026.1.13 — 2026-11-19 {#2026.1.13}

### Added

- **Hiwiski's source code is public.** *Account → About Hiwiski → Source code* opens
  the repository on GitHub, with the code of the app and the server.
- **An open invitation can be withdrawn.** Under *Account → Family*, the ✕ in the row
  of an invitation nobody has redeemed yet withdraws it: its code stops working at
  once. For a code handed to the wrong person, or one no longer needed — until now it
  stayed valid until it ran out.

### Changed

- **The website has an address of its own: [hiwiski.app](https://hiwiski.app),** the
  demo is at demo.hiwiski.app. The addresses under hiwiski.danielkononov.de keep
  working, and so do the links in apps that know them.
- **An invitation's QR code is scanned with the phone's own camera.** The camera app
  opens Hiwiski on "Redeem invitation" with the server and the code filled in; the
  app no longer has a scanner of its own, and the code can still be typed in. The
  apps no longer ask for the camera, and the Android app contains no Google code any
  more: the scanner was built on Google's ML Kit. The web app now loads nothing from
  anywhere but your server.
- **Editing works the same way everywhere.** "Edit" at the top of a list, a task, an
  event and a wiki page now turns the page itself into its fields, and "Cancel" and
  "Save" stand where "Edit" was. An event used to open a dialog for this, a task only
  its title, a wiki page had no "Cancel", and a list had its buttons below the form.
  A wiki page that is being edited is still saved when you leave it; "Cancel" is the
  way to leave it unchanged.
- **The top of every entry reads the same.** The title stands there once, at the same
  place and in the same size on an area and on what is opened from it, with its number
  first in the line below it (`TD-14 · Household`). A task's title no longer stands on
  the page a second time.
- **A wiki page beside its tree looks like a list beside the task lists.** The top
  keeps saying "Wiki"; the page's title, its number, the pages above it and "Edit"
  stand under it, and the text starts at the left under the title. The button that
  hides the tree or the task lists is now at the left of its row, and the one that
  brings them back appears at the same spot — no need to move the pointer.
- **Lists look alike.** Events and due tasks in the calendar's list are rows with a
  line between them, as tasks are in their list, with the calendar's colour as a strip
  at the start; a due task has the same box as in its list. Shopping entries have the
  line and the arrow too. The categories stand in one card like tags and calendars.
- **Something new is always the button at the bottom right**: a list, an event, and now
  a wiki page too. The symbol at the top that picks files to import is an upload arrow
  instead of a plus, and the buttons that create something say "Create".
- **Calendars are also found in the account**, beside tags and categories. The search
  symbol no longer appears twice on a tablet, the arrows of the account's rows stand in
  one line, and lists, entries and the account's pages are equally wide on a large
  screen.

### Fixed

- **The licenses page names the native libraries too.** *Licenses of the packages
  used* in *Account → About* listed the app's Dart packages and fonts, but not what
  the home screen widgets and plugins bring: on Android AndroidX, Kotlin, OkHttp and
  the others, on iPhone and iPad Apple's Swift packages. They are listed now, with
  their licenses and notices.
- **Security: a member could read what was not shared with them.** By sending a change
  again in a particular way, a signed-in member could read fields of an item whose
  address they knew — a page shared with them once and no longer, for one — and the
  address of somebody else's dashboard. Nobody without an account could. Update the
  server; the apps need no update for this.
- **Security: a repeating event or task that stopped the apps.** A repetition "every 0
  weeks" was accepted from an app, a calendar file and a subscribed calendar, and the
  calendar of everyone who saw it stopped responding. The server now refuses such a rule
  and leaves it out on import, and the apps show such an entry once instead of hanging.
- **Security: sign-in attempts could use up the server's memory.** Very long usernames
  sent to the sign-in, without an account, stayed in memory for minutes. Names,
  passwords and display names now have a maximum length (100 characters for a name,
  1024 for a password).
- **Importing a large calendar no longer holds up everyone else.** While a file or a
  subscription with thousands of events was written, no device could save anything —
  for minutes. It is now written in portions. If an import is interrupted, what was
  written stays and the next import or refresh continues from there.
- **The server's log no longer contains what a family wrote.** When a change was refused
  by the database, the log line carried the whole entry — a task's title, a page's
  text. It now names the change and the kind of refusal only. If you have passed logs
  on, for a bug report for example, they may contain such lines.
- **A password reset cannot be "changed" to the same password.** After the
  administrator reset a password, the member could enter the temporary password again
  as the new one; it stayed known to the administrator.
- **A backup file is checked more strictly before it is opened**: one whose header asks
  for an unreasonable amount of memory or time is refused instead of stalling the
  server, and so is one from before the first released version.
- **Values the apps cannot read are refused**: a task status or a repetition the apps
  do not know, an event without a start or with an end before its start, a number out
  of range. They were stored and answered as saved.
- Smaller things: a link preview or a monitor asking the server with `HEAD` gets the
  page instead of "sign in first"; what follows the end of a PNG image is no longer
  stored; a dashboard or calendar link made of one repeated character is refused; the
  server points out in its log when the database password is still the one from
  `.env.example`.

- **The web app in the browser is the new one after an update.** A browser that had
  opened the web app before kept running the version it had loaded first, however often
  the server was updated: fixes that were in a release did not show, and "Reload" changed
  nothing. Only a reload without the browser's cache helped. From this version on the
  browser gets the new web app with the next page load, also where it was stuck on an
  old one. The apps for phone and tablet were not affected.
- **Reminders for events somebody else entered** no longer wait for the app to be
  opened. The apps for iPhone, iPad and Android now fetch changes in the background for
  as long as you are signed in, not only while something of your own waits to be sent,
  and set the reminders from what they fetched. A home screen widget could show such an
  event without a reminder ever ringing for it. How often the system lets the app run in
  the background is up to the system: on iPhone and iPad not at all after the app was
  swiped away, until it is opened again.
- **The home screen widgets on Android show what was chosen for them.** In the released
  app every widget showed the Kanban column, whatever it was set up for. Widgets already
  on the home screen correct themselves after the update; no need to place them again.
- **A reminder stays in the notification centre** after it rang. It used to disappear
  with the next change to any calendar.

### Upgrade notes

- **The Android app needs Android 8.0 or newer.** A phone or tablet with Android 7
  keeps the app it has, but gets no update to this version any more.

## 2026.1.12 — 2026-11-14 {#2026.1.12}

### Fixed

- **2026.1.11 comes out with this version.** Its Android app could not be built, so that
  release stopped halfway: no GitHub release and no new Android app. Everything listed
  under 2026.1.11 arrives with this version.

## 2026.1.11 — 2026-11-13 {#2026.1.11}

### Added

- **Widgets for the home screen** on iPhone, iPad and Android: *Upcoming events* from
  the calendars you choose, a *Shopping list*, a *Task list* and *one column of a Kanban
  board*, each with what is still open and how many entries are open and done. Add them
  on the home screen as any widget; what each one shows is set in the app under
  *Account → Widgets* — a tap on a widget not set up yet leads there, a tap on one that
  is opens the calendar or the list. The widgets refresh themselves from the server
  while the app is closed, as often as the system lets them (about every 15 minutes);
  when the server cannot be reached they keep what they last showed and say how old it
  is, and the app updates them at once whenever something changes on the device. They
  need *Stay signed in*, and signing out clears them. iOS 17 or later.

- Lists and wiki pages can be exported as Markdown and imported again. *Export* is at
  the bottom of a list's or a page's info bar: a task list, a shopping list or a board
  becomes one Markdown file; a wiki page becomes one too, or — with its subpages and
  images, each of which can be left out — a zip archive laid out like a folder of
  notes. The browser downloads the file, every other device asks where to save it.
  The **+** in the header of *Tasks* and of the *Wiki* imports: it takes Markdown
  files and zip archives, shows what it found in them and what it could not read, and
  creates it on *Insert* — as new lists and pages, without changing what is there.
  Notes from other apps import the same way: a folder of Markdown files, zipped,
  becomes a branch of the wiki. Sharing, assignments, comments and the history are
  not part of an export.
- Pages, task and list descriptions and event notes can be written **formatted**:
  headings are large, bold is bold, lists show bullets, tasks their boxes (a tap ticks
  them), links their chips and images the image, while the Markdown that does it stays
  out of sight — it shows, faded, only where the cursor is. The first button of the
  editor's bar switches to the Markdown source and back at any time; *Account →
  Customize* sets which one texts open in (formatted, unless changed). The text is
  saved as the same Markdown either way. Ctrl/⌘+B and +I make the selection bold and
  italic, and pressing *Bold* or *Italic* again takes it back.

### Changed

- Links to other websites in pages, descriptions and notes open in the browser with a
  tap; before that, resting the pointer on one — or a long press on the phone — shows
  the address it leads to. An image from another website, `![label](https://…)`, now
  reads as such a link with its label, instead of the note that it was not loaded: it
  is still never fetched by itself, so that site does not learn who reads the text.
- On the phone, the small hint above lists, the calendar, the wiki and the start page
  ("Pull for filters", "Pull to customize") goes away by itself after the bar has been
  pulled down a few times, and gives its line back to the content. *Account →
  Customize* hides it sooner, or keeps it for good.

### Fixed

- Ticking a nested checkbox in a Markdown list ticked its parent instead, and the
  parent's box ticked the innermost one. Each box now ticks itself.
- In a Markdown list with a blank line in it, the first level showed bullets instead of
  checkboxes; they are boxes again.
- The filter bar no longer slides out by itself when a list bounces back at its top
  after a fast scroll; only pulling down with a finger opens it.
- On the phone, a wiki page's *Edit* (and *Save*) button is in the header like on a task
  or an event, no longer in a row of its own below it.
- In the wiki, every step of a page's breadcrumb is a link that opens that page.
- Signing out on purpose no longer ends on the "Access lost" screen: the server's
  answer to the sign-out was taken for a sign-out from another device, so one had to
  sign out twice.
- On a wide screen, the card that opens when hovering over an event on the last day of
  the week stays inside the window.
- A link to a long title in a comment stays inside the comment instead of running out
  of it.
- The filter bar no longer leaves an empty strip above the list once it has been
  pulled down and scrolled away.
- In the text editor of a task, an event and a wiki page, Tab indents the line (or the
  selected lines) and Shift+Tab takes it back, which nests list items: under the text
  of the item above, so numbered lists nest as well as bullets.
- On a large screen, the calendar and the reminder of an event are picked from a list
  right under the field instead of a sheet from the bottom of the window.
- A task and an event show the list or the calendar they belong to as a link in their
  header.

- On an iPad held upright and in windows of a similar width, wiki pages and recipes
  were squeezed into a narrow strip next to the page tree and the info bar. The info
  bar now moves below the content when there is no room beside it, and up to a width
  of 1200 the navigation is the narrow rail instead of the drawer.
- The row of tag filters above a list or the wiki could run a few pixels past its end
  at some window widths.
- On the phone, a sheet left the status bar and the tab bar bright while it darkened
  the rest of the screen.

### Upgrade notes

- The widgets ask the server with two reads this version adds. Until the server is
  updated, they show only what the app on the device hands them.

## 2026.1.10 — 2026-11-06 {#2026.1.10}

### Changed

- The database starts from one baseline instead of the 36 steps that built it. Nothing
  changes for a family: at its first start the server takes the existing database over
  without migrating anything.

### Fixed

- The sign-in, setup and password screens show the app's icon instead of a plain
  letter, and the website's tab the same icon as the web app's.

### Upgrade notes

- Update from 2026.1.9 or 2026.1.8. An older server goes through 2026.1.9 first.
- There is no rollback to 2026.1.9 once this version has started: the older server no
  longer recognizes the database's history. The backup the server makes before the
  update restores on this version.
- Update the apps with the server: this version's apps expect a server of 2026.1.10 or
  newer. An app older than 2026.1.9 updated straight to this one may have to be
  installed afresh.
- Invitations created before 2026.1.8 no longer open; create them again.

## 2026.1.9 — 2026-11-05 {#2026.1.9}

### Changed

- Nothing changes on an instance: this version is the first whose iOS app comes out
  of the same release as the server and the Android app. Updating from 2026.1.8 needs
  no steps beyond a new image.

## 2026.1.8 — 2026-11-05 {#2026.1.8}

### Added

- Backups are encrypted, always. The setup wizard asks for a backup password; without
  it no backup can be opened, so keep it in your password manager. It can be changed
  in the settings, or set anew if it is forgotten (older backups then open only with
  the old one).
- Backups go to a directory on the machine (`HIWISKI_BACKUP_DIR`), which can be a USB
  disk or a NAS share, and can be downloaded and uploaded in the app.
- A backup restores on its own version and on every newer one, and a new server can
  be set up from a backup right in the setup wizard.
- The server backs up by itself before every update, and before every restore.
- The backup schedule (daily or weekly, the time, how many are kept) is set in the
  settings, a night the server was asleep is caught up, and a failed backup is shown
  with its reason.
- While a backup is restored, every app shows it and takes no changes, also one
  started meanwhile; the server refuses changes until it is done.
- After a restore, devices lose nothing they saw since the backup: what they had not
  sent goes out by itself, and what the restored server no longer has waits on the
  device, to be brought back with one tap ("Only on this device").
- A running server refuses another family's backup and points to the setup wizard
  of a new instance instead.

- A website for Hiwiski: what it does, how to set up a server, and real views of the
  app to try on the feature pages.
- The administrator can disable a member (no sign-in, all devices signed out), enable
  them again, or sign out all of a member's devices, from the family screen.
- Each person can store up to 5 GB of pictures, and the server processes at most four
  uploads at once.
- A long press on a task, a shopping entry or a card edits its title right in the
  row. Where a long press picks the row up, holding it and letting go without moving
  does.
- A Kanban board can have several done columns (for example "Done" and "Handed
  over"); at least one column stays open.
- The wiki overview can expand or collapse all pages at once.

### Changed

- The app's texts are plainer and shorter, in German and English, and use one word for
  each thing: sync, dashboard, web version, version.
- A new server can only be set up with the setup code it prints to its log
  (`docker compose logs app | grep "Setup code"`).
- Changing your password signs out your other devices; a reset by the administrator
  signs out all of the member's devices. Like any loss of access, they are locked, not
  cleared: signing in again sends their waiting changes.
- Members who may *write* a shared list, calendar or page can change what is in it, but
  only the owner deletes, restores or moves the container itself, and only an item's
  owner moves it elsewhere.
- Assigning someone to a list is the list owner's choice. On a task or event, an
  assignment shares the item only when the owner adds that person; one made by someone
  else, or brought along by an import, a refresh or a restore, no longer gives access.
- The app offers deleting a list or calendar, moving a page or event and assigning a list
  only to their owner.
- Dashboards and calendar feeds can no longer be shared; their secret links travel only
  to their owner's devices.
- Images in texts that come from other web servers are no longer loaded; a note shows
  where they would come from.
- Photos are stored without their location, time and camera data.
- Opening an invitation link on a signed-out device, or scanning one on "Redeem
  invitation", shows the server address and asks before connecting. Invitation QR codes include https when the server uses it, and the
  redeem screen warns on plain HTTP.
- A new server signs in to Postgres with a role of its own that is no superuser, and the
  server container runs without Linux capabilities. The web app sends a
  Content-Security-Policy.
- The server believes a client's forwarded address only from its own Caddy; a server
  run without Caddy believes no one but itself.
- A recurrence rule the devices cannot expand is refused; a subscribed feed's event with
  such a rule is imported as a single event.
- A text with a paragraph longer than 10,000 characters is shown as plain text.
- A change too large for the server is kept on the device and waits there, with a note,
  until it is shortened; the page text warns from 90 % of the limit.
- Caddy 2.11 and Spring Boot 4.1.2.
- A list's history also shows what happened to its tasks — ticked off, changed,
  deleted — each with the task's name.
- The website shows the views that need a server too: devices, backups, sharing,
  invitations, subscriptions, ICS links, recipe import and the wall dashboard.
- "More fields" on a task list opens the new task as a sheet over the list, like a new
  event, instead of a page of its own; the list stays where it was.
- A card's history says which column it was moved to ("moved to “Doing”"),
  also in the list's history.

### Fixed

- Security review of 2026-10-31 (one high, nineteen medium and twenty-seven low
  findings):
  - Only the administrator can see open invitations and their codes; codes are stored
    only as a hash and shown once, when created.
  - Comments can only be written on items one can read; the server no longer reveals
    whether an item someone cannot see exists.
  - A deleted task can no longer be brought back by ticking it off; members with
    *check off* can tick off dates of repeating tasks, as documented.
  - "Done by" and "archived by" always show who actually did it.
  - Calendar links include only events their owner may see, need a long random token,
    stop working for disabled members, and can no longer carry forged entries.
    Imports and subscriptions no longer overwrite events the importer may not edit;
    subscribed calendars stay read-only on every device.
  - Restoring a backup no longer brings back signed-out devices or old passwords.
  - Sign-ins, recipe imports, very large syncs, pictures with huge declared sizes,
    extreme repeat rules and long lines of `[` can no longer overload the server or
    freeze the app.
  - Guessing a password, an invitation code or the current password is slowed per
    address, and someone else's failed sign-ins no longer keep you out.
  - Signing in on a device no longer signs out another member who used it before, and
    nobody can block another member's list order or take the id of a picture about to be
    uploaded.
  - Two malformed changes no longer block a device's sync with a server error.
  - The legal notice and privacy buttons open only web addresses.
  - The backup guide explains what an archive contains and how to keep it safe.
- Second pass of the review (2026-11-01):
  - "Try again" on a change the server refused shows the refusal again instead of
    silently dropping the change.
  - A refused push no longer stops the sync before it fetches the others' changes.
  - Very long ingredient lines, crafted recurrence rules, long texts, GIFs with a huge
    canvas and large animations no longer overload the server or freeze the app; WebP
    images get a preview.
  - Wrong passwords for one account are capped across all addresses, without keeping
    the member's own devices or home address out; invitation codes are stored under a
    slow, salted hash.
  - A restore keeps devices signed in however old the archive, and keeps wall-board and
    feed addresses that were replaced since the backup.
  - A calendar subscription can only be added to one's own calendar, and a disabled
    member's subscriptions stop refreshing.
  - An event the ICS feed cannot write is left out instead of failing the whole feed;
    event times need a four-digit year.
  - Recipe pages with `<scripty>`-like tags or a `<script` in a comment import again;
    a line over 500 characters is cut and marked, at most 200 ingredients are imported.
  - Photos also lose what comes after the picture (Motion Photo videos with their
    location); Ultra HDR photos keep showing as HDR.
  - "Delete task" is labelled correctly again.
- "Undo" after deleting a task, card or ticked-off entries scrolls to what it brings
  back, as adding does.
- In the web version, clicking the delete symbol on a task, card or comment shows
  "Hold to delete" instead of opening the task.
- The "Archived" note with "Undo" goes away by itself again, like every "Undo" note.
- "+ Tag" stands level with the tags beside it.
- An address the web version has no page for shows "This page does not exist" with a
  way back to the start, instead of an error page.
- With no calendar yet, the empty calendar offers "New calendar" instead of a new
  event that had no calendar to go into.
- In the web version, the cross on a selected tag and the arrow in the dashboard hints
  no longer show as empty boxes.
- With only subscribed or imported calendars, the calendar offers a calendar of your
  own instead of an event that has nowhere to go.

### Upgrade notes

- Update server and app together: the setup wizard of older apps cannot set up a new
  server, and invitation codes no longer appear in the family list after creation.
- Migrations V033 (hashes existing invitation codes), V034 (existing task and event
  assignments count as the owner's), V035 (removes list orders created under another
  member's id) and V036 (slow hashes for new invitation codes; open invitations keep
  working until they expire). At the first start, existing shares of
  dashboards and calendar feeds are removed.
- Fetch the new `docker-compose.yml`: it puts the stack on a fixed network
  `10.217.84.0/24` with Caddy at a fixed address, the only one the server trusts (if
  Docker reports an overlap, set `HIWISKI_NETWORK_PREFIX`), passes `HIWISKI_SETUP_CODE`
  through, pins Caddy and drops the container's capabilities. Behind a NAS proxy or
  tunnel in front of Caddy, add `trusted_proxies` to the Caddyfile (the new one shows
  how). The old `hiwiski_default` network stays until `docker compose down`.
- New optional variables: `HIWISKI_SETUP_CODE` (a fixed setup code for automated
  deployments), `HIWISKI_MEDIA_QUOTA_PER_MEMBER` (default `5GB`, `0` for no limit) and
  `HIWISKI_MEDIA_PARALLEL_UPLOADS` (default 4). A member who already stores more than
  5 GB cannot upload until the quota is raised.
- New installs get `HIWISKI_DB_ADMIN_USER` and `HIWISKI_DB_ADMIN_PASSWORD` in `.env`.
  Existing servers keep working unchanged; moving to the database's own role is optional
  (Setup → Updates).
- QR codes made before the update assume http; make new ones if your server uses https.
- Calendar feeds with a weak token stop working until their owner creates a new link.
- Events already stored with a refused recurrence rule stay; the app shows them once, on
  their start. WebPs uploaded before have no preview until uploaded again. A member at
  the picture quota because page history still holds images needs a higher
  `HIWISKI_MEDIA_QUOTA_PER_MEMBER`.
- Subscriptions someone attached to another member's calendar stop refreshing; the
  calendar's owner can remove them without losing the calendar.
- Apps older than this version show the cards of a second done column in the first
  one; update the apps before giving a board several done columns.
- **New mandatory variable `HIWISKI_BACKUP_DIR`**, the directory on the machine the
  backups go to (`.env.example`: `./backups`), and a new `docker-compose.yml` that
  mounts it. Archives from before (`*.hiwiski.zip` in the `hiwiski-data` volume) are
  unencrypted and cannot be restored by this version; copy them out first
  (`docker compose cp app:/data/backup ./old-backups`) if you want to keep them, and
  keep them private.
- An existing server has no backup password yet and backs up nothing until one is set:
  *Account → Settings → Backup → Forgot it? Set a new one*. The settings say so.
- The first start of a new version backs up before it migrates; the app is reachable
  once that backup is written. If it fails (a full disk, mostly), the server does not
  start and the previous version still does.
