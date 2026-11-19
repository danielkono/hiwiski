# The app

One Flutter project in `app/` for Android, iOS, macOS, Windows, Linux and the web. The
same code is the public demo (a web build without a server) and the app views on the
website (a separate web entry point, `lib/app/scenes/`).

Read [`architecture.md`](architecture.md) first: the client never talks to the API for
synced data — it reads and writes its local database, and the sync engine does the
rest.

## Commands

```sh
flutter pub get
dart run swagger_parser                                   # the API client, from api/
dart run build_runner build --delete-conflicting-outputs  # Drift, Freezed, Riverpod, l10n
dart analyze                                              # not `flutter analyze`
dart format <changed files>
flutter test                                              # or: flutter test test/sync_engine_test.dart
(cd tool/hiwiski_lints && dart test)                      # the project's analyzer rules
```

`build_runner watch` regenerates while you work. Generated files (`*.g.dart`,
`*.freezed.dart`, `lib/core/api/generated/`, `lib/core/l10n/generated/`) are not
checked in and never edited by hand.

**`dart format` is the only formatting** — its defaults, no project style. Format every
Dart file you touch.

## Structure

```
lib/
  main.dart           start: storage, database, the ProviderScope, the app
  app/                composition root: data clients, repositories, stores, router,
                      link index, background sync, the demo, the website's scenes
  features/<module>/<screen>/   screens, one folder each: view/ and a ViewModel
  components/<name>/  building blocks several features embed (item info, sharing,
                      tags, assignees, history, comments, links, avatars, sync banner,
                      export, import)
  data/<area>/        repositories and stores (Model)
  domain/<area>/      domain models and pure rules
  core/
    api/              the generated client, hand-written binary clients, the error model
    db/               the Drift database and its tables
    sync/             outbox, sync engine, entity codec, event stream, local writes
    storage/          preferences, the device token, the image cache
    platform/         notifications, device information, time zone
    common/           shared vocabulary: wire constants, names, date patterns, ids
    routing/          typed routes and internal references (hiwiski://…)
    shell/            the navigation scaffold: tabs, rail, drawer
    ui/               passive building blocks: sheets, dialogs, chips, info bar, states
    theme/            color, typography and measurement tokens
    l10n/             app_en.arb, app_de.arb
test/                 unit and widget tests; test/a11y/ the accessibility suite
integration_test/     on-device tests
tool/hiwiski_lints/   the project's analyzer plugin
```

The feature folders mirror the server's modules: `todo`, `calendar`, `wiki`, `board`,
`search`, `family`, `account`, `admin`, `setup`, …

## Layers

The client is MVVM. **The folder decides the layer**, and the analyzer rule
`layer_boundaries` checks every import:

- **view** — every `view/` folder, `core/ui`, `core/shell`, `core/theme`,
  `core/routing`: widgets. A view watches the ViewModel of its own screen or component
  (the `*_view_model.dart` next to its `view/` folder) and calls its commands; for types
  it may import `lib/domain/` and the generated API models. Never `lib/data/`, a service
  or `lib/app/`; never another screen's ViewModel; no `@riverpod` in a view. `core/ui`,
  `core/theme` and `core/l10n` read no provider at all — they are handed what they show.
- **ViewModel** — `*_view_model.dart`, and in `features/` and `components/` every file
  outside `view/`: `@riverpod` notifiers, `autoDispose`. One per screen or per
  component. It reads the Model through `app/repositories.dart`, `app/stores.dart` and
  `app/link_index.dart`, and imports no other ViewModel. Each ViewModel puts its state
  together itself — no shared helpers that watch, no command mixins; what several share
  are types and pure rules in `domain/` (`domain/todo/list_rules.dart`).
- **model** — `lib/data/<area>/`: repositories and stores, plain Dart (no Riverpod, no
  widgets; clients come in through the constructor). A repository maps Drift rows onto
  domain models; the generated API models pass through as they are. No repository
  imports another area's repository. Shared state (session, preferences, tag filters)
  is a `Store`; REST data several screens share is cached with `Query`
  (`data/query.dart`).
