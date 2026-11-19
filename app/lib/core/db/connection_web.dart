import 'dart:ui_web' as ui_web;

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:sqlite3/wasm.dart';
import 'package:web/web.dart' as web;

/// Next to the build's `assets/` directory.
const _sqliteWasm = '../sqlite3.wasm';

/// In the browser: **in memory only.**
///
/// The web version is not used offline; working offline is reserved for the apps. A
/// mirror that outlives the tab only caused trouble there: all tabs shared the database
/// in a shared worker, a migration only ran once no old tab held it open any more, and
/// after signing out the family was still sitting in the browser. Now every page load
/// fetches the state fresh from the server — as a snapshot, not as a log —,
/// and when the tab is gone, everything is gone.
///
/// Reads and writes still go against this database, never directly against the API:
/// one data path for all platforms.
///
/// `sqlite3.wasm` lives in `web/` (see `web/README.md`). Its address is resolved against
/// the page's `<base href>`, not against the address in the bar: `Uri.base` is the
/// latter, and a page reloaded on `/tasks/list/…` asked for `/tasks/list/sqlite3.wasm`,
/// got the app's `index.html` from the deep-link fallback, and never got past loading.
/// It is read against the engine's asset base, which is the page's `<base href>`
/// unless the page set another: the website's scenes load the build from `/embed/`.
QueryExecutor openConnection() => DatabaseConnection.delayed(
  Future(() async {
    final sqlite3 = await WasmSqlite3.loadFromUrl(
      Uri.parse(web.document.baseURI)
          .resolve(ui_web.assetManager.getAssetUrl(''))
          .resolve(_sqliteWasm),
    );
    sqlite3.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
    return DatabaseConnection(WasmDatabase.inMemory(sqlite3));
  }),
);

/// A database that lives only as long as it is open — in the browser every one does.
QueryExecutor openMemoryConnection() => openConnection();
