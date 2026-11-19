import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/api/hiwiski_api.dart';
import '../core/db/hiwiski_database.dart';
import '../core/platform/home_widget_bridge.dart';
import '../core/platform/reminder_scheduler.dart';
import '../core/storage/local_image_store.dart';
import '../core/storage/local_settings.dart';
import '../core/storage/token_store.dart';
import '../core/sync/local_writes.dart';
import '../core/sync/outbox.dart';
import '../core/sync/pending_shares.dart';
import '../core/sync/sync_engine.dart';
import '../domain/session/session_state.dart';
import 'stores.dart';
import 'background_sync.dart';
import 'leave_guard.dart';

part 'data_providers.g.dart';

/// The data layer: the clients that exist exactly once. Only the composition root
/// sees these providers — the repositories get the clients handed in
/// (`repositories.dart`).
///
/// `LocalSettings` is loaded before the first frame and overridden here — the first
/// frame should already carry the right theme instead of flashing light.

/// No automatic retry of a failed provider. Riverpod 3 retries one up to ten times
/// over some forty seconds and keeps it *loading* meanwhile — a screen's `when` then
/// showed the loading strip instead of the error, offline for most of a minute. The
/// app asks again on its own terms: "Try again" on the error, and the repositories
/// fetch again after every sync.
// `null` is the answer here: never retry.
// ignore: many_lints/function_always_returns_null
Duration? noRetry(int retryCount, Object error) => null;

@Riverpod(keepAlive: true)
LocalSettings localSettings(Ref ref) =>
    throw StateError('LocalSettings is overridden in main()');

/// The device's time zone, as an IANA name ("Europe/Berlin").
///
/// It is determined **before the first frame** and handed in here, not looked up on
/// every use: a series that gets a different zone when created than when displayed
/// shifts by an hour, and only sometimes.
@Riverpod(keepAlive: true)
String deviceTimeZone(Ref ref) =>
    throw StateError('deviceTimeZoneProvider must be overridden');

@Riverpod(keepAlive: true)
TokenStore tokenStore(Ref ref) => .create();

@Riverpod(keepAlive: true)
HiwiskiApi hiwiskiApi(Ref ref) {
  final settings = ref.watch(localSettingsProvider);
  return HiwiskiApi(
    tokens: ref.watch(tokenStoreProvider),
    baseUrl: settings.serverAddress ?? '',
  );
}

/// The local database -- the single source of truth for the UI.
@Riverpod(keepAlive: true)
HiwiskiDatabase database(Ref ref) {
  final database = HiwiskiDatabase();
  ref.onDispose(database.close);
  return database;
}

@Riverpod(keepAlive: true)
Outbox outbox(Ref ref) => .new(ref.watch(databaseProvider));

/// The images added without a server, until they are uploaded.
@Riverpod(keepAlive: true)
LocalImageStore localImageStore(Ref ref) => .new(ref.watch(databaseProvider));

/// The sync, created on the first nudge and not with whoever nudges — a screen that
/// only reads never starts it.
class LazySync implements SyncTrigger {
  LazySync(this._ref);

  final Ref _ref;

  @override
  Future<void> syncNow() => _ref.read(syncEngineProvider).syncNow();
}

/// Every change made on this device: the row and its mutation, together.
@Riverpod(keepAlive: true)
LocalWrites localWrites(Ref ref) => .new(
  db: ref.watch(databaseProvider),
  outbox: ref.watch(outboxProvider),
  sync: LazySync(ref),
);

@Riverpod(keepAlive: true)
PendingShares pendingShares(Ref ref) => .new(
  settings: ref.watch(localSettingsProvider),
  api: ref.watch(hiwiskiApiProvider),
);

@Riverpod(keepAlive: true)
ReminderScheduler reminderScheduler(Ref ref) => createReminderScheduler();

@Riverpod(keepAlive: true)
HomeWidgetBridge homeWidgetBridge(Ref ref) => const .new();

/// The sync: push, then pull.
///
/// It learns who is signed in from the session — wired here, because the sync sits
/// below the session and must not know it.
@Riverpod(keepAlive: true)
SyncEngine syncEngine(Ref ref) {
  final background = ref.watch(backgroundSyncProvider);
  final engine = SyncEngine(
    api: ref.watch(hiwiskiApiProvider),
    db: ref.watch(databaseProvider),
    outbox: ref.watch(outboxProvider),
    pendingShares: ref.watch(pendingSharesProvider),
    session: _SessionForSync(ref),
    runningElsewhere: background.runningElsewhere,
    onPendingChanged: (count) {
      // Without a server the outbox only grows: nothing in it waits for anything.
      final pending = ref.read(sessionProvider).hasServer ? count : 0;
      guardLeaving(pending: pending > 0);
    },
  );
  ref.onDispose(engine.dispose);
  return engine;
}

/// The background job follows the session: it runs for as long as a member is signed
/// in at a server, whether or not something waits to be sent — what others changed
/// has to arrive without the app, too, or its reminders never ring.
@Riverpod(keepAlive: true)
void backgroundSyncSchedule(Ref ref) {
  final background = ref.watch(backgroundSyncProvider);
  ref.listen(sessionProvider, (_, session) {
    // A job that could not be registered leaves the app as it was: it syncs on its
    // own while it is open.
    background.sessionChanged(signedIn: session.stage == .signedIn).ignore();
  }, fireImmediately: true);
}

class _SessionForSync implements SyncSession {
  _SessionForSync(this._ref);

  final Ref _ref;

  // A locked device keeps whom its data belongs to, but has no access: nothing syncs.
  // Nor does a device without a server: its member exists only here.
  @override
  String? get memberId {
    final session = _ref.read(sessionProvider);
    return _syncs(session) ? session.member?.id : null;
  }

  @override
  String? get deviceId {
    final session = _ref.read(sessionProvider);
    return _syncs(session) ? session.session?.deviceId : null;
  }

  static bool _syncs(SessionState session) =>
      session.stage != .accessLost && session.hasServer;

  @override
  Future<void> signedOutElsewhere() =>
      _ref.read(sessionStoreProvider).signedOutElsewhere();

  @override
  Future<void> claimLocalData() =>
      _ref.read(sessionStoreProvider).claimLocalData();

  @override
  void restoreRunning({required bool running}) {
    final store = _ref.read(sessionStoreProvider);
    // Begun: waits at once. Ended: the handshake says so, and the watch stops.
    running ? store.beginRestore() : unawaited(store.checkRestore());
  }
}