- **domain** — `lib/domain/<area>/`: models and pure rules (filter predicates too).
  Imports only `domain/` and the shared vocabulary.
- **service** — `core/api`, `core/db`, `core/sync`, `core/storage`, `core/platform`.
- **shared vocabulary** — `core/common` and the generated API models: every layer may
  import them.
- **composition root** — `lib/app/` and `main.dart` wire everything together and may
  import anything: data clients in `app/data_providers.dart`, repositories in
  `app/repositories.dart`, stores in `app/stores.dart`, the router in `app/router.dart`.

Nothing under `features/<x>/` imports from `features/<y>/`; only `core/routing` leads
to other features' screens. A building block several features embed is a component in
`lib/components/<name>/` with its own `view/` and ViewModel.

### Names

Checked by `view_model_names`:

- A screen or component folder `x/` holds `x_view_model.dart` with `XViewModel` (state
  `XState`).
- A screen's view is `view/x_screen.dart` with `XScreen`, or `view/x_sheet.dart` with
  `showXSheet`. A component's views are named after what they are (`link_chip.dart`).
- Where the folder name says too little, the feature goes in front: `todo/overview/` →
  `TodoOverviewViewModel`, `TodoOverviewScreen`.
- Every provider class outside `lib/app/` is a `…ViewModel` — there are no controllers
  or notifiers. Repositories are `XRepository` in `x_repository.dart`, stores `XStore`
  in `x_store.dart`.

### Commands

- A view calls its ViewModel where it acts —
  `ref.read(xViewModelProvider.notifier).method()` in the callback, never through a
  local variable — so every call shows which provider it goes to.
- A ViewModel answers through its state: its methods return nothing
  (`view_model_commands`). What the view shows or decides on is in the state.
- A method that changes something and answers with a result (the id it created, what to
  show, whether it fit) is marked `@command` (`core/common/command.dart`). Its
  `Mutation` (`riverpod/experimental`; Riverpod is pinned to 3.4.x) is declared next to
  it in the ViewModel's file, and the view runs the command only through it —
  `xMutation.run(ref, (tsx) => tsx.get(…notifier).command(…))`: awaited when the flow
  goes on with the result, or started with `.ignore()` and shown from
  `ref.watch(xMutation)` (running, error, result) instead of flags of its own.
- A screen that changes something calls a ViewModel command, never
  `ref.read(xRepositoryProvider)`.
- Updates are typed: one named parameter per field, left out means unchanged, and
  `Change(null)` (`domain/common/change.dart`) clears a field that may be empty. Wire
  field maps (`WireFields`) stay inside the repositories.

### Async state

Checked by `async_state`. A ViewModel that loads builds its state in
`Future<XState> build()` (`XState?` when the item can be gone — `null` means "gone",
never "loading"):

```dart
// From the server, decorating: not waited for.
final level = ref.watch(_sharesProvider(id)).value?.myLevel;
// Local: every source watched first, then awaited one by one.
final list = ref.watch(_listProvider(id).future);
final items = ref.watch(_itemsProvider(id).future);
final row = await list;
if (row == null) return null;
return ChecklistState(list: row, items: await items, level: level);
```

