import 'package:flutter/foundation.dart';

import 'background_sync.dart';

/// In the browser the queue lives in memory and is gone with the tab: there is
/// nothing a job could send later. `leave_guard_web.dart` asks before closing instead.
Future<void> initializeBackgroundSync() async {}

BackgroundSync createBackgroundSync() => const NoBackgroundSync();

ForegroundSync serveForegroundSync({
  required AsyncCallback sync,
  required AsyncCallback caughtUp,
}) => const _NoForegroundSync();

class _NoForegroundSync implements ForegroundSync {
  const _NoForegroundSync();

  @override
  void close() {}
}
