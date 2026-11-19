import 'dart:async';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:workmanager/workmanager.dart';

import '../core/platform/device_time_zone.dart';
import '../core/storage/local_settings.dart';
import 'background_sync.dart';
import 'data_providers.dart';
import 'repositories.dart';
import 'stores.dart';

/// The task's name — on iOS also the BGTaskScheduler identifier, listed under
/// `BGTaskSchedulerPermittedIdentifiers` in `Info.plist`.
const _task = 'de.danielkononov.hiwiski.sync';

/// How often the background sync runs — on iOS also the AppDelegate's earliest start.
const _every = Duration(minutes: 15);

/// Where the running app answers. A background run that finds it lets the app sync
/// instead of running a second sync next to it.
const _foregroundPort = 'hiwiski.sync.foreground';

/// Where a background run answers while it is running.
const _backgroundPort = 'hiwiski.sync.background';

/// Only the apps have a queue that outlives them; in the browser it lives in memory,
/// and on the desktop the scheduler only runs while the app does.
bool get _supported => Platform.isAndroid || Platform.isIOS;

/// Before `runApp`: the platform has to know what to start in the background.
Future<void> initializeBackgroundSync() async {
  if (!_supported) return;
  await Workmanager().initialize(backgroundSyncDispatcher);
}

BackgroundSync createBackgroundSync() =>
    _supported ? _ScheduledSync() : const NoBackgroundSync();

class _ScheduledSync implements BackgroundSync {
  bool? _scheduled;

  @override
  Future<void> sessionChanged({required bool signedIn}) async {
    if (signedIn == _scheduled) return;
    _scheduled = signedIn;
    if (signedIn) {
      await Workmanager().registerPeriodicTask(
        _task,
        _task,
        frequency: _every,
        // iOS ignores the frequency and asks for the next run right away unless told
        // otherwise — every run then used up the app's background budget at once, and
        // iOS throttled it. Android runs the first one soon, as before.
        initialDelay: Platform.isIOS ? _every : Duration.zero,
        constraints: Constraints(networkType: .connected),
        // Every start of the app registers again; that must not push the next run
        // further away.
        existingWorkPolicy: .keep,
      );
    } else {
      await Workmanager().cancelByUniqueName(_task);
    }
  }

  @override
  Future<bool> runningElsewhere() async {
    return _answers(_backgroundPort);
  }
}

/// The running app makes itself known to the background runs. [sync] runs when a
/// background run asks the app to sync in its place, [caughtUp] when a background run
/// has just finished — what it wrote, the app's own streams did not see.
ForegroundSync serveForegroundSync({
  required AsyncCallback sync,
  required AsyncCallback caughtUp,
}) {
  final port = ReceivePort();
  // A hot restart or a torn-down engine leaves the old mapping behind.
  IsolateNameServer.removePortNameMapping(_foregroundPort);
  IsolateNameServer.registerPortWithName(port.sendPort, _foregroundPort);
  final messages = port.listen(
    (message) => unawaited(_answer(message, sync: sync, caughtUp: caughtUp)),
  );
  return _ForegroundSync(port, messages);
}

Future<void> _answer(
  Object? message, {
  required AsyncCallback sync,
  required AsyncCallback caughtUp,
}) async {
  switch (message) {
    case [_ping, final SendPort reply]:
      reply.send(true);
    case [_syncInstead, final SendPort reply]:
      reply.send(true);
      try {
        await sync();
      } catch (error) {
        // The app reports its own failures; the background run only needs the end.
        debugPrint('hiwiski: background sync failed: $error');
      }
      reply.send(true);
    case _caughtUp:
      await caughtUp();
  }
}

class _ForegroundSync implements ForegroundSync {
  _ForegroundSync(this._port, this._messages);

  final ReceivePort _port;
  final StreamSubscription<Object?> _messages;

  @override
  void close() {
    if (IsolateNameServer.lookupPortByName(_foregroundPort) == _port.sendPort) {
      IsolateNameServer.removePortNameMapping(_foregroundPort);
    }
    unawaited(_messages.cancel());
    _port.close();
  }
}

/// What the platform starts in the background.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) => runBackgroundSync());
}

