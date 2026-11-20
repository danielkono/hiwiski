import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random, min;

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:meta/meta.dart' show protected, visibleForTesting;

import '../api/generated/export.dart';
import '../api/hiwiski_api.dart';
import '../api/hiwiski_failure.dart';
import '../common/sync_limits.dart';
import '../common/wire.dart';
import '../db/hiwiski_database.dart';
import '../db/tables.dart';
import 'entity_codec.dart';
import 'event_stream.dart';
import 'outbox.dart';
import 'left_behind.dart';
import 'pending_shares.dart';
import 'sync_status.dart';

/// Who is signed in, as far as the sync needs to know — answered by the session,
/// which sits layers above the sync and is handed in by the composition root.
abstract interface class SyncSession {
  /// `null` while nobody is signed in: then there is nothing to sync.
  String? get memberId;

  String? get deviceId;

  /// The server says the token is dead: off to the sign-in.
  Future<void> signedOutElsewhere();

  /// A backup restore began (`true`) or ended (`false`) on the server — said by the
  /// event stream, or by a change it refused meanwhile.
  void restoreRunning({required bool running});

  /// Makes the local data the signed-in member's — cleared first if it belongs to
  /// someone else. Done before every sync writes into it.
  Future<void> claimLocalData();
}

/// What a repository needs from the sync: a nudge after writing to the outbox.
abstract interface class SyncTrigger {
  Future<void> syncNow();
}

/// Sync: push, then pull.
///
/// ```
/// input → local DB (visible immediately) → outbox → push → change_log → pull → other devices
/// ```
///
/// There is no "Saving, please wait" and no loading interruption after typing.
class SyncEngine implements SyncTrigger {
  /// [runningElsewhere] asks whether a background run pushes the same outbox right
  /// now; [onPendingChanged] hears every change of the number of waiting changes —
  /// the composition root hangs the background job and the browser's leave guard on
  /// it.
  SyncEngine({
    required this._api,
    required this._db,
    required this._outbox,
    required this._pendingShares,
    required this._session,
    this._runningElsewhere,
    this._onPendingChanged,
  }) {
    // The number of waiting changes comes from the database; it survives a restart,
    // and that is exactly the promise.
    _pending = _outbox.watchPendingCount().listen((count) {
      if (count != state.pending) state = state.copyWith(pending: count);
      _onPendingChanged?.call(count);
    });
  }

  static const _codecs = entityCodecs;

  /// What a restore leaves behind is kept, not thrown away with the mirror.
  late final LeftBehind leftBehind = LeftBehind(_db);

  final HiwiskiApi _api;
  final HiwiskiDatabase _db;
  final Outbox _outbox;
  final PendingShares _pendingShares;
  final SyncSession _session;
  final Future<bool> Function()? _runningElsewhere;
  final void Function(int pending)? _onPendingChanged;

  late final StreamSubscription<int> _pending;
  final _changes = StreamController<SyncStatus>.broadcast();
  SyncStatus _state = const SyncStatus();

  Timer? _backoff;
  bool _running = false;
  bool _again = false;

  /// Completes when the engine is idle again: after the run in progress and the one
  /// requested during it.
  Completer<void>? _idle;

  /// Bumped by [stop]. A run compares it with the value it started under after every
  /// answer and gives up once it differs — it no longer writes for whoever left.
  int _epoch = 0;
  int _runEpoch = 0;
  EventStream? _events;
  StreamSubscription<int>? _signal;

  /// Where the sync stands right now.
  SyncStatus get state => _state;

  @protected
  set state(SyncStatus value) {
    _state = value;
    if (!_changes.isClosed) _changes.add(value);
  }

  /// Every change of [state], from now on.
  Stream<SyncStatus> get changes => _changes.stream;

  Future<void> dispose() async {
    _epoch++;
    _signalGeneration++;
    _backoff?.cancel();
    _reconnect?.cancel();
    await _signal?.cancel();
    _events?.close();
    await _pending.cancel();
    await _changes.close();
  }

  /// One run: out first, then in.
  ///
  /// In this order, because otherwise a pull would overwrite the device's own changes
  /// that have not been transmitted yet — and `resync_required` explicitly demands it:
  /// "The client first tries to push its outbox."
  ///
  /// **Done means done.** While a run is in progress, a call asks for one more right
  /// after it and completes when both are over. It used to return at once, and whoever
  /// awaited it as "synced" was wrong: a sign-out then wiped the device while the run
  /// was still writing, and the change that asked for the next run was never pushed.
  @override
  Future<void> syncNow() async {
    if (_idle case final idle? when _running) {
      // Whoever creates something during a run should not wait for the next occasion:
      // one more right after.
      _again = true;
      return idle.future;
    }
    if (_session.memberId == null) return;

    _running = true;
    final idle = _idle = Completer<void>();
    final epoch = _epoch;
    Object? failure;
    StackTrace? trace;
    bool signedOut = false;
    try {
      do {
        _again = false;
        try {
          signedOut = await _runOnce();
        } catch (error, stack) {
          failure ??= error;
          trace ??= stack;
        }
      } while (_again &&
          !signedOut &&
          epoch == _epoch &&
          _session.memberId != null);
    } finally {
      _running = false;
      idle.complete();
    }
    // After the run, not inside it: signing out stops the engine and waits for it.
    if (signedOut) await _session.signedOutElsewhere();
    if ((failure, trace) case (final failure?, final trace?)) {
      Error.throwWithStackTrace(failure, trace);
    }
  }