- Each source is a **private** stream provider in the ViewModel's file.
- **Local data** (Drift) is awaited. **Data from the server** that only decorates the
  screen (names, the reader's level, counts) is read with `.value` and not waited for —
  offline it may never come. What the screen is *about* is awaited even from the server
  (the trash, the settings, the family): offline the screen says so.
- Watch all sources first, then `await` them one by one — not `.wait` on a record,
  whose `ParallelWaitError` hides the failure.
- The state holds no `loading` flag. The view switches with
  `state.when(skipLoadingOnReload: true, …)`: `HiwiskiPage.loading` / `HiwiskiPage.error`
  for a screen, `LoadingStrip` / `NoticeBar.failure` inside a sheet or component.
  Without `skipLoadingOnReload` every rebuild flashes the loading branch; for the same
  reason a view never reads `isLoading`.
- Parts inside an already loaded screen (a sheet opened from it, a nested section) may
  read `ref.watch(…).value` with a fallback.
- A command that changes the state's own input (`search`, `setServings`) keeps the input
  in a field and calls `ref.invalidateSelf()`.
- `AsyncNotifier` has an `update` of its own: name the command `edit`.

### What the lints cannot check

- **One ViewModel per screen or component**, exposing one immutable state and command
  methods. A screen embeds components without knowing their ViewModels.
- **The view never filters, sorts or groups**, and derives no permission; it shows the
  ViewModel's state. Predicates are pure functions in `domain/`.
- **State shared by several screens or kept across restarts** (filters, session,
  preferences) is Model in `lib/data/`; a ViewModel holds only its own screen's state.
- **Small dialogs** use the commands of the screen that opens them; forms with state of
  their own get a ViewModel.
- **A widget lives in the `view/` folder of the lowest common ancestor** of its users.
- **Items are passed as an `ItemRef`** (`domain/common/item_ref.dart`), never as a type
  string plus an id.

### Riverpod pitfalls

- **Automatic retry is off** (`noRetry` in `app/data_providers.dart`, on every
  `ProviderScope` and `ProviderContainer`, tests included). Riverpod 3 keeps a failed
  provider *loading* for about forty seconds while it retries, and `when` showed the
  loading strip instead of the error.
- `ref.onDispose` inside `build()` fires on every rebuild; hold what must outlive a
  rebuild in a provider of its own (`tagFilterHoldProvider`).
- An `autoDispose` ViewModel that is only `ref.read` is disposed after the call: take its
  dependencies before the first `await`, and watch it from the screen.

## Analysis

`analysis_options.yaml` enables the `many_lints` preset and the project's own plugin
(`tool/hiwiski_lints`). Every enabled rule is a warning, and CI runs `dart analyze --fatal-infos`. Only
`dart analyze` runs plugins.

**No string literals outside named constants** (`no_string_literals`): wire codes, JSON
keys, preference keys, widget keys, routes and SQL go into a `const` (or a top-level /
`static final` where `const` is impossible); UI text goes into the ARB files. Exempt are
messages for developers (exception texts, `assert` messages, log lines, `toString()`),
annotations, enum arguments, strings without a letter, and `test/`.

Where the constants live:

- the sync vocabulary shared with the server (entity types, operations, field names,
  enumerated values): `lib/core/common/wire.dart`
- error codes: `FailureCodes` in `lib/core/api/hiwiski_failure.dart`
- widget keys for tests: `<feature>/view/<feature>_keys.dart`, `core/ui/ui_keys.dart`
- `DateFormat` patterns: `lib/core/common/date_patterns.dart`; RRULE parts:
  `lib/domain/common/rrule_parts.dart`; product name and URI schemes:
  `lib/core/common/app_names.dart`
- anything used in one file only: a private constant in that file

**No raw measurements** (`no_magic_dimensions`): paddings, gaps, widths and heights,
radii, icon sizes, strokes and elevations come from `HiwiskiMetrics`
(`lib/core/theme/hiwiski_metrics.dart`), including private constants and local variables
that only hide a number. A value not on a scale there is rounded to the nearest step or,
for a genuinely new component measurement, added as a named token. Factors stay allowed
(`size / 2`, `2 * HiwiskiMetrics.space32`); exempt are `0`, `lib/core/theme/` and
`test/`.

**Synced rows only through `LocalWrites`** (`synced_writes`): a change made on the
device writes its row and its outbox entry in one transaction, through a `LocalWrite`
(`lib/core/sync/local_writes.dart`) — `create`, `change`, `delete`, and `cascade` for
rows the server changes along with a mutation of the same run. Outside `core/sync/` and
`core/db/` nothing writes a synced table or the outbox with Drift, writes SQL by hand,
calls `Outbox.add` or imports the entity codecs. A row without its outbox entry is never
synced; do not work around the rule with an `ignore`.

**The time through `package:clock`** (`clock_now`): `clock.now()`, never
`DateTime.now()` or `DateTime.timestamp()`. Only `clock.now()` follows the zone, so a
test can fix the day with `withClock`. The store screenshots are golden files
(`test/store/`) and must show the same dates on every run. `test/` is exempt.

**`TODO` comments are warnings.** What comes up goes into an issue.

## Sync on the client

`lib/core/sync/`:

| File | What |
| --- | --- |
| `local_writes.dart` | the only way to change a synced row: the row and its outbox entry, one transaction |
| `outbox.dart` | the queue: entries with their preconditions (chains), held entries, compaction |
| `sync_engine.dart` | a run: push the outbox in batches, then pull; snapshot when there is no position; `resync_required`; when to run |
| `entity_codec.dart` | per entity type, wire fields ↔ Drift rows; only changed fields go out |
| `event_stream*.dart` | the server-sent signal (with a ticket), per platform |
| `left_behind.dart` | after a restore on the server: what this device had and the server no longer has |
| `pending_shares.dart` | shares chosen at creation or changed offline, sent once the server knows the item |
| `local_takeover.dart` | moving the data of "without a server" onto a server |

`app/background_sync*.dart` runs the same sync from a background job (`workmanager`) on
Android and iOS for as long as a member is signed in, and schedules the reminders anew
after it: they come from the local database, and without the job an event somebody else
entered would not remind until the app is opened.

**`baseVersion` comes from the last pull and is never incremented locally.** The codec
sends only the fields a change touched — never the whole row — so an older app does not
blank fields it does not know.

## The local database

Drift, `lib/core/db/`: the tables in `tables.dart`, the database and its migrations in
`hiwiski_database.dart` (`schemaVersion`). On the web the database is in memory
(`connection_web.dart`); `web/sqlite3.wasm` must match the `sqlite3` package version
(`web/README.md`).

**Migrate, never recreate.** A device may hold changes not yet synced; a
`deleteAndRecreate` would lose them. Every schema change gets a step in `onUpgrade` and a
test that migrates from the previous version. Every table that goes through sync has the
standard columns (`id`, `ownerId`, `version`, deleted flag) and a codec entry.

## Navigation

go_router with typed routes (`core/routing/routes.dart`, `app/router.dart`): a typo in a
path is a compile error. Three width classes decide the shell (`core/shell/`): below
600 a tab bar at the bottom and one column; from 600 a navigation rail; from 1024 two
columns, the content and the info bar; from 1200 a collapsible drawer instead of the
rail. The info bar stands beside the content only while the content keeps a reading
width of 480 next to it (`InfoBar.besideContent`, measured by `core/ui/content_width.dart`
in the shell and beside the wiki's tree); otherwise it goes below, as on the phone.
Internal references (`hiwiski://todo/<id>`, `#TD-14`) are resolved in
`core/routing`, the only place that knows every feature's screens.

## Texts and languages

- UI text comes from `lib/core/l10n/app_en.arb` (the template) and `app_de.arb`, through
  the generated class `L` (`L.of(context)`). A new string goes into both files.
- Log lines and exception texts are English and not translated.
- Error codes from the server are translated in one place (the failure model); an
  unknown code is shown as the code.

## The Markdown editor

Pages, descriptions and notes are written in one field, `MarkdownField`
(`components/rich_text/view/`), **formatted** or as **source**. Formatted is not a
second document model: the field's text is the Markdown, character for character, and
only its drawing changes. `MarkdownTextController.buildTextSpan` draws each character
as `domain/wiki/markdown_preview.dart` says — styled, hidden (a tiny transparent glyph,
so offsets stay the text's), or as a widget in place of one character (a bullet, a box,
a quote bar, a chip, an image). Whatever is saved, synced, parsed for links or exported
is therefore exactly what was typed, and the `#` suggestions, the toolbar, Tab and the
list continuation work on the same text in both modes.

Inline markers show, faded, while the cursor touches what they format. A line's prefix
(`## `, `- `, `- [ ] `, `> `) and a chip or an image are one piece: the controller keeps
the cursor out of them (`MarkdownPreview.snap`), and Backspace takes them whole
(`FormattedBackspace`, a formatter because a phone's keyboard sends no key for it).
Which mode a field starts in is a preference of the device (Account → Customize);
switching in the bar applies to that field.

## Recurring patterns

What a member has learnt on one screen has to hold on the next. A new screen takes
these as they are; a screen that needs something else changes the pattern for all.

- **The header of an item** is `PageHeader` (`core/ui/page_header.dart`), at every
  width: the title once, never again in the content; below it the item line in a fixed
  order — the citable key (`entityKey`, the only part in mono), the container as a link
  (`crumbs`), the context (`detail`). The title is one size per width and stands at the
  same place for an area and for what is opened from it: the same margins, the same
  line kept for the kicker. Only a subpage has the item line; an area keeps no room for
  one. The search is shown once per width: in the header below 600, in the navigation
  from there.
- **An item open beside a panel** — a list beside the task lists' rows, a page beside
  the wiki's tree — keeps the area's header above it ("Tasks", "Wiki") and has its own
  under it: the same `PageHeader` inside an `EmbeddedPage`, which then starts at the
  top edge with a smaller title and without avatar and back arrow. The button that
  puts the panel away is the first thing in the row above the panel, and the one that
  brings it back (`PanelReopen`) is the first thing in the item's header — both
  `PanelReopen.inset` from the left and at the same height, so the panel closes and
  opens without moving the pointer.
- **Editing happens on the page.** `EditActions` (`core/ui/edit_actions.dart`) in the
  header's `trailing`: "Edit" turns the page into its fields, and "Cancel" and "Save"
  stand in its place. The fields have no buttons of their own, and no dialog opens over
  an item to change it. A screen whose fields are a widget of their own lets the header
  reach them through that widget's state (`ListEditorState.save`,
  `EventFormState.save`) or reports to the header (`PageActions` in the wiki). The
  pencils in the info bar change one value at once; the content has none.
- **Creating is the floating button** of an area's first screen
  (`HiwiskiPage.floatingActionButton`), labelled with what it creates. It opens a sheet
  (`showHiwiskiSheet`) whose button says "Create" (`actionCreate`); "Save"
  (`actionSave`) is for a change. A header holds no plus. A list of settings — tags,
  categories — creates with a field and "Create" above its rows.
- **One reading width**: lists, forms and an item's page are `listMaxWidth` /
  `contentMaxWidth` wide; only the start screen, a board and the calendar use the
  whole width.
- **A list has one of two forms.** What is ticked off or opened — a task, a shopping
  entry, an event in the calendar's list — is a flat row with a line under it
  (`RowDivider`). What is managed — tags, calendars, categories — stands in one shared
  card with lines between its rows (`RowCard`). No row has a card of its own. At the
  end of a row the order is fixed: a count, the row's actions, then the arrow
  (`RowChevron`) if the row opens a page.
- **A row of the account** is `AccountRow`: label, count, arrow at the edge.

## Design tokens

`lib/core/theme/`: colors for light and dark (`hiwiski_tokens.dart`), the accent colors
behind the color tokens (`hiwiski_accents.dart`), typography (`hiwiski_text_styles.dart`,
`hiwiski_theme.dart`) and measurements (`hiwiski_metrics.dart`). Widgets never use a
color or a size directly.

**Roboto is a variable font.** Every text style sets the weight twice: `fontWeight` for
Flutter's font selection and `fontVariations` for the `wght` axis — without the axis the
text stays at 400 on some platforms, without any error. `test/theme_test.dart` pins it.

**Symbols** are Material Symbols Rounded, shipped as a subset font (`fonts/`). A new
symbol: use `HiwiskiSymbols.<name>`, then `python3 tool/generate_symbols.py`
(`fonts/README.md`).

## Tests

- `test/` — unit and widget tests, against an in-memory Drift database and fake API
  clients. `flutter test --timeout 30s` keeps a hanging test from blocking the run.
- `test/a11y/` — opens every screen and the sheets with data in them, light and dark, on
  phone and tablet, at 200 % text, and checks contrast, tap targets (48) and labels with
  Flutter's guidelines; `states_a11y_test.dart` does the same for empty and offline
  states.
- Golden files from `golden/` are checked here as on the server
  (`recurrence_golden_test.dart`, `link_parse_golden_test.dart`).
- `demo_seed_test.dart` keeps the German and English demo data in step.
- The website's screenshots are rendered by widget tests from the scenes catalog
  (`lib/app/scenes/`), see [`website.md`](website.md).

## Platforms

- **Deep links**: the scheme `hiwiski://` is registered in every platform project
  (Android manifest, iOS and macOS `Info.plist`, Windows and Linux on start).
- **Web**: the token is kept in local storage — there is no keychain outside a secure
  context, and on a home network the app is usually served over plain HTTP.
- **Notifications** are local (reminders scheduled on the device); there is no push and
  none on the web.
- **Home screen widgets** on Android and iOS are native — Glance and WidgetKit — and get
  their settings and the app's picture of their content through a method channel
  ([`home-widgets.md`](home-widgets.md)). The iOS widgets' client is generated with
  `tool/generate_widget_client.sh`; the Android one by the Gradle build.
- **Package id** `de.danielkononov.hiwiski` on every platform.

## Licenses

Every library the apps ship has its license on *Licenses of the packages used*
(*Account → About*). Three sources feed that page:

| What | How it gets there |
| --- | --- |
| Dart packages, and Flutter's engine | Flutter collects their `LICENSE` files by itself. |
| Fonts | `lib/app/font_licenses.dart`, the texts in `fonts/licenses/` ([`fonts/README.md`](../../app/fonts/README.md)). |
| Native libraries: Gradle (the widgets', the plugins' own) and Swift packages | `assets/licenses/native.json` and the texts next to it, `lib/app/native_licenses.dart`. Each platform lists its own. |

**Adding a package of any kind includes its license:**

1. **Its license allows selling the app in the stores.** MIT, BSD, Apache-2.0, ISC,
   zlib, MPL-2.0 (unchanged) and public domain do. GPL, LGPL and AGPL do not: they clash
   with the App Store's terms, and the relinking LGPL asks for cannot be offered on iOS.
   That is also why the Android app needs Android 8 (`minSdk 26`): below it, desugaring
   puts parts of OpenJDK's class library — GPL with the Classpath Exception — into the
   APK. Anything else — a closed-source SDK, Creative Commons, noncommercial terms — is
   asked about first. What a library does counts too: the app makes no third-party calls
   and sends no telemetry (that is why Google's ML Kit went).
2. **A Dart package** needs nothing more — unless it brings native code that is not its
   own: a plugin's Gradle dependencies, a Swift package, a binary a build hook downloads.
3. **A native library** — a Gradle dependency of the app or of a plugin, a Swift
   package — gets an entry in `assets/licenses/native.json`: `name`, `platforms`,
   `covers` (on Android the Maven `group:artifact`, or a prefix ending in `.` or `:`; on
   iOS the package's identity in `Package.resolved`), `license`, and its `notice` where
   it has one. Apache-2.0 asks for the NOTICE to travel with every copy: look for it in
   the AAR or JAR and in the repository. A text several share (`apache-2.0.txt`) is
   there once.
4. **A binary from a build hook** — `sqlite3` downloads SQLite — is seen by no check:
   its entry is written by hand, with `"covers": []`.

What holds it:

- `checkNativeLicenses` in `android/app/build.gradle.kts` runs before every Android
  build and stops it when a module of `releaseRuntimeClasspath` has no entry
  (`io.flutter` excepted: Flutter lists itself).
- Desugaring stays switched on — `flutter_local_notifications` demands it in its AAR
  metadata — but at `minSdk 26` a release takes nothing of `desugar_jdk_libs` along.
  A check after `l8DexDesugarLibRelease` stops the release build should that change.
- `test/native_licenses_test.dart` does what `checkNativeLicenses` does for the Swift
  packages in the iOS and macOS `Package.resolved`, refuses CocoaPods (whose pods it
  does not read), and checks that every text named is there.

When a library is updated, its NOTICE may change: take it from the new release.
