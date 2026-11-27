# Architecture

How Hiwiski is built and why. Read this first; the guides for the server
([`server.md`](server.md)), the app ([`app.md`](app.md)) and the contract
([`api.md`](api.md)) go into the details of each side.

## What it is

A self-hosted app for **one** family: calendar, tasks including the shopping list and
Kanban boards, a wiki that also holds the recipes, a search across everything, a start
board and a dashboard for a wall tablet. One Flutter client for every platform (Android,
iOS, macOS, Windows, Linux, web), one Spring Boot server in the family's home, Postgres
behind it. No cloud, no account with a provider, no telemetry.

Three properties decide almost every design question:

1. **Usable offline.** A home server cannot be reached from on the road. Every input
   goes through immediately, on the device, and syncs later.
2. **Compatible across versions.** Nobody updates five devices at once. An older app must
   not break against a newer server and must not destroy what it does not know.
3. **Easy to set up for non-experts.** One compose file, one `.env`, a setup wizard.

When a choice seems odd, it usually serves one of these.

## Stack

| Part | Choice | Why |
| --- | --- | --- |
| Client | Flutter, one project for all platforms | one codebase for all of a family's devices |
| Client database | Drift (SQLite; on the web via WASM, in memory) | typed, observable, the same API everywhere |
| Client state | Riverpod 3 with `riverpod_generator` | the provider's kind and lifetime follow from its signature |
| Client routing | go_router with typed routes | a typo in a path is a compile error |
| Server | Spring Boot 4, Java 25 | |
| Server modules | Spring Modulith | module boundaries are checked in the build |
| Database | PostgreSQL 18 | full-text search, JSONB, transactional DDL, a row lock for the sequence counter |
| Data access | jOOQ, generated from the schema | SQL as written, no ORM behaviour to switch off |
| Migrations | Flyway | |
| Contract | OpenAPI, code generated on both sides | one source for both ends of every call |
| Operations | Docker Compose: Postgres, the server, Caddy | one file a family can copy |

**Tests run against a real Postgres** (Testcontainers), never an in-memory database.
Everything that defines this application — full-text search, JSONB, transactional DDL,
the sequence counter's row lock — is Postgres-specific; an H2 suite would test H2.

## Repository

```
api/        the OpenAPI contract, split by module; openapi.bundled.yaml is generated
app/        the Flutter client (all platforms, the web version, the website's scenes)
deploy/     docker-compose.yml, Caddyfile, .env.example — what a family installs —
            and the Dockerfiles of the server, demo and website images
docs/       this documentation
golden/     test cases both sides are checked against (recurrence rules, references)
server/     Gradle multi-project
  api/      generated Spring interfaces and DTOs only
  db/       Flyway migrations and the jOOQ code generated from them
  app/      the application
  buildSrc/ the contract check (SpecContractTask)
site/       the website (Hugo), with the setup guide for administrators
tool/       version.sh, changelog.sh, the site's tool installer and translation check
```

A monorepo, because contract, server and client have to change in one go; a broken
contract would otherwise show up two releases later.

## The data path

```
input → local database (visible at once) → outbox → push → change log → pull → other devices
```

The client **always reads and writes its local database**, never the API directly —
even where it would only pass data through. There is no "Saving, please wait". A
screen watches a Drift query; a change writes the row and an outbox entry in one
transaction; the sync engine sends the outbox and pulls what others changed, and the
query emits again.

The one exception are the **home screen widgets**: native code that runs while the app is
closed, and so asks the server itself — two reads, never a write
([`home-widgets.md`](home-widgets.md)).

### Two kinds of API

| Through sync | Through REST |
| --- | --- |
| every item: lists, tasks, calendars, events, pages, a pinboard's elements and connections, comments, tags, boards, widgets, feeds, subscriptions, list orders | sign-in, invitations, devices, members and groups, the handshake |
| | sharing (the share sheet) |
| | wiki revisions, history, server search |
| | the home screen widgets' reads: the agenda, a list's summary |
| | ICS and recipe import, images |
| | administration, backup, restore, trash, categories |

A second write path over REST for synced items would need validation, sharing, conflict
handling and the change log twice — and would drift.

### What lives on the device

| What | Mirrored |
| --- | --- |
| every item the member may see | **completely** — the basis of working offline |
| images | those that were viewed, kept afterwards; those added here, until they are uploaded |
| wiki revisions, history | no: they never change, can be long, are rarely needed |