  /// Ends the sync for whoever is leaving: no retry starts any more, and a run in
  /// progress drops what it gets instead of writing it. Completes once nothing runs —
  /// a sign-out calls it before it clears the device, so nothing is written back
  /// afterwards.
  Future<void> stop() async {
    _epoch++;
    _backoff?.cancel();
    _backoff = null;
    // The stream ran in the name of whoever is leaving; left open, it outlived them
    // until the server dropped it.
    _signalGeneration++;
    _reconnect?.cancel();
    _reconnect = null;
    await _signal?.cancel();
    _signal = null;
    _events?.close();
    _events = null;
    await _idle?.future;
    // A background run writes into the same database from another isolate, which
    // this engine's epoch does not reach: cleared under it, it wrote the departed
    // member's rows and owner back.
    await _awaitElsewhere();
  }

  /// The last run before signing out: after a background run that is pushing the same
  /// outbox right now — a run here would only step aside for it, and the count of what
  /// is still waiting afterwards would name changes as lost that are on their way.
  ///
  /// **No run when nothing waits to go out.** All a run could do then is fetch what
  /// the sign-out clears right after — and with the server out of reach it held the
  /// confirmation and then the sign-out itself up for a connection timeout each,
  /// while the device stayed signed in.
  Future<void> syncLast() async {
    await _awaitElsewhere();
    if (!await _outbox.holdsOutgoing() && !await _pendingShares.waiting()) {
      return;
    }
    await syncNow();
  }

  /// Waits while a background run is under way, at most [_backgroundWait] — iOS gives
  /// one 30 seconds, and a run that never ends must not hold up a sign-out forever.
  Future<void> _awaitElsewhere() async {
    final elsewhere = _runningElsewhere;
    if (elsewhere == null) return;
    final deadline = clock.now().add(_backgroundWait);
    while (clock.now().isBefore(deadline) && await elsewhere()) {
      await Future<void>.delayed(_backgroundPoll);
    }
  }

  static const _backgroundWait = Duration(seconds: 30);
  static const _backgroundPoll = Duration(milliseconds: 500);

  /// Whether a retry is waiting — for the tests.
  @visibleForTesting
  bool get retryScheduled => _backoff?.isActive ?? false;

  /// Throws once [stop] was called during this run.
  void _ensureCurrent() {
    if (_runEpoch != _epoch) throw const _Stopped();
  }

  /// One pass; returns whether the server said the token is dead.
  Future<bool> _runOnce() async {
    _runEpoch = _epoch;
    state = state.copyWith(syncing: true);
    try {
      // A background run is pushing the same outbox right now; it wakes the app when
      // it is done.
      if (await _runningElsewhere?.call() ?? false) return false;
      // **Whose data this is, before any of it is written.** A start on a remembered
      // session syncs before the server has confirmed it; the confirmation then found
      // a mirror without an owner and threw it away — in the browser, whose database
      // starts empty on every load, a reload showed empty lists until something else
      // happened to sync again.
      await _session.claimLocalData();
      _ensureCurrent();
      final owner = await _db.owner;
      await _push();
      await _repairWidgets();
      await _pull();
      if (await _db.owner != owner) {
        // Claimed by someone else meanwhile — from the other isolate, which this
        // isolate's lock does not cover. The pages before that claim were cleared,
        // the position written after it says they are here: a snapshot fetches them.
        await _db.requestSnapshot();
      }
      await _rehomeParked();
      _ensureCurrent();
      // Only now does the server know what was just created.
      await _pendingShares.flush();
      state = state.copyWith(
        online: true,
        lastSyncedAt: clock.now(),
        lastAttemptFailed: false,
      );
      _backoff?.cancel();
      _backoff = null;
      _failedRuns = 0;
    } on _Stopped {
      // Signed out meanwhile: what came back belongs to whoever left.
      return false;
    } on HiwiskiFailure catch (failure) {
      // Signed out from another device: off to the sign-in, not on with a dead token.
      if (failure.isUnauthorized) return true;
      if (failure.code == FailureCodes.instanceRestoring) {
        // Not a failure: the server takes no changes while a backup is restored. The
        // app shows it and waits; the changes stay in the outbox until it is done.
        _session.restoreRunning(running: true);
        if (_runEpoch == _epoch) _scheduleRetry();
        return false;
      }
      if (failure.isNetwork) {
        // An unreachable server is not an error on the go but everyday life.
        state = state.copyWith(online: false);
        if (_runEpoch == _epoch) _scheduleRetry();
      } else {
        // A server restarting after an update answers 503 for a moment. Without a
        // retry nothing pushed the waiting changes until the user edited something
        // again — on a device left alone, for hours.
        if (failure.isTransient && _runEpoch == _epoch) _scheduleRetry();
        state = state.copyWith(lastAttemptFailed: true);
        rethrow;
      }
    } catch (_) {
      // Not the server's answer but something on this side: a field a codec cannot
      // take, a database error. It used to end the run without a word and without a
      // retry — a page that always fails stopped every later run at the same place,
      // and the banner said nothing. Now it says so and tries again with backoff.
      state = state.copyWith(lastAttemptFailed: true);
      if (_runEpoch == _epoch) _scheduleRetry();
      rethrow;
    } finally {
      state = state.copyWith(syncing: false);
      await _refreshCounts();
    }
    return false;
  }

