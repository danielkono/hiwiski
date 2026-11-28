# The server

A Spring Boot application in `server/`, one Gradle multi-project:

| Project | Holds |
| --- | --- |
| `:api` | only code generated from `api/openapi.yaml`: Spring interfaces and DTOs. Also the tasks that bundle the contract and check its compatibility ([`api.md`](api.md)). |
| `:db` | the Flyway migrations (`src/main/resources/db/migration`) and the jOOQ classes generated from them |
| `:app` | the application |
| `buildSrc` | the jOOQ code generation task and the contract check (`SpecContractTask`) |

Read [`architecture.md`](architecture.md) first: the data path, sync, sharing and the
module map are explained there.

## Commands

```sh
./gradlew build                      # everything: generation, compile, contract check, all tests
./gradlew build -x test              # without the tests
./gradlew :app:test --tests '*SyncIT'
./gradlew :app:bootRun               # needs the variables, see setup.md
./gradlew :api:updateBundledSpec     # after a change in api/
```

Test results: `server/app/build/test-results/test/*.xml`. Spring Modulith writes the verified
module structure to `server/app/build/spring-modulith-docs` (the `ModularityTest`).

## Generated code

- **jOOQ** — `:db` applies the migrations to a throwaway Postgres (Testcontainers) and
  generates the table classes into `de.danielkononov.hiwiski.db.generated`. A new
  migration is visible in Java after the next build.
- **The contract** — `:api` generates an interface per tag and a DTO per schema into
  `de.danielkononov.hiwiski.api`. A controller `implements` its interface; generated
  code is never edited.

Neither is checked in.

## A module

```
de.danielkononov.hiwiski.<module>/
  SomethingPublic.java        the module's API: interfaces, records, events others use
  internal/
    XController.java          implements the generated interface, maps DTOs
    XService.java             logic and transactions
    XRepository.java          jOOQ queries
    XSyncTypes.java           @Configuration: what the module registers (below)
```

- Nothing outside the root package is visible to other modules. `ModularityTest`
  fails on a reach into another module's `internal`, and on a cycle.
- Domain objects are Java records.
- A controller never contains logic beyond mapping; a service never builds HTTP
  answers. Errors are `HiwiskiException` with a code and parameters — the
  `ErrorAdvice` turns them into the error model (`platform`).
- Modules talk through their public interfaces or through Spring application events
  (`EntityWritten`, `GroupMembersChanged`, `InstanceRestored`, …), recorded by Spring
  Modulith's event publication table so that a listener after the commit is not lost.

### Registering what a module owns

The cross-cutting modules know no domain types. A domain module registers beans:

| Bean | Module | What it says |
| --- | --- | --- |
| `SyncType` | `sync` | the entity type's name, its table, its fields (`SyncField.text/uuid/…`), its properties, its container, its readable key, what a delete takes along, which upserts it refuses |
| `Ownable` (`JooqOwnable`) | `access` | the owner column, the container an item inherits its shares from |
| `Restorable` (`JooqRestorable`) | `admin` | how a deleted item shows in the trash and comes back |
| `Searchable` | `search` | what is indexed and how a hit is shown |
| `LinkSource` | `link` | which field holds text with references, what a target is called |

`tag/internal/TagTypes.java` is the smallest complete example; `todo/internal/` and
`calendar/internal/` are the larger ones.

### Adding a synced entity type

