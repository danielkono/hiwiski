# Hiwiski

A self-hosted family app: Flutter client (`app/`), Spring Boot server (`server/`), one
OpenAPI contract (`api/`) both are generated from. Read `docs/development/architecture.md`
before changing behaviour; the guides for each side are next to it.

## Language

**The language of this project is English** — regardless of the language a prompt is
written in. That covers everything written into the repository: identifiers, comments,
log and error messages, test names, documentation, the OpenAPI descriptions, commit
messages and pull request descriptions.

Exceptions:

- German UI strings live in `app/lib/core/l10n/app_de.arb` and stay German there, as do
  the website's German pages in `site/content/de/` and `site/i18n/de.toml`. File names,
  front matter keys and comments there are English.
- The native home screen widgets run without the app, so their German texts live in
  `app/ios/HiwiskiWidgets/de.lproj/Localizable.strings` and
  `app/android/app/src/main/res/values-de/strings.xml` (`docs/development/home-widgets.md`).
- Test data that exercises German input (the ingredient parser, German link syntax, the
  German demo data) stays German — it is data, not prose.

## Comments

A comment says **why**, in place, in full sentences — the reason must be readable
without any other document. Link to the documentation in `docs/` where it explains the
bigger picture; never to anything outside the repository.

## Rules that are easy to break

- **The contract is the source.** Change `api/`, then `./gradlew :api:updateBundledSpec`
  in `server/`, then regenerate the client (`dart run swagger_parser`, `build_runner`;
  for the iOS widgets `app/tool/generate_widget_client.sh`).
  Fields are only added and optional; enums only grow; nothing is renamed
  (`docs/development/api.md`).
- **A released Flyway migration is never edited**, not even a comment: its checksum
  would stop every existing server. Fix forward with a new migration, and keep it
  forward compatible (the previous server must still start on the new schema).
- **The client never writes synced data past the local database.** Every change goes
  through `LocalWrites` (row and outbox entry in one transaction); only changed fields
  are sent; `baseVersion` is never incremented locally.
- **Visibility is part of the query** on the server (`effective_access`), never a check
  after it. A hidden item answers exactly like a missing one (`404`, or `applied` for a
  delete).
- **Errors are codes with parameters**, translated by the client. Logs are English and
  never contain content or personal data.
- **Tests run against Postgres** (Testcontainers), never an in-memory database.
- **Generated code is not checked in** and never edited by hand.
- **Every library the apps ship has its license on the licenses page.** A new package —
  Dart, Gradle or Swift — first needs a license that allows selling the app in the
  stores (no GPL, LGPL or AGPL; a closed-source SDK only after asking); a native one also
  gets its entry in `app/assets/licenses/native.json`, or the Android build and
  `test/native_licenses_test.dart` refuse it (`docs/development/app.md`, "Licenses").

## Commands

```sh
cd server && ./gradlew build                 # all server tests; needs Docker
cd app && dart analyze && flutter test       # `dart analyze`, not `flutter analyze`
dart format <changed files>                  # the only formatting for Dart
```

Environment, versions and local setup: `docs/development/setup.md`. The app's own rules
(layers, ViewModels, analyzer plugins) are in `app/CLAUDE.md` and
`docs/development/app.md`.

## Before a merge into `main`

**Nothing is merged into `main` before every check CI runs has passed locally** — all of
them, on the whole project, not only on the files that changed:

```sh
cd app && dart analyze --fatal-infos && flutter test   # from app/, over the whole app
cd server && ./gradlew build                           # every server test
tool/site_translations.sh && tool/check_references.sh  # from the repository root
tool/store_metadata.py                                 # the store texts' limits
tool/store_shots.sh                                    # the store pictures (goldens, Linux in Docker)
cd site && hugo --panicOnWarning
cd app && flutter build apk --debug && (cd android && ./gradlew :app:testDebugUnitTest)  # the Android widgets
cd app && tool/generate_widget_client.sh && flutter build ios --simulator --debug        # the iOS widgets
cd app/ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=<iPhone>' CODE_SIGNING_ALLOWED=NO
```

- `dart analyze` runs from `app/` with no path: given a folder, it reported none of
  what the project's analyzer plugins found.
- A side the branch did not touch may skip its suite (no server change, no
  `./gradlew build`; no change under `app/android/` or `app/ios/` and none to the
  widgets' contract, no native build); `check_references.sh` always runs. `store_shots.sh` runs for
  every change to the app: on a Mac `flutter test` skips the store pictures' goldens,
  CI does not.
- A failing check is fixed before the merge, not after it. A test that fails only
  sometimes is reported, not retried until it passes.

## Branches and the changelog

Branches are `feat/…`, `fix/…`, `refactor/…`, `chore/…`, `ci/…`, `docs/…`. Every
`feat/…` and `fix/…` branch adds its entry under `## Unreleased` in `CHANGELOG.md`,
written for a family's administrator, with *Upgrade notes* when an update needs anything
done. CI checks it on `main`.