  /// Backoff, doubling up to one minute. Shows nothing.
  ///
  /// It used to be a fixed 15 seconds: a phone offline for a day tried a full sync
  /// four times a minute, and when the server came back every device hit it on the
  /// same beat. The jitter spreads them.
  void _scheduleRetry() {
    _backoff?.cancel();
    final seconds = min(
      _firstRetry.inSeconds << min(_failedRuns, 4),
      _longestRetry.inSeconds,
    );
    _failedRuns++;
    final jitter = _random.nextInt(seconds * 1000 ~/ 5 + 1);
    _backoff = Timer(Duration(milliseconds: seconds * 1000 + jitter), () {
      // The run reports its own failure — banner, next retry; from a timer it would
      // only become an uncaught error.
      syncNow().ignore();
    });
  }

  /// The delay a retry would wait, without jitter — for the tests.
  @visibleForTesting
  Duration get nextRetry => .new(
    seconds: min(
      _firstRetry.inSeconds << min(_failedRuns, 4),
      _longestRetry.inSeconds,
    ),
  );

  static const _firstRetry = Duration(seconds: 15);
  static const _longestRetry = Duration(minutes: 1);
  final _random = Random();

  /// Runs that failed in a row; a successful one starts over.
  int _failedRuns = 0;

  /// Up to this state, sync blanked a tile's kind as soon as only its configuration or
  /// size was changed. That cannot be repaired locally — the kind is only in the
  /// create. So away with such tiles and pull once from scratch; the server has them
  /// right.
  ///
  /// Here and not as a migration: written when all browser tabs shared the database
  /// in a shared worker, where a migration only ran once no old tab held it open.
  /// Each tab now has a database of its own in memory (`connection_web.dart`); the
  /// repair stays for devices that synced before the fix.
  Future<void> _repairWidgets() async {
    final broken = await (_db.delete(
      _db.widgets,
    )..where((w) => w.kind.equals(''))).go();
    if (broken > 0) await _db.requestSnapshot();
  }

  // --- Duplicate board -----------------------------------------------------------

  /// What a parked entry's `errorCode` starts with: `board:<kind>:<orphan>`.
  static const _parkedOnBoard = 'board';

  /// A device that creates its start board before the first sync has brought the
  /// existing one gets `sync.constraint_violated` from the server — there is only one
  /// per kind per member. Rejected, it stayed locally, and **everything that landed on
  /// it afterwards was stuck forever**: every tile waited for a board the server never
  /// accepts (seen in Safari, October 2026).
  Future<bool> _isDuplicateBoard(OutboxRow entry, String? code) async =>
      code == FailureCodes.syncConstraintViolated &&
      entry.entityType == EntityTypes.board &&
      entry.op == SyncOps.upsert &&
      entry.baseVersion == null;

  /// Give up the device's own board, park the work on it and pull once from scratch —
  /// then the server's board is there, and [_rehomeParked] moves everything over.
  Future<void> _parkDuplicateBoard(OutboxRow entry) async {
    final orphan = entry.entityId;
    final board = await (_db.select(
      _db.boards,
    )..where((row) => row.id.equals(orphan))).getSingleOrNull();
    await _db.transaction(() async {
      final widgets = await (_db.select(
        _db.widgets,
      )..where((row) => row.boardId.equals(orphan))).get();
      final widgetIds = [for (final row in widgets) row.id];
      await (_db.update(_db.outboxEntries)..where(
            (row) =>
                row.containerId.equals(orphan) | row.entityId.isIn(widgetIds),
          ))
          .write(
            OutboxEntriesCompanion(
              state: const Value(OutboxStates.parked),
              // Where to move it to is on the entry: the board's kind.
              errorCode: Value(
                '$_parkedOnBoard:${board?.kind ?? BoardKinds.start}:$orphan',
              ),
            ),
          );
      await (_db.update(_db.outboxEntries)
            ..where((row) => row.dependsOn.equals(entry.mutationId)))
          .write(const OutboxEntriesCompanion(dependsOn: Value(null)));
      await _outbox.remove(entry.mutationId);
      await (_db.delete(
        _db.boards,
      )..where((row) => row.id.equals(orphan))).go();
    });
    await _db.requestSnapshot();
  }