1. **A migration** with the table and the [standard
   columns](architecture.md#columns-every-synced-item-has).
2. **A `SyncType` bean** with every field the client may write. A field not listed is
   not accepted from a push. Fields only some items carry, and that need no query,
   can be properties in a JSONB column instead (`SyncProperty`), as wiki page kinds do
   ([`wiki-page-kinds.md`](wiki-page-kinds.md)).
3. **An `Ownable`** naming the container it inherits from, if any.
4. **A `Restorable`** if it can be deleted by a member.
5. **The schema in the contract** (`api/components/<module>.yaml`, under the sync
   item types) — the client's codec is written against it.
6. **Integration tests**: create, change, conflict, delete, visibility for a member
   without a share.
7. On the client: a Drift table, the codec, a repository — see [`app.md`](app.md).

## Migrations

`server/db/src/main/resources/db/migration/V<NNN>__<what>.sql`.

- **The chain starts at `V036__baseline.sql`**: the schema of 2026.1.9 in one file,
  dumped from a database the 36 migrations before it had built, with the rows they
  seeded. A database from before is taken over at its first start by Flyway's repair
  (`BaselineTakeover`); nothing is run. The next migration is `V037`.
- **A released migration is never edited** — not a statement, not a comment, and
  "released" starts with the first release candidate, whose image is public. Flyway
  checks a checksum on every start; a changed file stops every server that already ran
  it. Fix forward, with a new migration.
- **Forward compatible**: the previous server version must still start on the new
  schema, so that rolling back the image is a rollback. Add columns nullable or with a
  default; drop nothing a released server still reads.
- **One schema change, one migration**, written for an instance with years of data:
  data migrations in SQL, in the same file, set-based.
- A restore runs the migrations on the restored data (below), so a migration must also
  work on an archive's old state, not only on the state of today's databases.

## Tests

- **Unit tests** for pure logic: `*Test.java`.
- **Integration tests** boot the whole application against Postgres in a container:
  `*IT.java`, annotated `@IntegrationTest` (`support/`). Between tests the
  `DatabaseCleaner` empties the tables. `support/Family` sets up members and devices,
  `support/SyncClient` pushes and pulls as a device would.
- **Golden files** (`golden/`) are read by server and app tests alike: recurrence
  expansion, its limits, and the reference parser. A case is added there, once, and must
  pass on both sides.
- `ModularityTest` checks the module boundaries; `DatabaseRoleIT` runs every migration
  as the unprivileged role a real installation uses.
- Security-relevant behaviour has its own tests in `security/` (access rules, identity,
  media, headers), each asserting the secure behaviour.

Write integration tests through the HTTP API wherever possible: they test what a device
sees, including the sharing filter.

## Configuration

`server/app/src/main/resources/application.yaml` maps the `HIWISKI_*` variables to
`hiwiski.*` properties (`platform/internal/HiwiskiProperties`). Every path is set
explicitly; **the server does not start if a required variable is missing**, and names
it (`MissingConfigurationFailureAnalyzer`), nor if the media or backup directory is not
writable. The variables, for operators, are documented in `deploy/.env.example` and on
the website's setup pages.

Instance settings that the administrator changes in the app (family name, time zone,
key prefixes, retention, backup schedule) live in `instance_setting`, not in variables
(`platform/SettingKey`).

## Scheduled jobs

| Job | When | Class |
| --- | --- | --- |
| Trash: delete what is past its retention | daily 03:40 | `admin/internal/TrashService` |
| Change log and processed mutations past retention | daily 03:20 | `sync/internal/RetentionJob` |
| Orphaned images | Sundays 03:50 | `media/internal/OrphanedImagesJob` |
| Calendar subscriptions due | hourly | `calendar/internal/SubscriptionService` |
| Expired invitations | hourly | `identity/internal/InvitationService` |
| Idle sessions (12 hours) and devices (180 days) | hourly | `identity/internal/AuthService` |
| Scheduled backup due, or missed | every 10 minutes | `admin/internal/BackupService`, `ScheduledBackup` |
| Event stream: batch signals, heartbeat | 250 ms, 25 s | `sync/internal/EventStreamController` |

**An error that is recorded belongs in a transaction of its own.** A subscription whose
import fails notes the error on the subscription; if that note ran in the import's
transaction, it would be rolled back with it, and the user would see a server error
instead of a readable state. `SubscriptionStatus` shows the pattern.

**A long write goes in batches.** Every write holds the instance's writer lock until
its transaction ends (`change_sequence`), so one transaction around a calendar of
thousands of events keeps every device from saving for as long as it runs. An import and
a subscription's refresh therefore write 50 events per transaction
(`SubscriptionService`); each event is whole and matched by its UID, so an interrupted
run is continued by the next one, and what has gone from the source is deleted in a last
step, once every event was seen.

## Backup and restore

The `admin` module. An archive is a database dump, the images and a manifest (schema
version, server version, family identity), as **one encrypted file**.

- **Encryption.** At setup the server creates an X25519 key pair; it keeps the public key
  and the private key wrapped with the backup password (`KeySlot`: a memory-hard key
  derivation with its parameters). Every archive is a standard
  [age](https://age-encryption.org) file encrypted to the public key — so scheduled
  backups need no password — behind a fixed-size header of ours (`ArchiveHeader`): a
  magic number and version, two slots for the wrapped private key (a password change
  writes the slot not in use, so a power cut never leaves neither), and what the list
  shows without the password. On restore the manifest *inside* the encrypted payload
  decides, not the header.
- **Where.** `HIWISKI_BACKUP_PATH` (in the container `/data/backup`, a host directory in
  the compose file), checked for writing at start. The newest *n* are kept.
- **When.** On a schedule, on demand, **before an update** (the server keeps the version
  it last ran; started with another one, it backs up first and migrates after — reading
  the tables from the catalog, because the code is already new and the schema still
  old) and before a restore.
- **Restore from any older version** (`StagingRestore`): a staging schema is migrated to
  the archive's schema version, the archive's rows go in, Flyway migrates the staging
  schema to the current version, then one transaction swaps the data into `public`.
  Anything failing before the swap leaves the instance as it was. Then images move in and
  derived data (previews, the search index) is rebuilt.
- **What a restore keeps**: who may sign in (passwords, disabled members, revoked
  devices, current tokens) and the current backup key — an old archive must not bring
  back a revoked phone or an old password. A new instance identifier makes every device
  resync; devices keep aside what they had sent and the restored server no longer has,
  and offer to bring it back.
- A running server restores only **its own family's** archives (`family.id`); another
  family's goes through the setup wizard of a fresh server.

## The served web app

The release pipeline builds the Flutter web app and puts it into the server image
(`server/app/build.gradle.kts`), so a server always serves the web app of its own
version. `platform/internal/WebClientRouting` serves it and answers every path the
app resolves itself with `index.html`.

- **Every file is sent with `no-cache`**: Flutter's files carry no hash in their
  names, so the browser asks on every load whether its copy is still good.
- **That question is answered by the file's content** (an `ETag` from its hash,
  `WebClientEtags`), never by its date. The files in the image carry one fixed date in
  every release; answered by date, a browser kept the web app of the release it had
  loaded first, however often the server was updated.
- **`build.json`** names the served build (a hash of `main.dart.js`). The web app
  compares it with the build it was started as and offers to reload when they differ.

## Security

- **Passwords**: Argon2id. **Device tokens**: random, opaque, stored as a hash,
  revocable — no JWT, because a lost phone must be locked out at once. Invitation codes:
  salted Argon2id, shown once.
- **Sign-in throttling** (`LoginThrottle`) delays, never locks out — a locked-out family
  has no support channel. It counts per username and address, per address, and per
  username across all addresses.
- **No outgoing requests into the local network.** Recipe import and ICS subscriptions
  check the *resolved* address against private, loopback, link-local and metadata
  ranges, before and after every redirect (`platform/OutboundUrls`).
- **Trusted proxies only.** The client address comes from `X-Forwarded-For` only when
  the request comes from a configured proxy (`HIWISKI_TRUSTED_PROXIES`; in the compose
  setup Caddy's fixed address).
- **The database role is no superuser.** The server's role owns the database and
  nothing else; the image's superuser creates it on first start.
- **Limits** on request size, image size and pixels, a storage quota per member,
  parallel uploads, page length — so a bug does not fill the disk.
- Security headers, a strict Content Security Policy for the served web app, no
  caching of API responses (`identity/internal/SecurityHeaders`).
- **The visibility check is part of the query**, never a step after it, and a hidden
  item answers exactly like a missing one.

## Commands in the container

```sh
docker compose exec app hiwiski reset-admin-password
```

The only way to reset the administrator's password: the administrator resets everyone
else's in the app, but has nobody above them. The `hiwiski` script
(`deploy/image/usr/local/bin/hiwiski`) starts the application with
`hiwiski.command=reset-admin-password` (`identity/internal/ResetAdminPasswordCommand`).
