# Releasing

How a version comes about, what it produces, and where it goes.

| What | Where it goes | Built by |
| --- | --- | --- |
| Server image, with the web app inside | `ghcr.io/danielkono/hiwiski:<version>` (amd64, arm64) | `release.yml` |
| Demo image (the web app without a server) | `ghcr.io/danielkono/hiwiski-demo:<version>` | `release.yml` |
| Website image | `ghcr.io/danielkono/hiwiski-site:<version>` ([`development/website.md`](development/website.md)) | `release.yml` |
| Android app | Google Play, internal test track | `release.yml` |
| iOS app | TestFlight | `release.yml` |
| Store listings | App Store and Google Play: texts, release notes, pictures | `release.yml` on a tag, or `fastlane metadata` ([`development/store.md`](development/store.md)) |
| Setup files and release notes | the GitHub release: `docker-compose.yml`, `Caddyfile`, `env.example`, the version's section of `CHANGELOG.md` | `release.yml`, release tags only, once both apps are uploaded |

The web app is part of the server image: a change to the web app is a new server image.
Server, web app and apps always carry the same version. They do not need each other's
exact version — the handshake (`apiVersion`, `minClientVersion`) and the additive-only
contract keep older and newer combinations working — but one version says at once what
belongs together.

## Versions

**The tags are the only place a version is kept.** Neither `server/gradle.properties`
nor `app/pubspec.yaml` holds one; `tool/version.sh` reads it from the tags, and CI and
both fastlane lanes call it.

Calendar versions: `<year>.<minor>.<patch>`, e.g. `2026.1.0`. Two kinds of tag:

| Tag | Meaning | Starts a release |
| --- | --- | --- |
| `v2026.1.1` | **Release tag.** This commit is version 2026.1.1. | yes |
| `v2026.2.0-dev` | **Dev tag.** From here on, work goes towards 2026.2.0. | no |

| Checked out | `tool/version.sh` | `tool/version.sh --numeric` (iOS) |
| --- | --- | --- |
| the commit of `v2026.1.1` | `2026.1.1` | `2026.1.1` |
| 3 commits after `v2026.2.0-dev` | `2026.2.0-dev.3.gabc1234` | `2026.2.0` |
| no dev tag before the commit | error | error |
| latest release newer than or equal to the latest dev tag | error: set the next dev tag | error |

A release tag wins over a dev tag on the same commit. The last row is the safety net:
without a fresh dev tag after a release, the next intermediate build would carry the
released version again, and App Store Connect refuses builds of a version that is
already live.

**Why a dev tag:** Apple takes only versions of three numbers and, once a version is
released, no further builds of it. Between two releases TestFlight builds therefore need
the *next* version: with `v2026.2.0-dev` they go up as 2026.2.0 (1), (2), (3) …, and the
release `v2026.2.0` is simply the next build of that version. Server and Android get
`2026.2.0-dev.<commits>.g<sha>`, which names its commit and sorts before 2026.2.0.

Rules:

- **Set the next dev tag right after every release.** It may sit on the same commit.
- **Never move or delete a pushed tag.** A moved tag is one version with two contents.
- **Tags are pushed explicitly**: `git push` does not take them along.

## Making a release

```sh
tool/changelog.sh release 2026.1.1        # "Unreleased" becomes 2026.1.1 in CHANGELOG.md
(cd server && ./gradlew :api:acceptSpecBaseline)   # the contract as published
git commit -am "chore: Release 2026.1.1"
git tag v2026.1.1                          # on that commit, after CI passed for it
git tag v2026.2.0-dev                      # where the next version begins
git push origin main v2026.1.1 v2026.2.0-dev
```

- Every `feat/…` and `fix/…` branch has added its entry to `CHANGELOG.md` (CI checks it
  on `main`); the release turns them into the version's notes. *Upgrade notes* there are
  what an administrator reads before updating — write them for that reader.
- `acceptSpecBaseline` writes `api/openapi.baseline.yaml`: from now on every build checks
  that the contract stays compatible with what this version published
  ([`development/api.md`](development/api.md)). It moves only here.
- **Migrations are frozen from here.** A migration that a released version ran is never
  edited again.

The release tag starts `release.yml`: the three images, Android to the internal track,
iOS to TestFlight, and the GitHub release with the setup files and the notes. The
product comes as one: the GitHub release waits for both apps, and a failed upload stops
it -- run the failed jobs again.

Promoting the builds beyond testing (Play production, App Store review) happens in the
store consoles.

If the secrets `DEPLOY_REPO` and `DEPLOY_TOKEN` are set, the release's last job asks
the workflow `deploy.yml` in that repository to deploy the version (`gh workflow run …
-f version=<version>`). Both are secrets, so neither the repository nor the token shows
in the public log. Without them the job says there is nothing to deploy to and ends
green; a fork releases without deploying anywhere.

## Intermediate builds

| Build | How |
| --- | --- |
| Server image, demo, website, Android and/or iOS | GitHub → Actions → Release → **Run workflow**, tick what to build |