  Future<void> _rehomeParked() async {
    final parked = await (_db.select(
      _db.outboxEntries,
    )..where((row) => row.state.equals(OutboxStates.parked))).get();
    if (parked.isEmpty) return;
    bool moved = false;
    for (final entry in parked) {
      final parts = (entry.errorCode ?? '').split(':');
      final target = parts.length != 3
          ? null
          : await (_db.select(_db.boards)..where(
                  (row) => row.kind.equals(parts[1]) & row.deletedAt.isNull(),
                ))
                .getSingleOrNull();
      if (target == null) {
        // Not there yet — try again on the next regular run, not right away. After
        // enough runs without a board of that kind it will not come: the entry is
        // given up and shown, instead of being asked about forever.
        await _outbox.countAttempt(entry.mutationId);
        if (entry.attempts + 1 >= _parkedRuns) {
          await _outbox.reject(entry.mutationId, FailureCodes.syncBoardGone);
        }
        continue;
      }
      final orphan = parts[2];
      moved = true;
      await _db.transaction(() async {
        await (_db.update(_db.widgets)
              ..where((row) => row.boardId.equals(orphan)))
            .write(WidgetsCompanion(boardId: Value(target.id)));
        await (_db.update(
          _db.outboxEntries,
        )..where((row) => row.mutationId.equals(entry.mutationId))).write(
          OutboxEntriesCompanion(
            state: const Value(OutboxStates.pending),
            errorCode: const Value(null),
            containerId: entry.containerId == orphan
                ? Value(target.id)
                : const Value.absent(),
          ),
        );
      });
    }
    // Only when something moved: "one more run" for nothing synced back to back,
    // for as long as the device was online — and after every restart again.
    if (moved) _again = true;
  }

  /// Mutations per push — the server takes up to 200.
  static const _pushBatch = 50;

  /// A `400` or `413` on the push itself that is about the request — too many
  /// mutations, a body too large or one the server could not read: the batch, not
  /// one of its mutations. Other codes (a device the server does not know) are no
  /// reason to take the outbox apart.
  static bool _refusesTheBatch(HiwiskiFailure failure) =>
      (failure.status == 400 || failure.status == 413) &&
      (failure.code == FailureCodes.requestInvalid ||
          failure.code == FailureCodes.requestTooLarge);

  /// How many runs a parked entry waits for its board before it is given up.
  static const _parkedRuns = 20;

  // --- Push --------------------------------------------------------------------

  Future<void> _push() async {
    final deviceId = _session.deviceId;
    if (deviceId == null) return;

    int limit = _pushBatch;
    while (true) {
      final entries = await _outbox.pending(limit: limit);
      if (entries.isEmpty) return;
      // A value beyond the server's limit does not go out — "Try again" made it
      // pending once more. Held, it waits for a change that shortens it.
      final oversized = [
        for (final entry in entries)
          if (SyncLimits.exceeded(
                jsonDecode(entry.fields) as Map<String, dynamic>,
              ) !=
              null)
            entry,
      ];
      if (oversized.isNotEmpty) {
        for (final entry in oversized) {
          await _outbox.hold(entry.mutationId);
        }
        continue;
      }

      final mutations = [
        for (final entry in entries)
          Mutation(
            mutationId: entry.mutationId,
            entityType: entry.entityType,
            entityId: entry.entityId,
            op: entry.op == SyncOps.delete
                ? MutationOp.delete
                : MutationOp.upsert,
            containerType: entry.containerType,
            containerId: entry.containerId,
            baseVersion: entry.baseVersion,
            fields: jsonDecode(entry.fields) as Map<String, dynamic>,
          ),
      ];

      final PushResponse response;
      try {
        response = await HiwiskiApi.run(
          () => _api.sync.push(
            body: PushRequest(
              deviceId: deviceId,
              pendingCount: entries.length,
              mutations: mutations,
            ),
          ),
        );
      } on HiwiskiFailure catch (failure) {
        if (!_refusesTheBatch(failure)) rethrow;
        _ensureCurrent();
        // The push as a whole was refused — too many mutations or too large a body.
        // Sent again unchanged it fails at every run, and the
        // run never reached its pull: the device stopped receiving changes too.
        // Halved until it goes through; a single mutation still refused is
        // rejected visibly, like any other rejection.
        if (entries.length > 1) {
          limit = (entries.length + 1) ~/ 2;
        } else {
          await _outbox.reject(entries.single.mutationId, failure.code);
        }
        continue;
      }

      _ensureCurrent();
      for (final result in response.results) {
        await _applyResult(result);
      }
      if (entries.length < limit) return;
      // A full batch goes on with the next one — unless nothing of it left the
      // queue: a status this version does not know, or a mutation the answer left
      // out. The same 50 would otherwise go out back to back forever, and the run
      // would never reach the pull. They wait for the next run instead.
      final still = {
        for (final entry in await _outbox.pending(limit: limit))
          entry.mutationId,
      };
      if (entries.every((entry) => still.contains(entry.mutationId))) return;
    }
  }