Revisions and history are therefore not available offline, and the screens say so in
place. There is no size limit; Account → Storage shows what is used and offers to free
up the image cache. **That never touches the outbox** or anything else not yet synced.

In the browser the mirror lives **in memory only**: the web version is not used offline,
and every page load fetches the state fresh. It still reads and writes a local database
— one data path on every platform. While a change has not reached the server, the
browser asks before the tab closes.

## Sync

### The sequence number

Every change on the server gets the next number of one counter per instance
(`change_sequence`, a single row, `UPDATE … SET seq = seq + 1 RETURNING seq`). Not a
Postgres `SEQUENCE`: those are handed out on insert, not on commit, and a device could
skip a number for good. The row lock until commit makes commit order and number order
the same. Numbers, not timestamps, because device clocks disagree.

Each change is written to `change_log` **in the same transaction** as the change itself:
`seq`, the entity and its container, the operation, the changed fields and their values,
who and from which device.

### Columns every synced item has

| Column | Meaning |
| --- | --- |
| `id` | UUIDv7, **generated by the client** — an item created offline needs an identity at once |
| `owner_id` | the member it belongs to |
| `version` | the item's version, set by the server: the `seq` of its last change |
| `field_seq` | JSONB: field name → `seq` of that field's last change |
| `created_*`, `updated_*` | server time on receipt, and who |
| `deleted_at`, `deleted_by` | soft delete; `null` while alive |

`sync` finds these columns by name on every synced table; no module reinvents them.

### Pull

