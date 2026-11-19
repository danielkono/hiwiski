# Web directory

Next to `index.html` this directory holds one file that Drift needs in the browser:

| File | Source | Purpose |
| --- | --- | --- |
| `sqlite3.wasm` | [sqlite3.dart releases](https://github.com/simolus3/sqlite3.dart/releases), same version as `sqlite3` in `pubspec.lock` | the SQLite core |

**Without it the local database in the browser stays silent — and without an error
message.** The streams never emit, and the UI sits on "loading". That is exactly how it
was noticed the first time.

In the browser the database lives **in memory only** (`lib/core/db/connection_web.dart`):
the web version is not used offline; every page load fetches the state fresh from the
server. A worker and OPFS are therefore no longer needed; `drift_worker.js` has been
removed.

The version must match `pubspec.lock`. After an update of `sqlite3`:

```sh
curl -fsSL -o web/sqlite3.wasm \
  "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-<version>/sqlite3.wasm"
```