  /// For tests: apply a result without a server answering.
  @visibleForTesting
  Future<void> applyResult(MutationResult result) => _applyResult(result);

  Future<void> _applyResult(MutationResult result) async {
    switch (result.status) {
      case .applied:
      case .duplicate:
        // `duplicate` counts as success: the retry had the same effect.
        await _rememberVersion(result);
        await _outbox.remove(result.mutationId);
      case .conflict:
        await _rememberVersion(result);
        await _recordConflict(result);
        await _takeServerValues(result);
        await _outbox.remove(result.mutationId);
      case .rejected:
        final entry =
            await (_db.select(_db.outboxEntries)
                  ..where((row) => row.mutationId.equals(result.mutationId)))
                .getSingleOrNull();
        // Parked, because the board below it is being moved right now: the rejection
        // in the same run is a consequence of that, not an error of its own.
        if (entry?.state == OutboxStates.parked) break;
        if (entry != null && await _isDuplicateBoard(entry, result.code)) {
          await _parkDuplicateBoard(entry);
          break;
        }
        // Permanently rejected: blocks the chain and becomes visible — not as a
        // silent loss.
        await _outbox.reject(result.mutationId, result.code);
        if (entry != null &&
            (result.code ?? '').startsWith(FailureCodes.accessPrefix)) {
          await _rollBack(entry);
        }
      default:
        // A status this app version does not know. Leaving it and trying again on
        // the next run is the only safe answer.
        await _outbox.countAttempt(result.mutationId);
    }
  }

  /// Undoes locally what the server refused for lack of permission.
  ///
  /// The change was applied to the local database right away — that is the promise of
  /// the outbox. Refused for good, it would otherwise stay on this device: a tag that only
  /// the reader sees, under a notice that says it was not allowed. A new item is removed,
  /// since the server never had it; for a change or a deletion the next pull is a
  /// snapshot, which writes the server's state over every visible item.
  Future<void> _rollBack(OutboxRow entry) async {
    if (entry.op == SyncOps.upsert && entry.baseVersion == null) {
      final codec = _codecs
          .where((candidate) => candidate.entityType == entry.entityType)
          .firstOrNull;
      await codec?.purge(_db, entry.entityId);
    } else {
      await _db.requestSnapshot();
    }
  }

  /// Remembers the version set by the server and the readable key.
  ///
  /// The key comes exactly once, on the first sync — before that the UI shows a
  /// dash.
  Future<void> _rememberVersion(MutationResult result) async {
    final entityId = result.entityId;
    final version = result.version;
    if (entityId == null || version == null) return;

    await (_db.update(
      _db.todos,
    )..where((row) => row.id.equals(entityId))).write(
      TodosCompanion(
        version: Value(version),
        entityKey: result.entityKey == null
            ? const Value.absent()
            : Value(result.entityKey),
      ),
    );
    await (_db.update(
      _db.todoLists,
    )..where((row) => row.id.equals(entityId))).write(
      TodoListsCompanion(
        version: Value(version),
        entityKey: result.entityKey == null
            ? const Value.absent()
            : Value(result.entityKey),
      ),
    );
    await (_db.update(_db.todoOccurrences)
          ..where((row) => row.id.equals(entityId)))
        .write(TodoOccurrencesCompanion(version: Value(version)));
  }

  Future<void> _recordConflict(MutationResult result) async {
    final fields = result.conflictFields ?? const [];
    if (fields.isEmpty) return;

    final entry =
        await (_db.select(_db.outboxEntries)
              ..where((row) => row.mutationId.equals(result.mutationId)))
            .getSingleOrNull();
    final mine = entry == null
        ? const {}
        : jsonDecode(entry.fields) as Map<String, dynamic>;

    for (final field in fields) {
      await _db
          .into(_db.conflicts)
          .insertOnConflictUpdate(
            ConflictRow(
              id: '${result.entityId}:$field',
              entityType: entry?.entityType ?? '',
              entityId: result.entityId?.toString() ?? '',
              field: field,
              mine: jsonEncode(mine[field]),
              theirs: jsonEncode((result.serverFields ?? const {})[field]),
              base: switch (result.baseFields) {
                final Map<String, dynamic> base when base.containsKey(field) =>
                  jsonEncode(base[field]),
                _ => null,
              },
              detectedAt: clock.now(),
            ),
          );
    }
  }