The device sends its last position (`lastSeq`), its device id and how many changes it
still holds (`pendingCount`, shown in the device list). The server answers with the
log entries after that position, **filtered in the same query** to what the member may
see (see [Sharing](#sharing)).

Entries carry `seq`, `entityType`, `entityId`, `containerType`, `containerId`, `op`,
`fields`, `version`. The envelope is strictly typed; `fields` is free-form, with a
schema per type in the contract. The client decodes by `entityType` in a hand-written
dispatcher and **skips types it does not know** — an older app against a newer server.

Four operations: `upsert`, `delete`, and the synthetic `access_granted` and
`access_revoked` (below).

**A device without a position fetches the state, not the history.** The log is cleaned
up after its retention period (90 days by default); replayed from zero it would miss
everything older. The first sync, a rebuild after `resync_required` and the catch-up
after `access_granted` therefore pull a **snapshot**: every living, visible item once,
with all fields, containers before their content, page by page through a cursor. The
log then continues from the position the snapshot started at — what happened meanwhile
comes a second time, in log order, and settles correctly.

If a device's `lastSeq` lies before the oldest log entry, the server answers
`resync_required`. The device first pushes its outbox; what is refused lands in a list
the member can copy from. Then it discards its mirror and pulls a snapshot.

### Push

The outbox holds one entry per local change. Every mutation carries:

- a **`mutationId`** from the client — the idempotency key. A retried push after a
  dropped connection is not a duplicate. A mutation the server has seen gets the
  answer it got the first time (`processed_mutation`). The answer belongs to the member
  who sent the mutation and to the item it was about: the same id from another member
  or about another item is `rejected` (`sync.mutation_id_reused`).
- **only the changed fields.** Never whole objects. Not an optimisation: an older app
  that sent whole rows would blank the fields it does not know.
- **`baseVersion`** — the version it builds on, from the last pull. **It is never
  incremented locally**; doing so would turn every later change into a conflict.

| Result | Meaning | The client |
| --- | --- | --- |
| `applied` | accepted | removes the entry, keeps the new `version` |
| `conflict` | some fields lost (below), the server's values attached | shows it |
| `rejected` | refused for good (no permission, invalid), with an error code | blocks the entry's chain, shows it |
| `duplicate` | already applied | counts as applied |

The outbox goes out after every own change, at start, when the app returns to the
foreground, on every real-time signal, every 15 seconds while the server is unreachable,
and — on Android and iOS — from a background job for as long as a member is signed in
(Android: with a network, at most every 15 minutes; iOS: when the system grants it;
neither after a force quit). The job runs whether or not something waits: it also pulls
what others changed and schedules the reminders from it, which otherwise only happens
while the app is open. Without a server it only fills; when the device connects, it is compacted to one
creation per item and sent the same way.

**Chains.** A task in a list created offline, a subpage under a new page: if the first
push is refused, the dependent ones must not run. Every outbox entry knows its
preconditions; a `rejected` blocks its chain, and the app shows it as one group
("Plan vacation and 3 more changes could not be applied" — try again, view, discard).
Temporary errors retry with backoff and show nothing: an unreachable server is everyday
life, not an error.

### Conflicts, field by field

What counts is the server's order of receipt, not a device clock. For every field of a
mutation:

- if `field_seq[field] <= baseVersion`, the field is written;
- otherwise someone changed that field since — this field is dropped, the rest of the
  mutation goes through, and the answer is `conflict` with the current values.

Whoever ticks a task off while someone else moves its due date loses nothing. Within one
field, whoever reaches the server first wins; that is the price of not using CRDTs,
which would solve a problem this app has in exactly one place (the wiki text) at the cost
of a data model nobody can read by hand.

- **A conflict is always shown**: a banner with the field, the lost and the current
  value — as a person reads them, never as ids or JSON — and "Take mine anyway".
- **Wiki text:** on a conflict on `content`, the server's text stays and the losing text
  is stored as a **revision of kind `CONFLICT`**. The banner links to it. Nothing is
  lost, nobody has to merge, nothing is locked.
- **Series:** ticked-off occurrences of a recurring task and the exceptions of a
  recurring event are **merged, not replaced**: two devices ticking off different dates
  offline both get through.
- **Properties are fields.** Where a type keeps optional fields in a property map (a
  wiki page's kind, see [`wiki-page-kinds.md`](wiki-page-kinds.md)), each key has its
  own `field_seq` entry and its own conflict. The map is never replaced as a whole.

### Limits

Every mutation holds the instance's writer lock in turn, so one oversized push would
stall every other device. `SyncLimits` caps a push — far above what a family writes:

| What | Limit | Beyond it |
| --- | --- | --- |
| Request body (any JSON request) | 32 MiB | `413 request.too_large` |
| Mutations per push | 200 (the app sends 50) | `400` for the call |
| A text field | 200,000 characters | the mutation is `rejected`, `sync.value_too_large` |
| A list of ids | 500 entries | likewise |
| A JSON field | 256 KiB | likewise |
| A merged map (an event's exceptions) | 5,000 keys | likewise |

The app checks the value limits itself: a change beyond them is kept on the device and
its outbox entry is **held** — not sent, shown with the changes that cannot sync — until
a later change of the same field makes it fit. A push refused as a whole (`400`, `413`)
is halved until it goes through, and the run goes on to its pull.

**Who and when belong to the server.** `doneBy` and `archivedBy` are set to whoever
pushes, whatever the client sent; `doneAt` and `archivedAt` keep the client's time
(it matters offline) but never lie after the moment of receipt.

### Deletions, retention, the archive

Deletes are soft (`deleted_at`). Without a tombstone a device that was offline would
never learn of it and would recreate the item on its next push.

| Period | Default | Setting |
| --- | --- | --- |
| Trash | 30 days | `retention.trash.days` |
| Change log (and so the history) | 90 days, at least 14 | `retention.log.days` |

- A delete of an item the member cannot see is answered `applied` with nothing done —
  the same as for an id that does not exist. A refusal would confirm the item exists.
- An upsert on a deleted item **brings it back** — someone edited it offline. That is a
  restore and needs what a delete needs; anyone else gets `rejected` with
  `sync.entity_deleted`.
- **The archive is not a deletion.** Archived lists and pages are living items with
  `archived_at`/`archived_by` set — ordinary synced fields. They stay mirrored, open
  offline, are read-only (the server refuses changes with `archive.read_only`) and are
  never cleaned up. A task is archived when its list is; a page is archived per page.

### Real-time signal

`GET /api/v1/events` is a server-sent event stream. **The signal carries no data**, only
the newest sequence number; every signal triggers an ordinary, filtered pull, so a
missed one breaks nothing. Signals are batched over 250 ms, with a heartbeat every
25 seconds.

`EventSource` in the browser cannot send a header, so the app first asks for a ticket
(`POST /api/v1/events/ticket`: valid 60 seconds, once) and passes it as a query
parameter. The stream is the only endpoint outside the contract: OpenAPI cannot express
it usefully.

## Sharing

### The model

**Whoever creates an item owns it** and may do anything with it. **Anyone else may do
what a share allows** — and does not even see the item otherwise. There are no roles and
no fine-grained permissions.

| Level | Allows |
| --- | --- |
| `READ` | see, search, comment, link |
| `CHECK` ("check off") | also: tick a task or an occurrence off, move a card to another column. Nothing else |
| `WRITE` | also: create, change, delete **within the container**. Not: change the sharing, delete or move the container |

`CHECK` exists for the wall tablet and for children on the shopping list; with only read
and write, either the tablet can do nothing or it can delete the list. Items without a
completion state (calendars, pages, tags) do not offer it.

"Within the container" is literal: a non-owner deletes an item only if they may write it
*and* its container. Lists, calendars, root pages and boards have no container — only
their owner deletes or restores them, and only the owner moves an item to another
container, because a move hands it to another audience.

### Recipients and inheritance

A share goes to a **member** or a **group**. Groups are stored as a reference, not
expanded into members: whoever joins later is included.

**Assignment shares.** Assigning a task to someone shares it with them (`CHECK` for
tasks, `READ` for events), shown as its own row in the share sheet. Only the owner's
assignment brings someone new in; a writer's assignment only raises the level of someone
who sees the item already. So *write* cannot share.

| Item | Inherits from |
| --- | --- |
| task | its list |
| event | its calendar |
| wiki page | its parent page (a root page from nothing) |
| comment | the item it is on |
| widget | its board |

**A share of its own replaces the inherited one**, for the item and everything below it.
A page without its own shares that moves to another branch takes on that branch's.

### `effective_access`

The resolution is **materialised** in `effective_access` (`member_id`, `item_type`,
`item_id`, `level`) and recomputed when a share changes, a page moves, group membership
changes or an item is created. Every read query — pull, search, history, links — joins
against it **in the same query**. Walking up the tree per query would be fast enough at
family size, but it would be the same logic in many places, and a separate visibility
check after the query is a time window in which even an item's title leaks.

### Sharing and offline

- **Shares take effect retroactively.** A member given access today to a calendar filled
  last month would never see those changes: they lie before their position. The server
  therefore writes a synthetic **`access_granted`** for the member, and the device pulls
  the container as a snapshot. **`access_revoked`** makes the device delete the
  container's local data. A wiki move does this for the whole subtree, per member
  affected.
- **The client is never the authority.** It allows what it last knew; the server checks
  again on push and refuses what it must, visibly.
- **The share sheet works offline** from the last state the server sent for that item;
  a change waits and goes out with the next sync run. A sheet never seen on the device
  does not open offline.

### The administrator

Exactly one member, created in setup. The administrator manages **the server** —
instance settings, members (create, invite, disable, reset a password, sign out their
devices), groups, backups and restore, the log, the instance-wide trash — but **sees no
one else's content**. There is no password reset by e-mail; the administrator resets
passwords, and their own is reset in the container
(`docker compose exec app hiwiski reset-admin-password`).

### Tokens that act as their owner

A **dashboard** (the wall tablet's board) is opened without a sign-in at an address with
a token. The token is a restricted session of the board's owner: it sees what the owner
sees, limited to what is on the board. A **calendar feed** (`/ics/{token}.ics`) works the
same way for the chosen calendars. That is why boards, widgets, feeds and list orders
cannot be shared — the server refuses it — and sync delivers their tokens to the owner's
devices only.

## The server's modules

One module per top-level package below `de.danielkononov.hiwiski`. A module's root
package is its public API; `internal/` is private. `ModularityTest` checks the
boundaries and cycles on every build.

| Module | Holds |
| --- | --- |
| `platform` | sequence counter, readable keys, instance settings, error model, handshake, request limits, trusted proxies |
| `identity` | members, groups, devices, sign-in, invitations, setup |
| `access` | ownership, shares, `effective_access` |
| `sync` | change log, pull, push, idempotency, the event stream, item history, archive rules |
| `recurrence` | RRULE expansion (lib-recur) |
| `tag` | tags (assigned as a `tags` field on the items) |
| `link` | references between items, parsed from text |
| `todo` | lists, tasks, the shopping list, Kanban, occurrences, list orders |
| `calendar` | calendars, events, ICS import, subscriptions, feeds |
| `wiki` | pages of any depth, kinds (recipes), revisions, recipe import, comments |
| `catalog` | products and categories of the shopping list |
| `dashboard` | boards and widgets, the dashboard address |
| `search` | full-text search across modules, and the history endpoint |
| `media` | images attached to items |
| `admin` | backup, restore, the trash, settings and log endpoints |

**The cross-cutting modules know no domain types.** Every domain module registers with
them instead of being listed there:

| Module | Interface | What a domain module provides |
| --- | --- | --- |
| `sync` | `SyncType` | how its entity is read, written and put into the log; its fields (`SyncField`, `SyncProperty`) |
| `access` | `Ownable` | who owns an item and where it inherits its sharing from |
| `link` | `LinkSource` | which field holds text with references, what a target is called |
| `search` | `Searchable` | what matches, filtered for visibility in the same query |
| `admin` | `Restorable` | what of it is in the trash and how it comes back |

Three directions are fixed:

- **`access` points to `sync`, not back.** `sync` needs a visibility check to filter the
  log and declares it as an interface (`ChangeVisibility`); `access` implements it and
  writes share changes into the log.
- **`platform` never points to `access`.** `access` builds on `platform`.
- **Domain modules use the cross-cutting ones, never the other way round.**

Within a module: **controller** (implements the generated interface) → **service**
(logic, transactions) → **repository** (jOOQ). Records for domain objects. Details in
[`server.md`](server.md).

## The client's layers

MVVM, with feature folders that mirror the server's modules. Dependencies point
downwards only, and the analyzer rule `layer_boundaries` checks every import:

```
view/                 widgets: watch one ViewModel, call its commands     View
*_view_model.dart     one per screen or component: state and commands    ViewModel
lib/data/<area>/      repositories and stores, plain Dart                Model
lib/domain/<area>/    domain models and pure rules
core/api, db, sync, storage, platform                                    services
```

Details, rules and pitfalls in [`app.md`](app.md).

## The data model

Field names in `snake_case` (database); in the API and the client `camelCase`, mapped
mechanically. All synced tables carry the [standard columns](#columns-every-synced-item-has).

### platform and identity

| Table | Notes |
| --- | --- |
| `instance_setting` | key → value: family name and time zone, key prefixes, retention, backup schedule, … (`SettingKey`). A free key–value table so a setting needs no migration. |
| `change_sequence` | one row, the counter |
| `entity_key_counter` | per keyed type, the next number |
| `member` | `username` (unique, lower case), `display_name`, `password_hash` (Argon2id), `must_change_password`, `is_admin`, `color_token`, `disabled_at`, … |
| `group`, `group_member` | groups carry no role and no permission. Setup creates "Everyone" (every new member joins it) and "Parents". |
| `device` | one per signed-in installation: `token_hash`, `last_seen_at`, `last_sync_seq`, `pending_count`, `revoked_at` |
| `invitation` | `code_hash` (salted Argon2id; the code is shown once), the prefilled name, the groups, the expiry (1 hour, 24 hours, 7 days) |

**Readable keys.** Tasks (`TD-14`), events (`EVT-1`), pages (`WIKI-3`), recipes
(`REC-12`) and lists (`LST-3`) get a number **on their first arrival at the server**, from
`entity_key_counter` in the caller's transaction. The key is a nullable label on five
tables, never a foreign key; the UUID is the identity. It cannot be the other way round:
an item created offline needs its identity before any counter can be reached, and
"have a look at TD-14" is something you can say on the phone. Imported events get no
key. A changed prefix applies to what is created afterwards; old numbers stay valid.

### access and sync

| Table | Notes |
| --- | --- |
| `share` | `item_type`, `item_id`, `subject_type` (`MEMBER`, `GROUP`), `subject_id`, `level` |
| `effective_access` | the materialised resolution (above) |
| `change_log` | `seq`, entity, container, `op`, `fields`, `changed_fields`, actor member and device, `recorded_at`. `changed_fields` and the actor make the history possible without diffing. |
| `processed_mutation` | `mutation_id` → result and response, kept as long as the log |

The **history** of an item has no table: it is read from `change_log`, filtered through
`effective_access`, and turned into lines ("Ben ticked this off") by the client. It
reaches back as far as the log does, and says so.

### Items

| Table | Notes |
| --- | --- |
| `tag` | an item of its own, with owner and sharing. Items carry their tags as `tags uuid[]`; a tag the member cannot see is not shown on items either. |
| `link` | references, **parsed from text**, never kept by hand. Two notations: `#TD-14` (typed) and `[Title](hiwiski://todo/<uuid>)` (inserted by the link picker; works before an item has a number). Both resolve to the UUID and render as a chip with the target's current title. A target the reader cannot see is left out entirely. |
| `comment` | flat, on any item (`item_type`, `item_id`, `body`); whoever may read may comment |
| `todo_list` | `name`, `description`, `kind` (`STANDARD`, `SHOPPING`, `KANBAN`), `color_token`, `position`, `columns` (Kanban), archive fields |
| `todo` | `title`, `description`, `status` (`OPEN`, `DONE`), `due_date`, `due_time`, `rrule`, `assignees` (members and groups), `position`; shopping: `amount`, `unit`, `product_id`; Kanban: `column_id` |
| `todo_occurrence` | the ticked-off or skipped dates of a recurring task; merged on sync |
| `list_order` | a member's own order of the lists, one item per member, shared with no one |
| `calendar` | `kind` (`LOCAL`, `EXTERNAL` for a subscription, `IMPORTED` for a file import — both read-only), `tags` and `default_reminder_minutes` that apply to all its events |
| `event` | three time forms (below), `rrule`, `exceptions` (keyed by the original start, merged on sync), `attendees`, reminders, `source_uid`/`source_recurrence_id` for imports |
| `calendar_subscription` | an ICS address fetched on an interval into an `EXTERNAL` calendar (or into a task list); matched by `UID` + `RECURRENCE-ID`, never by title. Title and time belong to the source; tags, assignment, reminder and completion to the family. |
| `calendar_feed` | an export: calendars, `FULL` or `BUSY`, a token in plaintext (so the address can be shown again; it can only read) |
| `wiki_page` | `parent_id` (any depth; `null` is a root), `position`, `kind`, `title`, `content` (Markdown), `tags`, `properties` (what the kind adds), archive fields |
| `wiki_revision` | REST only; `kind` `SAVE` or `CONFLICT` |
| `pinboard_node`, `pinboard_edge` | a pinboard's elements and the connections between them, items of their own in their page (`page_id`, the container whose share they inherit), so that each field of each element has its own conflict; they go and come back with their page and have no entry of their own in the trash. An element: `kind` (`PLAIN`, `NOTE`, `IMAGE`, `LINK`, `MEMBER`, `DRAWING` — one stroke drawn by hand), `x`, `y`, `width`, `height`, `layer` (a fraction, so a step up or down writes one element), `text` (a picture element's picture as a Markdown image, as in a page's text), `target` (a link element's item; a member element's member as `hiwiski://member/<id>`, which is no link of the page), `link_view` (`TITLE` or `CONTENT`), `color`, `shape`, `text_size`, `text_color`, `points` and `stroke_width` (a stroke's points across its element, so it scales with it, and its thickness; a stroke's `shape` names what it was drawn as — `RECTANGLE`, `ELLIPSE`, `TRIANGLE`, `DIAMOND`, `LINE`, `ARROW` — and makes it resizable, empty: freehand), `rotation` (whole degrees 0–359 clockwise about the centre; connections still meet the unturned outline), `text_align` (where a note's text stands: `TOP_LEFT` … `CENTER` … `BOTTOM_RIGHT`, nine in all; empty: top left), `text_flow` (what a note's lines fill: `BOX`, the largest box inside its shape, or `SHAPE`, the shape itself, each line as wide as the shape at its height; empty: `BOX`). `text_size` is `S`, `M`, `L`, `XL` or a size of its own in logical pixels (`"18"`, 4 to 400). A connection: `from_id`, `to_id`, `text`, `color`, `stroke_width`, `line` (`SOLID`, `DASHED`, `DOTTED`) and `arrows` (`NONE`, `END`, `START`, `BOTH`) — names in capitals, an unknown one drawn plain; both ends living elements of its page, checked on every write. |
| `board`, `widget` | one start board and one dashboard per member, created on first open; `layout` `FLOW` or `GRID`; the dashboard's `token`. A widget kind the app does not know shows a placeholder. |
| `product`, `aisle` | the shopping list's catalog and categories — the only domain data **without an owner**, shared by the family. Built-in categories have a `key`, own ones a `name`; built-in ones are hidden, never deleted. Over REST, not sync. |
| `media` | images: owner, content type, size, dimensions, `sha256` (stored once), and the item they are attached to. The bytes are files under `HIWISKI_MEDIA_PATH`. |

**Event times** are three field groups, not one column, because each stores something
else:

| `time_form` | Fields | Why |
| --- | --- | --- |
| `TIMED` | `starts_at`, `ends_at` (`timestamptz`) | a point in time |
| `ALL_DAY` | `start_date`, `end_date` (`date`) | 1 January is not 23:00 the day before in Portugal |
| `RECURRING` | `local_start`, `local_end` (local date-time text), `time_zone` | "every Monday 8:00" computed in UTC moves to 9:00 when the clocks change |

**Kanban.** A board's columns are one synced field on the list, replaced as a whole:
2–8 columns, each with an id, a name, a color and a `done` flag; at least one done and
one open column. Where a card stands is **derived**, so status and column never
contradict each other: a done card stands in its column if that is a done column,
otherwise in the first done column; an open card likewise among the open columns. A list
becomes a board once (`STANDARD` → `KANBAN`), and a card cannot repeat.

**Images** belong to an item and have no sharing of their own: whoever sees the item
sees its images. An upload always names its item; an image attached to nothing is
removed by the weekly cleanup. Two sizes — the original, with its metadata (EXIF, GPS,
…) stripped on upload, and a preview (longest edge 640). Limits: 100 megapixels, a quota
per member, a cap on parallel uploads.

An image added to a text in the editor is **kept on the device first**, under the id
the text points to, and uploaded under that id after the sync, once its item has no
change waiting in the outbox (`MediaRepository.carryOver`). Like the text, it can be
added offline, and saving before an upload would have finished loses nothing. Picked
photos still take a moment to be read in (on an iPhone they are converted first):
meanwhile "Save" is greyed out (`MarkdownTextController.addingImagesAnywhere`), and
every save of a text waits for `MarkdownTextController.imagesAdded` as well. Until an
image is up, it counts among the changes waiting, which signing out names. Another
device that shows the text before the upload shows the image as missing until the item
is opened again. A recipe's picture is uploaded at once instead: the server checks that
a field's image exists when the field arrives, while it reads nothing from the images in
a text.

**Colors are tokens** (`BLUE`, `RUST`, `VIOLET`, `GREEN`, `PINK`, `OCHRE`, `TEAL`,
`SLATE`), never color values: the client maps each to a color for the light and the dark
theme. An unknown token falls back to `SLATE`.

**The one exception is a pinboard's `color` and `text_color`**: a token, or a color of
the family's own as `#RRGGBB` — `#RRGGBBAA` where the canvas shows through it. It is content someone chose, not part of the design.
Stored once for both themes, the app adapts it (`core/theme/pinboard_colors.dart`): on an
element's surface it stays as chosen and the text on it is dark or light, whichever reads
better; as a line or a text on the canvas it keeps its hue and changes its tone until it
stands out from the canvas in either theme. A chosen text colour keeps its hue and changes
its tone until it reads on what it stands on.

## Compatibility

- **The contract only grows.** Fields are added and optional; nothing is renamed,
  retyped, made required afterwards or dropped without a deprecation period; enums are
  only extended, and the client survives an unknown value. The build checks this against
  the last published contract ([`api.md`](api.md)).
- **The handshake** (`GET /api/v1/handshake`, no sign-in) names the API version, the
  server version and `minClientVersion`. An app below it says so and offers the update
  instead of failing somewhere.
- **Migrations are forward compatible**: the previous server version must still start
  on the new schema, or a rollback is not one. And **a released migration is never
  edited**, not even a comment: Flyway's checksum would stop every existing server.
- **The client skips what it does not know**: unknown entity types in a pull, unknown
  widget kinds, unknown color tokens, unknown error codes (shown as the code).

## Errors

An error is a **code with parameters**, never a finished sentence:

```json
{ "code": "todo.list_not_found", "params": { "listId": "…" }, "correlationId": "8f3c…" }
```

The client translates the code through its ARB files. HTTP status by meaning: `400`
invalid, `401` not signed in, `403` not allowed, `404` not there **or not visible** (the
same answer — `403` would confirm existence), `409` conflict, `413` too large, `429` too
often. Every request has a correlation id, also in the error, so "error 8f3c" can be
found in the log.

Logs and console output are English, structured, on stdout, and contain ids but never
content or personal data. There is no telemetry; the app keeps its own log locally,
and the member can export it.
