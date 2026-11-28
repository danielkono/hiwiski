# Releasing

How a version comes about, what it produces, and where it goes.

| What | Where it goes | Built by |
| --- | --- | --- |
| Server image, with the web app inside | `ghcr.io/danielkono/hiwiski:<version>` (amd64, arm64) | `release.yml` |
| Demo image (the web app without a server) | `ghcr.io/danielkono/hiwiski-demo:<version>` | `release.yml` |
| Website image | `ghcr.io/danielkono/hiwiski-site:<version>` ([`development/website.md`](development/website.md)) | `release.yml` |
| Android app | Google Play, internal test track; a candidate or a release also to the public tests | `release.yml` |
| iOS app | TestFlight; a candidate or a release also to the public tests | `release.yml` |
| Store listings | App Store and Google Play: texts, release notes, pictures | `release.yml` on a release tag, or `fastlane metadata` ([`development/store.md`](development/store.md)) |
| Setup files and release notes | the GitHub release: `docker-compose.yml`, `Caddyfile`, `env.example`, the version's section of `CHANGELOG.md`; a pre-release for a candidate | `release.yml`, on a tag, once both apps are uploaded |

The web app is part of the server image: a change to the web app is a new server image.
Server, web app and apps always carry the same version. They do not need each other's
exact version — the handshake (`apiVersion`, `minClientVersion`) and the additive-only
contract keep older and newer combinations working — but one version says at once what
belongs together.

## Versions

**The tags are the only place a version is kept.** Neither `server/gradle.properties`
nor `app/pubspec.yaml` holds one; `tool/version.sh` reads it from the tags, and CI and
both fastlane lanes call it.

Calendar versions: `<year>.<minor>.<patch>`, e.g. `2026.1.0`. Three kinds of tag:

| Tag | Meaning | Starts a build |
| --- | --- | --- |
| `v2026.2.0` | **Release tag.** This commit is version 2026.2.0. | the release |
| `v2026.2.0-rc.1` | **Release candidate tag.** This commit is the first candidate for 2026.2.0. | the candidate's |
| `v2026.2.0-dev` | **Dev tag.** From here on, work goes towards 2026.2.0. | no |

| Checked out | `tool/version.sh` | `tool/version.sh --numeric` (iOS) |
| --- | --- | --- |
| the commit of `v2026.2.0` | `2026.2.0` | `2026.2.0` |
| the commit of `v2026.2.0-rc.2` | `2026.2.0-rc.2` | `2026.2.0` |
| 3 commits after `v2026.2.0-rc.2` | `2026.2.0-rc.2.3.gabc1234` | `2026.2.0` |
| 3 commits after `v2026.3.0-dev` | `2026.3.0-dev.3.gabc1234` | `2026.3.0` |
| no dev or candidate tag before the commit | error | error |
| latest release newer than or equal to that tag | error: set the next dev tag | error |

A release tag on the commit wins. Otherwise the **highest** dev or candidate tag in the
commit's history counts, not the nearest: `main` takes in every release branch with its
candidate tags, and those can be fewer commits away than `main`'s own dev tag. Of the
same version, the candidate outranks the dev tag. The versions sort as they should:
`2026.2.0-dev.5…` < `2026.2.0-rc.1` < `2026.2.0-rc.1.3…` < `2026.2.0-rc.2` < `2026.2.0`.

**Why a dev tag:** Apple takes only versions of three numbers and, once a version is
released, no further builds of it. Between two releases TestFlight builds therefore need
the *next* version: with `v2026.2.0-dev` they go up as 2026.2.0 (1), (2), (3) …, the
candidates as further builds of it, and the release `v2026.2.0` is simply the next
build of that version. Server and Android get the full version, which names its commit
or candidate and sorts before 2026.2.0. The last row of the table is the safety net:
without a newer tag after a release, the next build would carry the released version
again, and App Store Connect refuses builds of a version that is already live.

Rules:

- **`tool/release.sh` sets the dev tags** (below): the version's own on its release
  branch, the next one on `main`.
- **Never move or delete a pushed tag.** A moved tag is one version with two contents.
- **Tags are pushed explicitly**: `git push` does not take them along.

## Release branches and candidates

Every version is tested as a **release candidate** before it is released. A candidate
is built and published like a release, for testers: the apps in the public tests'
preview groups, the server image for anyone who wants to try it, and the preview's demo.

```
main ──●──●──M (v2026.3.0-dev) ──●──●──────M2──
           \  /                           /
  release/2026.2.0 ● rc.1 ── fix ── ● rc.2 ── ● v2026.2.0
```

**The branch decides the version.** `release/<version>` starts the candidates of that
version:

- **The version `main` works towards, or any above it,** starts from `main`. `main`'s
  dev tag says which version that is — `v2026.2.0-dev`, say, for `2026.2.0`; above it
  is a jump to `2026.3.0` or `2027.1.0`. `main` then goes on towards the next minor
  version, `2026.3.0`, so that the patch numbers after the candidate stay free for its
  fixes. A patch number works as well: `2026.1.16` from `main` at `v2026.1.16-dev`
  moves `main` on to `2026.2.0`.