  /// Sets the discarded fields locally to the server state.
  ///
  /// The server did not accept the device's own change to these fields, but the local
  /// row still carries it. And the pull does not bring the server state back: the
  /// other device's change is older than the local state and was pulled long ago.
  /// Without this step this device would permanently see something different from all
  /// the others. The device's own version is not lost by this — it sits in the
  /// conflict (and for wiki text also as a conflict revision on the server).
  Future<void> _takeServerValues(MutationResult result) async {
    final fields = result.conflictFields ?? const [];
    final entityId = result.entityId;
    final version = result.version;
    if (fields.isEmpty || entityId == null || version == null) return;

    final entry =
        await (_db.select(_db.outboxEntries)
              ..where((row) => row.mutationId.equals(result.mutationId)))
            .getSingleOrNull();
    final codec = _codecs
        .where((candidate) => candidate.entityType == entry?.entityType)
        .firstOrNull;
    if (codec == null) return;

    final server = result.serverFields ?? const {};
    await codec.upsert(
      _db,
      id: entityId,
      ownerId: await codec.localOwner(_db, entityId) ?? _session.memberId ?? '',
      version: version,
      containerId: await codec.containerOf(_db, entityId),
      entityKey: result.entityKey,
      fields: {for (final field in fields) field: server[field]},
    );
  }

  // --- Pull --------------------------------------------------------------------

  Future<void> _pull() async {
    final deviceId = _session.deviceId;
    if (deviceId == null) return;

    // A device without a state fetches the state, not the history: the log is cleaned
    // up after the retention period, and replayed from 0 it would lack everything
    // nobody has touched since.
    if (await _db.lastSeq == 0 || await _db.snapshotFrom != null) {
      await _snapshot();
    }

    // A share takes effect retroactively: the prior history lies *before* the local
    // state. If an `access_granted` comes in this run, the state is pulled once
    // afterwards — then the same filter also delivers what was not visible before.
    bool grantSeen = false;

    while (true) {
      final lastSeq = await _db.lastSeq;
      final pending = await _outbox.pending(limit: 1000);

      final response = await HiwiskiApi.run(
        () => _api.sync.pull(
          body: PullRequest(
            lastSeq: lastSeq,
            deviceId: deviceId,
            pendingCount: pending.length,
          ),
        ),
      );

      _ensureCurrent();
      if (response.resyncRequired) {
        await _resync(response);
        return;
      }
      if (await _rememberInstance(response.instanceId)) {
        // A restore: this page belongs to sequence numbers that no longer exist as such.
        await _snapshot();
        continue;
      }

      // One transaction per page, like the snapshot: every change on its own was a
      // commit of its own, and every commit re-ran every query watching its table — 300
      // tasks from someone else meant 300 times all tasks and the whole link index.
      await _db.transaction(() async {
        for (final change in response.changes) {
          if (change.op == .accessGranted) grantSeen = true;
          await _applyChange(change);
        }
        await _db.setLastSeq(response.latestSeq);
      });

      if (!response.hasMore) break;
    }

    if (grantSeen) {
      // Once, not in a loop: on the second run the new items are already there, and
      // there can be no further `access_granted` there.
      await _db.requestSnapshot();
      await _snapshot();
      await _pullPages();
    }
  }

  /// The state instead of the history: every visible item once, with all fields.
  ///
  /// Afterwards the log continues from [HiwiskiDatabase.snapshotFrom] — the device's
  /// previous state or, on a fresh device, the state at the start of the snapshot.
  /// Whatever happened during the snapshot thus comes again, in log order, and ends up
  /// on the right end.
  Future<void> _snapshot() async {
    final deviceId = _session.deviceId;
    if (deviceId == null) return;

    int from = await _db.snapshotFrom ?? await _db.lastSeq;
    String? cursor;
    final pending = (await _outbox.pending(limit: 1000)).length;
    while (true) {
      final response = await HiwiskiApi.run(
        () => _api.sync.pull(
          body: PullRequest(
            lastSeq: 0,
            deviceId: deviceId,
            pendingCount: pending,
            snapshot: true,
            snapshotCursor: cursor,
          ),
        ),
      );
      _ensureCurrent();
      // A new instance discards the mirror along with its state; then the snapshot's
      // state counts.
      if (await _rememberInstance(response.instanceId)) {
        from = 0;
        if (cursor != null) {
          // Noticed on a later page: the pages before were the old instance's and went
          // with the mirror. Going on from this cursor left them missing until someone
          // asked for another snapshot — so it starts over.
          cursor = null;
          continue;
        }
      }
      if (from == 0) from = response.latestSeq;
      await _db.setSnapshotFrom(from);

      await _db.transaction(() async {
        for (final change in response.changes) {
          await _applyChange(change);
        }
      });

      cursor = response.snapshotCursor;
      // Without a cursor it cannot go on — not even if a server that does not know the
      // snapshot reports `hasMore`. Otherwise it would pull the same page forever.
      if (!response.hasMore || cursor == null) break;
    }
    await _db.finishSnapshot(from);
    // The restored state is complete: now it shows what it does not have.
    await leftBehind.settle();
  }

