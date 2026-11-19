# Home screen widgets

Four widgets for the home screen of a phone or tablet, on iOS and Android: **upcoming
events**, a **shopping list**, a **task list** and **one column of a Kanban board**. Each
shows what the app is set to on that device (Account → Widgets); a tap opens what it shows,
or its settings while it has none.

They are **native** — SwiftUI with WidgetKit, Kotlin with Glance — not Flutter: the system
asks for a widget's content in a process of its own while the app is closed, and only
native code runs there. A Dart package that hands data to native widgets would still
depend on the app having run lately; these ask the server themselves.

## Two pictures, one schema

A widget has two sources, and both write the same types:

| Source | When | What it has |
| --- | --- | --- |
| **the app** | after every change to its database, debounced (`lib/app/home_widgets.dart`) | everything the device holds, **including changes not yet sent** — and it works without a server |
| **the server** | whenever the system refreshes the widget (`getAgenda`, `getListSummary`) | what others changed while the app was closed |

The app computes its picture from its own database (`domain/home_widgets/home_widget_snapshots.dart`)
into the types generated from the contract — `Agenda` and `ListSummary` — so the widget
reads one format from either side. The server expands events by the same rules as the app
(`EventOccurrences`, checked with the app's `EventExpander` against
[`golden/occurrences.json`](../../golden/occurrences.json)) and derives a Kanban card's
column the same way.

**Which picture is shown** (`choose` in `WidgetChoice.swift` and `WidgetSnapshots.kt`):

- only a picture made for the widget's current settings counts;
- **the app's wins while it still waits to send a change** to what the widget shows — the
  server's answer would show the state before it, and the milk ticked off in the shop
  would come back;
- otherwise the one at the newer **position** (the server's change sequence: the app's
  last pull, the server's position when it answered), and between two at the same position
  the one made later.

## Failures

A refresh that cannot reach the server **keeps the last picture**; on the road the home
server is often out of reach, and that is everyday life, not an error. A picture older
than an hour says how old it is ("As of 14:32"). The agenda drops what is over by itself:
iOS gets timeline entries at every end of an event and at midnight, Android redraws every
quarter of an hour.

Two answers are not failures:

| Answer | The widget |
| --- | --- |
| `401` | the device was signed out — it forgets **everything** (settings, pictures, session) |
| `404` | the list is gone or no longer visible (the same answer for both) — it asks to be set up again |

## How often

| | Refresh by itself | Redrawn by the app |
| --- | --- | --- |
| iOS | when WidgetKit grants it, asked for every 15 minutes (a daily budget, in practice every 15–60 minutes) | at once; from the app in the foreground this costs nothing of the budget |
| Android | WorkManager, every 15 minutes at most, later in Doze | at once |

## Ahead of the app

A widget asks the server itself; the app's reminders come from its local database. So a
widget can show an event somebody else entered **before the app has pulled it** — and
until the app has, no reminder for it exists.

The app closes that gap with its background sync (`app/background_sync*.dart`): for as
long as a member is signed in it pulls every quarter of an hour at best and schedules the
reminders anew. The gap stays as wide as the system makes it: iOS grants the app's runs
at its own discretion and none after a force quit, Android delays them in Doze. Without
"Stay signed in" there is no gap, because the widgets get no token and ask nobody.

## What lives where

The app writes through a method channel (`core/platform/home_widget_bridge.dart` →
`HomeWidgetBridge.swift` / `HomeWidgetBridge.kt`); each key has one writer.

| Key | Written by | iOS | Android |
| --- | --- | --- | --- |
| `config` — which widget shows what | app | App Group `group.de.danielkononov.hiwiski`, `UserDefaults` | `SharedPreferences` `hiwiski_home_widgets` |
| `snapshot.app.<kind>` — the app's picture | app | as above | as above |
| `snapshot.server.<kind>` — the fetched picture | widget | as above | as above |
| `gone.<kind>` — the server answered `404` | widget | as above | as above |
| the server's address and the device token | app | keychain, in the App Group's access group, readable after the first unlock | encrypted with an AES key of the Android keystore |

`<kind>` is `agenda`, `shopping`, `tasks` or `kanban`. The settings document has one entry
per kind that is set up: `{"agenda": {"calendarIds": [], "days": 7}, "shopping":
{"listId": "…"}, "kanban": {"listId": "…", "columnId": "…"}}`; no calendar means all of
them. A picture is `{"source", "savedAt", "pending", "config", "agenda" | "list"}`.

**The session.** The widgets get the device token only if it was stored to stay ("Stay
signed in"): without it the session ends with the app, and so does what the home screen
shows. Signing out, losing access or changing the server clears everything the widgets
hold. Without a server the widgets show the app's pictures and ask nobody.

## The widgets read the API

Everywhere else the client reads only its local database. The widgets are the exception:
they **read** two endpoints and never write — interactive widgets (a tick on the home
screen) would write past the local database and its outbox, and are not offered.

## Links

A tap opens the app with `hiwiski://widget/<address>`, where the address is **one of the
app's own**: Flutter hands the router the link's path, so the router leads there — through
the sign-in first, when nobody is signed in. A link of its own (`/list/<id>`) found no
screen. `home_widgets_test.dart` pins the three addresses; a route that moves breaks a tap on
a widget.

| Link | Opens |
| --- | --- |
| `hiwiski://widget/calendar` | the calendar (`CalendarRoute`) |
| `hiwiski://widget/tasks/list/<listId>` | the list (`TodoListRoute`) |
| `hiwiski://widget/account/home-widgets?kind=<kind>` | Account → Widgets, with that widget's settings open (`HomeWidgetsRoute`) |

## The generated clients

Both widgets call the server with a client generated from the contract, never checked in,
reduced to the two operations and their types:

| Platform | Generator | Run |
| --- | --- | --- |
| Android | openapi-generator (`kotlin`, `jvm-okhttp4`, kotlinx.serialization) | by the Gradle build itself (`openApiGenerate` before `preBuild`) |
| iOS | swift-openapi-generator (`ios/HiwiskiWidgets/openapi-generator-config.yaml`) | `app/tool/generate_widget_client.sh`; the Xcode build stops with a note if the client is missing or older than the contract |

**The widgets' schemas carry no enums.** A generated Swift or Kotlin enum throws on a value
it does not know, where the Dart client maps it to a placeholder; a field that would be an
enum (`kind`, `colorToken`) is a string, and the widget falls back on an unknown one.

## Texts

The widgets' texts are native resources, since they run without the app:
`ios/HiwiskiWidgets/{en,de}.lproj/Localizable.strings` and
`android/app/src/main/res/values{,-de}/strings.xml`. Both languages, as in the ARB files.

## Files

| | |
| --- | --- |
| Contract | `api/paths/calendar.yaml#Agenda`, `api/paths/todo.yaml#ListSummary` |
| Server | `calendar/internal/AgendaService`, `EventOccurrences`; `todo/internal/ListSummaryService`, `TodoController` |
| App | `domain/home_widgets/`, `data/home_widgets/`, `app/home_widgets.dart`, `features/account/home_widgets/` |
| iOS | `ios/HiwiskiWidgets/` (the extension; `WidgetStore.swift` also in the app), `ios/Runner/HomeWidgetBridge.swift` |
| Android | `android/app/src/main/kotlin/…/widgets/`, `res/xml/home_widget_*.xml` |
| Tests | `golden/occurrences.json`; `AgendaIT`, `ListSummaryIT`; `app/test/home_widgets_test.dart`; `WidgetSnapshotsTest.kt`; `ios/RunnerTests` |