- **A fix of a release** — a patch number below the version `main` works towards,
  `2026.2.1` — starts from the release before it, `v2026.2.0`, so that nothing of `main`
  comes along.

On the branch go **fixes only**: `fix/…` branches from the release branch, merged back
into it. The release branch is merged into `main` at every step, `main` never into it.
`tool/release.sh` does the git part and pushes nothing; each step says what to push.

```sh
tool/release.sh candidate 2026.2.0   # release/2026.2.0 from main; main → v2026.3.0-dev
tool/release.sh candidate 2026.2.1   # a fix: release/2026.2.1 from v2026.2.0
# push what it names; once CI passed for the release branch:
tool/release.sh rc                   # v2026.2.0-rc.1 on the branch, merged into main
# fixes on the branch, then the next candidate:
tool/release.sh rc                   # v2026.2.0-rc.2
# when the version is good -- the maintainer decides:
tool/release.sh final                # the release's commit on the branch, merged into main
git tag v2026.2.0 release/2026.2.0   # once CI passed for that commit
```

- `candidate` turns `## Unreleased` into `## 2026.2.0 — Release candidate {#2026.2.0}`
  (`tool/changelog.sh candidate`; for a fix the section starts empty), moves the
  contract's baseline, sets the dev tags, and for a version from `main` merges the
  branch into `main` at once, with `main`'s next dev tag on that merge.
- `rc` tags the commit checked out as the next candidate; a candidate whose section in
  the changelog says nothing is refused.
- `final` is allowed only on the last candidate's commit, so that the release is what
  was tested. It gives the section its date (`tool/changelog.sh release`) and moves the
  baseline once more, for what the fixes added.
- **Merging into `main`**: `CHANGELOG.md` conflicts there whenever `main` has new
  entries above the candidate's section. The script resolves exactly that — the
  version's section from the branch, everything else from `main`
  (`tool/changelog.sh take`) — and keeps `main`'s baseline when a patch and a newer
  candidate both moved it. Any other conflict stops it, to be resolved by hand.

**On the release branch the changelog entries go into the candidate's section,** not
under `Unreleased`, which on `main` is already the version after. A fix for something
only the candidate had — a bug in a feature that is new in it — changes that feature's
entry instead of adding a *Fixed* line: the released version never had the bug. CI runs
on every push to `release/…` and checks there, too, that each `feat/…` and `fix/…`
merged into it touched the changelog.

**Frozen from the first candidate:** its server image is public and runs on real data.

- **A migration a candidate shipped is never edited**, as for a release — a fix is a new
  migration. And the previous release's server still starts on the candidate's schema,
  which is what lets a tester go back.
- **The contract's baseline** moved with the branch (`acceptSpecBaseline`): every build
  checks against what the candidate published ([`development/api.md`](development/api.md)).

### What a candidate tag builds

The same as a release tag, with these differences:

| | Release tag | Candidate tag |
| --- | --- | --- |
| Images, Android, iOS | built and uploaded | the same, as `<version>-rc.<n>` (iOS: the version's next build) |
| GitHub release | the release | a pre-release: GitHub's *Latest* stays with the released version |
| Store listings | uploaded | not touched: they belong to the released version |
| Website | built from the tag | the latest release's pages, with the candidate's `CHANGELOG.md` and roadmap ([`development/website.md`](development/website.md)) |
| Deploy | `all` | `candidate`: the preview, the review instance and the website |

The review instance runs the candidate's server because the stores' beta reviews of the
candidate's apps sign in there; a newer server serves the released apps as well.

### The release

The release tag starts `release.yml`: the three images, Android to the internal track,
iOS to TestFlight, the store listings, and the GitHub release with the setup files and
the notes. The product comes as one: the GitHub release waits for both apps, and a
failed upload stops it -- run the failed jobs again.

*Upgrade notes* in the version's section are what an administrator reads before
updating — write them for that reader.

Promoting the builds beyond testing (Play production, App Store review) happens in the
store consoles.

### The public tests

Until the apps are in the stores, anyone can install them through a public test, in two
groups: the **released version** and the **preview**, the candidates. A tag's builds go
to them on their own, once uploaded (the jobs `play-testers` and `testflight-testers`);
intermediate builds stay with the internal testers.

| Tag | TestFlight: external groups | Google Play: closed tracks |
| --- | --- | --- |
| a candidate | *Public preview testers* | *Public preview test* |
| a release | *Public testers* and *Public preview testers* | *Public test* and *Public preview test* |

- **A release goes to the preview, too:** its testers would otherwise stay on the
  last candidate.
- **No test gets a version older than one it has had** -- its testers would install it
  over the newer one. A patch while the next version is a candidate goes to the
  released version's test only, and the patch's own candidates to the internal testers
  only. The job `version` decides from the tags (its output `testers`).
- **TestFlight:** two external groups with a public link each. The lane `testers` in
  `app/ios` waits until Apple has processed the build, gives it to the groups and
  submits it for Apple's beta review. *What to Test* points to the website:
  `release_notes.txt` for a release, `testflight/<locale>/candidate.txt` for a
  candidate. Apple reviews the first build of every version before a link offers it --
  about a day, so the first candidate waits; later candidates and the release of the
  same version usually do not. Apple reviews one build of a version at a time: a newer
  one takes the place of one still waiting, which expires.
- **Google Play:** two closed tracks, each admitting the members of a Google Group
  anyone can join. The lane `testers` in `app/android` releases the build to them, with
  the release notes of the internal track: `changelogs/default.txt`, or
  `changelogs/candidate.txt` for a candidate. Google reviews every release in a track,
  from a few hours to a few days. Play gives a tester in both tracks the higher version
  code: the candidate, and after the release the release -- but also a patch released
  while the next version is a candidate, whose build is newer.

The groups' and tracks' names are in the Fastfiles (`TESTER_GROUPS`, `TEST_TRACKS`): one
renamed in a console is renamed there, too. A test that refuses a build fails only its
own job, not the GitHub release; run the job again, or the lane by hand:

```sh
cd app/android && fastlane testers version:2026.2.0-rc.1 build:57 to:preview check:true  # Play only checks
cd app/android && fastlane testers version:2026.2.0-rc.1 build:57 to:preview
cd app/ios && fastlane testers version:2026.2.0-rc.1 build:57 to:preview
```

**Going back from a candidate to the released app is not supported:** the app is
deleted and installed again, after leaving the preview's group (the website's preview
page says so to testers). Play does not offer an older version code at all; TestFlight
does, but the app would open the candidate's newer local database.