  /// Pulls page by page without reacting to shares.
  Future<void> _pullPages() async {
    final deviceId = _session.deviceId;
    if (deviceId == null) return;

    while (true) {
      final lastSeq = await _db.lastSeq;
      final response = await HiwiskiApi.run(
        () => _api.sync.pull(
          body: PullRequest(
            lastSeq: lastSeq,
            deviceId: deviceId,
            pendingCount: 0,
          ),
        ),
      );
      _ensureCurrent();
      // The same checks as the main loop: a restore or a cleaned-up log can land in
      // the same moment as a share. Without them the catch-up applied the new
      // instance's changes onto the old mirror and stored their position, and the
      // resync the main loop would have done never came.
      if (response.resyncRequired) {
        await _resync(response);
        return;
      }
      if (await _rememberInstance(response.instanceId)) {
        await _snapshot();
        continue;
      }
      await _db.transaction(() async {
        for (final change in response.changes) {
          await _applyChange(change);
        }
        await _db.setLastSeq(response.latestSeq);
      });
      if (!response.hasMore) return;
    }
  }

  /// The server has changed the instance identifier — a restore.
  ///
  /// Without this identifier devices would silently keep working on a state that no
  /// longer exists: the worst data loss imaginable in this app.
  ///
  /// Returns whether the mirror was discarded because of it.
  Future<bool> _rememberInstance(String instanceId) async {
    final known = await _db.instanceId;
    if (known == null) {
      await _db.setInstanceId(instanceId);
    } else if (known != instanceId) {
      // A copy is kept before the mirror goes: this device may have seen more than
      // the restored server has.
      await leftBehind.capture();
      await _db.setInstanceId(instanceId);
      await _db.discardMirroredData();
      return true;
    }
    return false;
  }

  /// Get rid of the outbox first, then discard locally and reload.
  ///
  /// Whatever is rejected stays in the visible list to copy from instead of silently
  /// disappearing.
  Future<void> _resync(PullResponse response) async {
    state = state.copyWith(resyncRequired: true);
    try {
      await _push();
      // A restore tells the device so: its mirror goes, a copy of it stays.
      if (await _db.instanceId != response.instanceId) {
        await leftBehind.capture();
      }
      await _db.discardMirroredData();
      await _db.setInstanceId(response.instanceId);
    } finally {
      // The flag says a resync is under way, not that one is still owed: when the push
      // fails offline, the next run hears `resync_required` again and sets it again.
      // Left set, the state claimed a resync for as long as the device stayed offline.
      state = state.copyWith(resyncRequired: false);
    }
    await _pull();
  }

  Future<void> _applyChange(ChangeEnvelope change) async {
    final codec = _codecs
        .where((candidate) => candidate.entityType == change.entityType)
        .firstOrNull;
    if (codec == null) {
      // An old app skips unknown types and does a full resync once after an update.
      return;
    }
    switch (change.op) {
      case .delete:
        await codec.markDeleted(_db, change.entityId, change.version);
      case .accessRevoked:
        // No tombstone: the item is not deleted, it just no longer belongs to what I
        // may see. A `deleted_at` would come back later and claim someone deleted
        // it.
        await codec.purge(_db, change.entityId);
      case .accessGranted:
        // Carries no data. The full catch-up happens in `_pull`.
        break;
      default:
        await codec.upsert(
          _db,
          id: change.entityId,
          // Delivered by the server; an older one does not, and then it stays as before
          // — the reader's own id only for an item the device does not have yet. Taken
          // for every row, it made someone else's shared item look like the reader's.
          ownerId:
              change.ownerId ??
              await codec.localOwner(_db, change.entityId) ??
              _session.memberId ??
              '',
          version: change.version,
          containerId: change.containerId,
          entityKey: change.entityKey,
          fields: change.fields ?? const {},
        );
    }
  }

