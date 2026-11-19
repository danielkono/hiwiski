# Setting up a development environment

Everything needed to build, test and run Hiwiski on your own machine: the server, the
apps, the web version and the website. The commands are for macOS; on Linux they are the
same apart from how the tools are installed.

## Tools

| Tool | Version | What for | Install (macOS) |
| --- | --- | --- | --- |
| **JDK** | 25 | the server (Gradle toolchain, `server/gradle/libs.versions.toml`) | `brew install openjdk@25` |
| **Flutter** | 3.47.1, pinned in `app/.fvmrc` | the apps, the web version, the website's scenes | [FVM](https://fvm.app): `brew install fvm`, then `fvm install` in `app/` |
| **Docker** | any recent | the server's tests (Testcontainers), a local Postgres, the release images | Docker Desktop, or [Colima](https://github.com/abiosoft/colima): `brew install colima docker` |
| **Python** | 3 | `app/tool/generate_symbols.py` (new Material symbols) | preinstalled |
| **Hugo** (extended) | 0.168.0, pinned in `tool/site_tools.sh` | the website | `brew install hugo` |

Only for releasing the apps yourself:

| Tool | What for |
| --- | --- |
| **Xcode** with the iOS platform | iOS and macOS builds |
| **Android SDK** (Android Studio) and JDK 17 | Android builds |
| **Ruby** with Bundler, for **fastlane** as `app/Gemfile.lock` pins it: `bundle install` in `app/`, then `bundle exec fastlane …` runs the gems `release.yml` runs | uploading to TestFlight and Google Play — see [`../releasing.md`](../releasing.md) |

The Gradle wrapper (`server/gradlew`) brings Gradle itself. Nothing else needs to be on
the machine: the OpenAPI generator, jOOQ's code generator, Flyway and `openapi-diff` are
Gradle dependencies, and the Dart code generators are dev dependencies of the app.

### Paths

Neither the JDK nor an FVM-installed Flutter is on the `PATH` by default. In your shell
profile, or before working in a new shell:

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@25/libexec/openjdk.jdk/Contents/Home
export PATH="$HOME/fvm/versions/3.47.1/bin:$PATH"   # or use `fvm flutter …`
```

Use `fvm flutter` and `fvm dart` if you prefer not to touch the `PATH`. Avoid
`fvm use` in scripts: it may stop at an interactive prompt.

### Docker under Colima

The server's integration tests start Postgres through Testcontainers. Under Colima,
Testcontainers needs two variables, or its helper container (Ryuk) fails to mount the
Docker socket (`mkdir …docker.sock: operation not supported`):

```sh
colima start
export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock
```

Docker Desktop needs neither.

## First build

```sh
git clone <repository> hiwiski && cd hiwiski

# Server: compiles, generates jOOQ from the migrations, runs every test.
cd server && ./gradlew build && cd ..

# App: dependencies, then the generated code, then analysis and tests.
cd app
flutter pub get
dart run swagger_parser                                   # the Dart API client, from api/
dart run build_runner build --delete-conflicting-outputs  # Drift, Freezed, Riverpod, l10n
tool/generate_widget_client.sh                            # the iOS widgets' client (macOS only)
dart analyze
flutter test
```

**Generated code is not checked in.** The Dart client (`lib/core/api/generated/`), the
`*.g.dart` and `*.freezed.dart` files, the localizations and the jOOQ classes are made
by the commands above. After pulling a change to `api/`, the tables or a ViewModel, run
the two `dart run` lines again — and, for an iOS build, `tool/generate_widget_client.sh`:
the Xcode build stops with a note when the home screen widgets' client is older than the
contract ([`home-widgets.md`](home-widgets.md)). The Android widgets' client is generated
by the Gradle build itself.

**`dart analyze`, not `flutter analyze`.** Only `dart analyze` runs analyzer plugins,
and the project's own rules live in one (`app/tool/hiwiski_lints`, see
[`app.md`](app.md#analysis)). `flutter analyze` reports a clean result that is not.

The server build takes a few minutes, most of it the integration tests. `./gradlew
build -x test` builds without them; `./gradlew :app:test --tests '*SyncIT'` runs one
class. Gradle's `-q` hides the test summary: the results are in
`server/app/build/test-results/test/`.

## Running it locally

### A database

```sh
docker run -d --name hiwiski-dev-db -p 55432:5432 \
  -e POSTGRES_DB=hiwiski -e POSTGRES_USER=hiwiski -e POSTGRES_PASSWORD=hiwiski \
  postgres:18-alpine