The links are on the website, taken from `site/hugo.toml`: the released version's on
the apps page (`params.apps`), the preview's on the preview page (`params.preview`)
([`development/website.md`](development/website.md)).

If the secrets `DEPLOY_REPO` and `DEPLOY_TOKEN` are set, the last job of a release or a
candidate asks the workflow `deploy.yml` in that repository to deploy the version
(`gh workflow run … -f version=<version> -f target=<all|candidate>`). Both are secrets,
so neither the repository nor the token shows in the public log. Without them the job
says there is nothing to deploy to and ends green; a fork releases without deploying
anywhere.

## Intermediate builds

| Build | How |
| --- | --- |
| Server image, demo, website, Android and/or iOS | GitHub → Actions → Release → **Run workflow**, tick what to build |

From a release branch, the apps' jobs reach their keys only if the environments `play`
and `apple` admit `release/*` as well as `main` and `v*` ("Signing and store
credentials"); the candidates themselves come from their tags and need no such rule.

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
`APP_STORE_CONNECT_ISSUER_ID` from the environment `apple`. Both admit only the tags `v*` --
releases and candidates -- and `main`. The workflow writes them only to files in the runner's temp folder, never
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
| `no dev tag (v<version>-dev) or release candidate tag before this commit` | No dev tag yet, or the tags were not fetched (`git fetch --tags`). |
| `v… is released, but the latest dev or candidate tag is …` | The dev tag after the last release is missing: `git tag v<next>-dev` on `main`. On a release branch after its release: a further fix is the next patch (`tool/release.sh candidate <version>`). |
| `Tag … is neither a release tag … nor a release candidate tag …` | A tag `v…` was pushed that is none of `vX.Y.Z`, `vX.Y.Z-rc.N` or a dev tag. |
| `No notes for <version>-rc.<n> in the changelog` | The candidate's section of `CHANGELOG.md` is empty -- for a patch, its fixes have not been merged yet. |
| `No notes for <version> in the changelog` at the GitHub release | The release tag was set without `tool/release.sh final`: the section still says *Release candidate*. |
| `tool/release.sh final`: `there are commits since v…-rc.…` | The release is the last candidate as tested: tag the newer commits as a candidate first. |
| `tool/release.sh`: `conflicts beyond CHANGELOG.md` | Merging the release branch into `main` met a real conflict: resolve it on `main`, `git commit`, switch back to the branch. |
| Play: `The caller does not have permission` | The service account is not invited in the Play Console, or the permission has not arrived yet. |
| Play: `Only releases with status draft may be created on draft app` | The app was never rolled out: `fastlane internal status:draft`, then roll out in the console. |
| Play: `The caller does not have permission` at *Validating all changes*, in `fastlane metadata` | The app has never been published (a draft app): the service account needs *Edit and delete draft apps* as well as *Manage store presence*. |
| Play: `Release in track targeting no countries`, in `fastlane testers` | The closed track has no countries yet: Play Console → the track → *Countries / regions*, the same as the other test's. |
| TestFlight: `No group … in TestFlight`, in `fastlane testers` | The group's name in App Store Connect differs from `TESTER_GROUPS` in `app/ios/fastlane/Fastfile`. |
| `App Store Connect API key JSON is missing field(s): key` | The file was given as `api_key_path`; the lane reads the format above itself. |
| `android/key.properties is missing` | No upload key on this machine. |
| The Android job is cancelled at its time limit, silent after the native builds | The runner (8 GB in a private repository) ran out of memory and swapped. The `memory:` lines in the log show it; the step *Gradle memory* in `release.yml` sets the build's heap. |
