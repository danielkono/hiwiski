# Hiwiski

A self-hosted app for **one** family: a shared calendar, tasks including the shopping
list and Kanban boards, a wiki that also holds the recipes, a search across everything,
a start board and a dashboard for a wall tablet.

One Flutter app for Android, iOS, macOS, Windows, Linux and the browser; one Spring Boot
server in the family's home, with Postgres. No cloud, no account with a provider, no
telemetry.

- **Website, features and the setup guide:** <https://hiwiski.app>
- **Try it without installing anything:** the demo, linked from the website
- **What changed:** [`CHANGELOG.md`](CHANGELOG.md)

## Apps

Until the apps are in the App Store and on Google Play, anyone can install them as a test
version:

| Platform | Get it |
| --- | --- |
| Android 8.0 or later | The test on Google Play: join the [testers group](https://groups.google.com/g/hiwiski-testers), then [become a tester](https://play.google.com/apps/testing/de.danielkononov.hiwiski) and install Hiwiski from Google Play |
| iPhone and iPad, iOS 15 or later | [TestFlight](https://testflight.apple.com/join/MhTFxGNk) — Apple's TestFlight app installs it |
| Browser | Your server's address — or the [demo](https://demo.hiwiski.app/), which needs no server |

The app can also be used without a server; it connects to the family's server
later and keeps what is on the device. The steps one by one, with a QR code for
the phone, and where to send feedback: <https://hiwiski.app/en/apps/>.

## What everything hangs on

1. **Usable offline.** A home server cannot be reached from on the road. Every input
   goes through immediately, on the device, and syncs later.
2. **Compatible across versions.** An older app must not break against a newer server
   and must not destroy anything it does not know.
3. **Easy to set up for non-experts.** One compose file, one `.env`, a setup wizard.

## Running a server

```sh
mkdir hiwiski && cd hiwiski
# docker-compose.yml, Caddyfile and env.example from the latest GitHub release
cp env.example .env        # fill in: passwords, host name, backup directory
docker compose up -d
docker compose logs app | grep "Setup code"
```

Then open the address in a browser: the setup wizard creates the family and its
administrator. The full guide — TLS on a home network, backups, updates, moving to
another machine — is on the website (`site/content/en/setup/`).

## Repository

| Directory | Contents |
| --- | --- |
| `api/` | The OpenAPI contract, split by module. Both sides are generated from it. |
| `app/` | The Flutter app: every platform, the web version, the demo, the website's app views. |
| `server/` | The Spring Boot server: `:api` (generated interfaces), `:db` (Flyway migrations, generated jOOQ), `:app`. |
| `deploy/` | What a family installs (`docker-compose.yml`, `Caddyfile`, `.env.example`) and the Dockerfiles of the images. |
| `golden/` | Test cases server and app are both checked against. |
| `site/` | The website (Hugo). |
| `tool/` | Versions from tags, the changelog, the website's tools. |
| `docs/` | Documentation for developers. |

## Development

Start with [`docs/`](docs/README.md):

- [Setting up a development environment](docs/development/setup.md) — tools, first build, running it locally
- [Architecture](docs/development/architecture.md) — the data path, sync, sharing, the modules, the data model
- [The server](docs/development/server.md), [the app](docs/development/app.md), [the contract](docs/development/api.md), [the website](docs/development/website.md)
- [Releasing](docs/releasing.md)

In short:

```sh
cd server && ./gradlew build          # JDK 25 and Docker
cd app && flutter pub get && dart run swagger_parser \
  && dart run build_runner build --delete-conflicting-outputs \
  && dart analyze && flutter test     # Flutter 3.47.1
```

## Contributing

Pull requests are not accepted at the moment. Bug reports and ideas are welcome as
issues — for a bug, the version (shown under *About*), the platform, what you did, what
you expected and what happened. Please report a security issue through GitHub's
**Report a vulnerability** under the repository's *Security* tab, not in a public issue.

## License

[PolyForm Noncommercial 1.0.0](LICENSE.md). Reading, self-hosting, changing and sharing
for noncommercial purposes is allowed; commercial use needs a separate license. The code
is source-available, not open source in the OSI sense.
