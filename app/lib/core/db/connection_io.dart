import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../common/app_names.dart';

const _walMode = 'PRAGMA journal_mode = WAL';
const _busyTimeout = 'PRAGMA busy_timeout = 5000';

/// On the device: a file that persists. Working on offline is the whole point of the app.
QueryExecutor openConnection() => driftDatabase(
  name: AppNames.product,
  native: DriftNativeOptions(
    // The background sync opens the file from an engine of its own —
    // a connection of its own, deliberately not one shared through an isolate: the
    // isolate would die with whichever engine started it, and the other would be
    // left with a dead database. Two connections to one file need SQLite's locking:
    // WAL so reads never wait for the other's writes, and a timeout instead of an
    // immediate "database is locked" when both write.
    setup: (database) {
      database.execute(_walMode);
      database.execute(_busyTimeout);
    },
  ),
);

/// A database that lives only as long as it is open — for content shown, not kept.
QueryExecutor openMemoryConnection() => NativeDatabase.memory();