/// One background run: push, then pull — the same run as in the app — and then the
/// reminders, scheduled anew from what the pull brought.
///
/// Returns `true` also when the server cannot be reached: the job is periodic and
/// tries again on its own; a `false` would only add Android's backoff on top.
Future<bool> runBackgroundSync() async {
  // The app is alive in this process (on Android the process outlives the screen, on
  // iOS the app may only be suspended): it syncs itself, with its own state.
  if (await _syncInForeground()) return true;

  final port = ReceivePort();
  IsolateNameServer.removePortNameMapping(_backgroundPort);
  IsolateNameServer.registerPortWithName(port.sendPort, _backgroundPort);
  final pings = port.listen((message) {
    if (message case [_ping, final SendPort reply]) reply.send(true);
  });

  // The zone database belongs to this engine, too: without it a series expands in UTC
  // and its reminders ring an hour off after a clock change.
  final (settings, timeZone) = await (
    LocalSettings.open(),
    loadDeviceTimeZone(),
  ).wait;
  final container = ProviderContainer(
    retry: noRetry,
    overrides: [
      localSettingsProvider.overrideWithValue(settings),
      deviceTimeZoneProvider.overrideWithValue(timeZone),
      // The last confirmed session, without the handshake on start: the sync itself
      // signs out on a 401.
      sessionHandshakeOnStartProvider.overrideWithValue(false),
      backgroundSyncProvider.overrideWithValue(const NoBackgroundSync()),
    ],
  );
  try {
    // Nobody signed in, or signed in without "Stay signed in": that token lived in
    // the app's memory and went with the app. Asking the server without one would be
    // answered with a 401 and recorded as access lost.
    if (container.read(sessionProvider).member == null ||
        await container.read(tokenStoreProvider).read() == null) {
      await Workmanager().cancelByUniqueName(_task);
      return true;
    }
    await container.read(syncRepositoryProvider).syncNow();
    await _rescheduleReminders(container);
    return true;
  } catch (_) {
    return false;
  } finally {
    container.dispose();
    IsolateNameServer.removePortNameMapping(_backgroundPort);
    await pings.cancel();
    port.close();
    // If the app came up meanwhile, it waited for this run.
    IsolateNameServer.lookupPortByName(_foregroundPort)?.send(_caughtUp);
  }
}

/// Schedules the reminders from what the run just pulled. The running app does that
/// from its table streams; here nobody watches, and what this run wrote would not
/// remind until the app is opened.
///
/// A failure costs the reminders of this run, never the sync that is already done: the
/// next run schedules everything anew.
Future<void> _rescheduleReminders(ProviderContainer container) async {
  try {
    // In the app the localizations load the date names with the first frame; here no
    // frame is ever drawn, and a reminder would name its day in numbers only.
    await initializeDateFormatting();
    await container.read(reminderRepositoryProvider).rescheduleOnce();
  } on Object catch (error) {
    debugPrint('hiwiski: reminders not rescheduled in the background: $error');
  }
}

/// Asks the running app to sync and waits for it — within the 30 seconds iOS grants.
Future<bool> _syncInForeground() async {
  final app = IsolateNameServer.lookupPortByName(_foregroundPort);
  if (app == null) return false;
  final answers = ReceivePort();
  final replies = StreamIterator(answers);
  try {
    app.send([_syncInstead, answers.sendPort]);
    // The acknowledgement comes at once — unless the port is left over from an app
    // that is gone.
    final alive = await replies.moveNext().timeout(
      const Duration(seconds: 1),
      onTimeout: () => false,
    );
    if (!alive) {
      IsolateNameServer.removePortNameMapping(_foregroundPort);
      return false;
    }
    await replies.moveNext().timeout(
      const Duration(seconds: 25),
      onTimeout: () => false,
    );
    return true;
  } finally {
    await replies.cancel();
    answers.close();
  }
}

/// Whether someone still answers under [name]; a left-over mapping is removed.
Future<bool> _answers(String name) async {
  final port = IsolateNameServer.lookupPortByName(name);
  if (port == null) return false;
  final answers = ReceivePort();
  try {
    port.send([_ping, answers.sendPort]);
    await answers.first.timeout(const Duration(seconds: 1));
    return true;
  } on TimeoutException {
    IsolateNameServer.removePortNameMapping(name);
    return false;
  } finally {
    answers.close();
  }
}

// The background run is an engine of its own, a different isolate group: across that
// border only plain values travel, no instances of our own classes.
const _ping = 'ping';
const _syncInstead = 'sync';
const _caughtUp = 'caught-up';