  /// Hooks into the real-time stream and pulls on every signal.
  ///
  /// The ticket can be redeemed once; if the connection drops, a new one is fetched. A
  /// missed signal cannot break anything — it only triggers a pull that every startup
  /// and every change of one's own triggers anyway.
  Future<void> listenForSignals() async {
    // Only the newest call connects. Two calls overlapping while they waited for a
    // ticket both connected, the first stream was overwritten without being closed, and
    // its end later tore down the current one through the reconnect.
    final generation = ++_signalGeneration;
    _reconnect?.cancel();
    _reconnect = null;
    await _signal?.cancel();
    _signal = null;
    _events?.close();
    _events = null;

    if (_session.memberId == null) return;

    try {
      final ticket = await HiwiskiApi.run(() => _api.sync.createEventTicket());
      if (generation != _signalGeneration) return;
      final stream = EventStream();
      _events = stream;
      _signal = stream
          .connect(
            baseUrl: _api.baseUrl,
            ticket: ticket.ticket,
            onRestoring: (running) => _session.restoreRunning(running: running),
          )
          .listen(
            (seq) =>
                // The sync reports its own failures: banner, retry.
                syncNow().ignore(),
            onError: (Object error) {
              if (generation != _signalGeneration) return;
              if (error is! StreamRevoked) return _reconnectLater(generation);
              // Signing out reports itself; nothing waits for it here.
              _revoked().ignore();
            },
            onDone: () => _reconnectLater(generation),
          );
    } on HiwiskiFailure catch (failure) {
      if (generation != _signalGeneration) return;
      if (failure.isUnauthorized) {
        await _revoked();
        return;
      }
      // No stream does not mean no sync: without a signal it pulls at startup, after
      // each of its own changes and on backoff.
      _reconnectLater(generation);
    }
  }

  /// Bumped by every [listenForSignals]: a stream from an older call ignores its end.
  int _signalGeneration = 0;

  /// The pending reconnect — kept, so a newer connect and [dispose] can cancel it.
  Timer? _reconnect;

  /// The server says this device is out: straight to the sign-in.
  Future<void> _revoked() async {
    _signalGeneration++;
    await _signal?.cancel();
    _signal = null;
    _events?.close();
    _events = null;
    await _session.signedOutElsewhere();
  }

  void _reconnectLater(int generation) {
    if (generation != _signalGeneration) return;
    if (_session.memberId == null) return;
    _signal?.cancel();
    _signal = null;
    _events?.close();
    _events = null;
    _reconnect?.cancel();
    _reconnect = Timer(
      const Duration(seconds: 20),
      () =>
          // A failed reconnect schedules the next one itself.
          listenForSignals().ignore(),
    );
  }

  // --- Conflicts -----------------------------------------------------------------

  /// "Apply anyway": send the device's own discarded version once more — now on the
  /// state that caused the conflict. That makes it a deliberate decision and no longer
  /// a race, and the server accepts it.
  Future<void> takeMine(ConflictRow conflict) async {
    final codec = _codecs
        .where((candidate) => candidate.entityType == conflict.entityType)
        .firstOrNull;
    if (codec == null) {
      await dismissConflict(conflict);
      return;
    }

    final id = conflict.entityId;
    final fields = {
      conflict.field: switch (conflict.mine) {
        null => null,
        final mine => jsonDecode(mine),
      },
    };
    await _db.transaction(() async {
      final version = await codec.localVersion(_db, id);
      if (version == null) {
        return; // Deleted or no longer shared in the meantime.
      }
      await codec.upsert(
        _db,
        id: id,
        ownerId: await codec.localOwner(_db, id) ?? _session.memberId ?? '',
        version: version,
        containerId: await codec.containerOf(_db, id),
        entityKey: null,
        fields: fields,
      );
      await _outbox.add(
        entityType: conflict.entityType,
        entityId: id,
        op: SyncOps.upsert,
        fields: fields,
        baseVersion: version == 0 ? null : version,
        dependsOn: await _outbox.lastPendingFor(id),
      );
      await (_db.delete(
        _db.conflicts,
      )..where((row) => row.id.equals(conflict.id))).go();
    });
    await _refreshCounts();
    // The run reports its own failure: banner, retry.
    syncNow().ignore();
  }

  /// Seen, and the server state accepted.
  Future<void> dismissConflict(ConflictRow conflict) async {
    await (_db.delete(
      _db.conflicts,
    )..where((row) => row.id.equals(conflict.id))).go();
    await _refreshCounts();
  }

  /// Recounts the stuck entries and conflicts.
  ///
  /// Public, because the list of rejected entries asks for it: whoever discards there
  /// wants to see the message disappear immediately and not only on the next sync.
  Future<void> refreshCounts() => _refreshCounts();

  Future<void> _refreshCounts() async {
    final stuck =
        await (_db.select(_db.outboxEntries)..where(
              (entry) => entry.state.isIn([
                OutboxStates.rejected,
                OutboxStates.blocked,
              ]),
            ))
            .get();
    final conflicts = await _db.select(_db.conflicts).get();
    state = state.copyWith(stuck: stuck.length, conflicts: conflicts.length);
  }
}

/// [SyncEngine.stop] was called while a run was under way.
class _Stopped implements Exception {
  const _Stopped();
}