```

The same major version as `deploy/docker-compose.yml`. The server migrates the schema
itself on start (Flyway).

### The server

The server refuses to start without its required variables, and names the missing one.
Put them in a file outside the repository, for example `~/.hiwiski-dev.env`:

```sh
HIWISKI_DB_URL=jdbc:postgresql://localhost:55432/hiwiski
HIWISKI_DB_USER=hiwiski
HIWISKI_DB_PASSWORD=hiwiski
HIWISKI_MEDIA_PATH=/Users/<you>/hiwiski-dev/media
HIWISKI_BACKUP_PATH=/Users/<you>/hiwiski-dev/backups
HIWISKI_SETUP_CODE=dev-setup-code
```

The two directories must exist and be writable — the server checks at start.
`HIWISKI_SETUP_CODE` fixes the setup code, which is otherwise random and printed to the
log at every start until the instance is set up. Every other variable has a default
(`server/app/src/main/resources/application.yaml`; what they do is in
`deploy/.env.example`).

```sh
cd server
set -a; . ~/.hiwiski-dev.env; set +a
./gradlew :app:bootRun
```

The server listens on `http://localhost:8080`. A fresh database opens the setup
wizard; there you create the family and its administrator.

### The web version through the server

The server serves the web build itself, as in production. Build it first:

```sh
cd app
flutter build web --release --tree-shake-icons --no-web-resources-cdn
```

then (re)start `bootRun`: it copies `app/build/web` into the server's resources when it
starts, so every new web build needs a server restart. Open `http://localhost:8080`.

- **`--no-web-resources-cdn` is required.** Without it CanvasKit is loaded from
  Google's CDN, the server's Content Security Policy blocks it, and the page stays
  black.
- Serving the web build from another port (`python -m http.server`) does not work: the
  server sends no CORS headers, and the app reports that it cannot find a server.

### The apps against the local server

```sh
cd app
flutter run -d macos          # or an emulator, a simulator, a device: `flutter devices`
```

At the start the app asks for the server address. On the same machine that is
`http://localhost:8080`; from a phone it is the machine's address on the network
(`http://192.168.x.y:8080`). Over plain HTTP the app shows that the connection is not
encrypted — that is expected.

**Updating an app on an iPhone keeps its data only with `xcrun devicectl`.**
`flutter install` uninstalls first and so deletes the local database and the outbox:

```sh
flutter build ios --release
xcrun devicectl device install app --device <device-id> build/ios/iphoneos/Runner.app
```

### Without a server

The app also runs entirely on the device: "Use without a server" at the start. That is
the same app with a local member and no sync; the public demo is this mode in a browser
with sample data (`--dart-define=HIWISKI_DEMO=true`).

### The website

```sh
cd site && hugo server
```

Hugo serves the site with live reload on `http://localhost:1313`. The app views
embedded in its pages ("scenes") and the search need the release build; see
[`website.md`](website.md).

## Editors

Any editor works. The repository has VS Code launch configurations in `.vscode/`
(not tracked); for IntelliJ, open `server/` as a Gradle project and `app/` with the
Flutter plugin. Format Dart with `dart format` (defaults, no project style) and Java
with the IDE's default formatter in the style of the surrounding code.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| Server tests fail with `Could not find a valid Docker environment` | Docker is not running, or under Colima the two variables above are missing. |
| `bootRun` exits at once and names a variable | A required variable is missing or a directory is not writable. |
| The web version shows a black page | The web build was made without `--no-web-resources-cdn`. |
| The web version shows an old state | The server was not restarted after the web build. |
| `dart analyze` finds nothing, CI does | You ran `flutter analyze`. |
| `The getter … isn't defined` after a pull | Generated code is stale: run `dart run swagger_parser` and `build_runner`. |
| The web app sits on "loading" forever | `app/web/sqlite3.wasm` does not match the `sqlite3` version in `pubspec.lock` (`app/web/README.md`). |
