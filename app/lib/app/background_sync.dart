import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'background_sync_stub.dart'
    if (dart.library.io) 'background_sync_io.dart'
    as platform;

export 'background_sync_stub.dart'
    if (dart.library.io) 'background_sync_io.dart'
    show initializeBackgroundSync, serveForegroundSync;

part 'background_sync.g.dart';

/// Sync without the app.
///
/// Changes made offline must reach the server even if the app is not opened again —
/// whoever comes home does not open the app for that. And what others changed must
/// reach this device the same way: reminders are scheduled from the local database, so
/// an event somebody else entered would otherwise not remind until the app is opened,
/// while the home screen widgets, which ask the server themselves, already show it
/// (`docs/development/home-widgets.md`). As long as a member is signed in, a periodic
/// job is registered: on Android with WorkManager whenever there is a network, at most
/// every 15 minutes; on iOS as a `BGAppRefreshTask`, whenever iOS grants one. **After a
/// force quit iOS starts nothing until the app is opened again** — no API gets around
/// that.
abstract interface class BackgroundSync {
  /// Registers the job while a member is signed in at a server, and removes it
  /// otherwise.
  Future<void> sessionChanged({required bool signedIn});

  /// Whether a background run is pushing right now — then the app waits for it
  /// instead of sending the same outbox a second time. The run wakes the app when it
  /// is done.
  Future<bool> runningElsewhere();
}

/// In the browser, and for the background run itself: it neither schedules nor waits
/// for itself.
class NoBackgroundSync implements BackgroundSync {
  const NoBackgroundSync();

  @override
  Future<void> sessionChanged({required bool signedIn}) async {}

  @override
  Future<bool> runningElsewhere() async => false;
}

/// The running app, known to the background runs.
abstract interface class ForegroundSync {
  void close();
}

@Riverpod(keepAlive: true)
BackgroundSync backgroundSync(Ref ref) => platform.createBackgroundSync();