Nothing builds on a push to `main`: every release run is one somebody started, which
keeps Actions minutes and the test devices' updates in check -- the iOS job runs on macOS,
whose minutes count ten times while the repository is private.

**Build numbers** are not kept in the repository: every build of a run -- web app,
Android, iOS -- carries the run's number plus a fixed offset, so one build is found on
every platform by it ("2026.1.1 (57)" under *About*). The stores take each number once
and only rising, which holds as long as every upload goes through the workflow: the
lanes take the number as `build:` and do not run without it. The offset, in the
workflow's job *Version*, lifts the run number above the builds the stores received
before this repository began; it may grow, never shrink. To repeat a failed upload, run the
failed jobs again, which keeps the number -- running the whole workflow again would
offer the store that already has the build the same number once more. A number that
was built but not uploaded stays a gap in the stores.

## Signing and store credentials

Store uploads need the maintainer's signing keys and store accounts. Nothing secret is
in the repository; the lanes read it from files outside it:

| File (default) | Override | What |
| --- | --- | --- |
| `app/android/key.properties` (git-ignored) | — | `storeFile`, `storePassword`, `keyAlias`, `keyPassword` of the Android upload key |
| `~/.config/hiwiski/play-service-account.json` | `HIWISKI_PLAY_KEY` | the Google Play service account's key |
| `~/.config/hiwiski/app-store-connect.json` | `HIWISKI_APP_STORE_KEY` | `{ "key_id", "issuer_id", "key_filepath" }` of an App Store Connect API key |

iOS signs the store build manually with an App Store distribution certificate and one
profile per bundle -- the app `de.danielkononov.hiwiski` and its home screen widgets
`de.danielkononov.hiwiski.widgets`, both with the App Group
`group.de.danielkononov.hiwiski` -- kept by [match](https://docs.fastlane.tools/actions/match/), encrypted with
`MATCH_PASSWORD` in the branch `signing` of a private repository named by
`MATCH_GIT_URL` (`app/ios/fastlane/Matchfile`). `fastlane beta` only reads them -- no
Apple ID in Xcode is needed -- and `fastlane match appstore` creates them, once a year.
The manual signing is switched on only for that build (`ios/Flutter/Release.xcconfig`):
a Release build for a device keeps Xcode's automatic signing. In CI the
Android job reads `ANDROID_UPLOAD_KEYSTORE` (base64), `ANDROID_UPLOAD_KEYSTORE_PASSWORD`,
`ANDROID_UPLOAD_KEY_ALIAS`, `ANDROID_UPLOAD_KEY_PASSWORD` and
`PLAY_SERVICE_ACCOUNT_JSON` from the environment `play`; the iOS job reads
`MATCH_GIT_URL`, `MATCH_PASSWORD`, `MATCH_DEPLOY_KEY` (an SSH key with read access to the
match repository), `APP_STORE_CONNECT_KEY` (the `.p8`), `APP_STORE_CONNECT_KEY_ID` and
`APP_STORE_CONNECT_ISSUER_ID` from the environment `apple`. Both admit only release tags
and `main`. The workflow writes them only to files in the runner's temp folder, never
to the log, and never runs for a pull request. fastlane and every gem under it are
installed as `app/Gemfile.lock` names them, checksums included, and run with
`bundle exec fastlane …` -- the lanes hold these keys, so none of their code is
whatever was newest that day.

**A new capability needs new profiles.** The App Group is registered in the developer
account (Certificates, Identifiers & Profiles → Identifiers → App Groups) and switched on
for both App IDs; `fastlane match appstore --force` (not read-only, once, on the
maintainer's Mac) then makes both profiles anew with it. Until then `fastlane beta` stops
at `match(readonly: true)`.

A build for your own device needs none of this: `flutter run --release`, or
`flutter build apk` / `flutter build ios` with your own signing.

fastlane locally comes from Homebrew; CI installs the version pinned in `release.yml`.
Keep the two the same.

## Troubleshooting

| Message | Cause |
| --- | --- |
| `no dev tag (v<version>-dev) before this commit` | No dev tag yet, or the tags were not fetched (`git fetch --tags`). |
| `v… is released, but the latest dev tag is …` | The dev tag after the last release is missing: `git tag v<next>-dev`. |
| `Tag … is not a release tag` | A tag `v…` was pushed that is neither `vX.Y.Z` nor a dev tag. |
| Play: `The caller does not have permission` | The service account is not invited in the Play Console, or the permission has not arrived yet. |
| Play: `Only releases with status draft may be created on draft app` | The app was never rolled out: `fastlane internal status:draft`, then roll out in the console. |
| Play: `The caller does not have permission` at *Validating all changes*, in `fastlane metadata` | The app has never been published (a draft app): the service account needs *Edit and delete draft apps* as well as *Manage store presence*. |
| `App Store Connect API key JSON is missing field(s): key` | The file was given as `api_key_path`; the lane reads the format above itself. |
| `android/key.properties is missing` | No upload key on this machine. |
| The Android job is cancelled at its time limit, silent after the native builds | The runner (8 GB in a private repository) ran out of memory and swapped. The `memory:` lines in the log show it; the step *Gradle memory* in `release.yml` sets the build's heap. |
