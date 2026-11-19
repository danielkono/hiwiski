import 'dart:async';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/common/wire.dart';
import '../core/sync/outbox.dart';
import '../data/home_widgets/home_widget_repository.dart';
import '../domain/home_widgets/home_widget_settings.dart';
import '../domain/home_widgets/home_widget_snapshots.dart';
import '../domain/session/session_state.dart';
import 'data_providers.dart';
import 'repositories.dart';
import 'stores.dart';

part 'home_widgets.g.dart';

/// Keeps the home screen widgets in step with this device: the settings, the app's
/// own picture of each widget's content, the session they ask the server with — and
/// nothing of the member once they have left.
///
/// The picture follows the database, not the screens: a tick on the shopping list,
/// an event pulled by the sync, a change that waits to be sent — each redraws the
/// widget, and the widget does not have to ask the server for what the app knows.
/// While the app is closed, the widgets ask the server themselves
/// (`docs/development/home-widgets.md`).
@Riverpod(keepAlive: true)
void homeWidgets(Ref ref) {
  final repository = ref.watch(homeWidgetRepositoryProvider);
  if (!repository.supported) return;
  final publisher = _Publisher(ref, repository);
  ref.onDispose(publisher.close);
  ref.listen(
    sessionProvider,
    (_, session) => publisher.sessionChanged(session),
    fireImmediately: true,
  );
  ref.listen(homeWidgetSettingsProvider, (_, _) => publisher.changed());
}

class _Publisher {
  _Publisher(this._ref, this._repository);

  final Ref _ref;
  final HomeWidgetRepository _repository;

  /// A sync writes many rows in a row; the picture is drawn once after them.
  static const _settle = Duration(seconds: 1);

  /// Who and where the widgets currently show — `null` while they show nothing.
  String? _showing;
  StreamSubscription<void>? _tables;
  Timer? _debounce;

  /// The runs go one after the other: two side by side could leave the older picture
  /// last.
  Future<void> _running = Future.value();

  void close() {
    _debounce?.cancel();
    _tables?.cancel();
  }

  void sessionChanged(SessionState session) {
    switch (session.stage) {
      case .signedIn || .localOnly:
        final key =
            '${session.stage.name}|${session.member?.id}|'
            '${session.serverAddress}';
        if (key != _showing) {
          _showing = key;
          _enqueue(() => _start(session));
        }
      case .signedOut || .noServer || .setupRequired:
        // Signed out, another server: nothing of the member stays on the home screen,
        // nor in the settings.
        _showing = null;
        _stopWatching();
        _enqueue(() => _clear(forget: true));
      case .accessLost:
        // Locked, not cleared: the home screen shows nothing, but whoever signs in again
        // as the same member finds their widgets set up as before.
        _showing = null;
        _stopWatching();
        _enqueue(_clear);
      case .unreachable || .passwordChangeRequired:
        // On the way back in: the widgets keep what they have until it is clear
        // whose they are.
        break;
    }
  }

  /// The settings changed: the widgets get the new ones and the pictures that go
  /// with them, at once.
  void changed() {
    if (_showing != null) _enqueue(_publishAll);
  }

  void _enqueue(AsyncCallback step) {
    final next = _running.then((_) => step());
    _running = next.onError<Object>((error, _) {
      // A widget that is not redrawn keeps its last picture; the next change tries
      // again.
      debugPrint('hiwiski: home screen widgets not updated: $error');
    });
  }

  Future<void> _start(SessionState session) async {
    // Another member's data may have been cleared underneath, settings included.
    _ref.read(homeWidgetStoreProvider).reload();
    if (session.stage == .signedIn) {
      // Only a token stored to stay: without "Stay signed in" the session ends with
      // the app, and the home screen must not go on showing it.
      final token = await _ref.read(tokenStoreProvider).readPersisted();
      if (token == null || session.serverAddress == null) {
        _stopWatching();
        await _clear();
        return;
      }
      await _repository.publishCredentials(
        server: session.serverAddress,
        token: token,
      );
    } else {
      // Without a server the widgets show what the app hands them, and ask nobody.
      await _repository.publishCredentials();
    }
    _watch();
    await _publishAll();
  }

  void _watch() {
    _tables?.cancel();
    final db = _ref.read(databaseProvider);
    _tables = db
        .tableUpdates(
          TableUpdateQuery.onAllTables([
            db.calendars,
            db.events,
            db.todoLists,
            db.todos,
            // A change sent or refused changes whose picture is the newer one.
            db.outboxEntries,
          ]),
        )
        .listen((_) {
          _debounce?.cancel();
          _debounce = Timer(_settle, () => _enqueue(_publishAll));
        });
  }

  void _stopWatching() {
    _debounce?.cancel();
    _tables?.cancel();
    _tables = null;
  }

  Future<void> _clear({bool forget = false}) async {
    if (forget) await _ref.read(homeWidgetStoreProvider).forget();
    await _repository.clear();
  }

  Future<void> _publishAll() async {
    if (_showing == null) return;
    final settings = _ref.read(homeWidgetSettingsProvider);
    await _repository.publishConfig(settings);
    final pending = await _ref.read(outboxProvider).pendingTargets();
    final position = await _ref.read(databaseProvider).lastSeq;
    for (final kind in HomeWidgetKind.values) {
      final config = settings.of(kind);
      if (config == null) {
        await _repository.forget(kind);
      } else if (kind == .agenda) {
        await _publishAgenda(config, pending, position);
      } else {
        await _publishList(kind, config, pending, position);
      }
    }
  }

  Future<void> _publishAgenda(
    HomeWidgetConfig config,
    List<OutboxTarget> pending,
    int position,
  ) async {
    final calendars = _ref.read(calendarRepositoryProvider);
    final agenda = agendaSnapshot(
      events: await calendars.watchEvents().first,
      calendars: await calendars.watchCalendars().first,
      calendarIds: config.calendarIds,
      days: config.days,
      now: clock.now(),
      timeZone: _ref.read(deviceTimeZoneProvider),
      position: position,
    );
    await _repository.publishAgenda(
      config,
      agenda,
      pending: pending.any(
        (target) =>
            target.entityType == EntityTypes.event ||
            target.entityType == EntityTypes.calendar,
      ),
    );
  }

  Future<void> _publishList(
    HomeWidgetKind kind,
    HomeWidgetConfig config,
    List<OutboxTarget> pending,
    int position,
  ) async {
    final listId = config.listId;
    if (listId == null) return;
    final todos = _ref.read(todoRepositoryProvider);
    final list = await todos.watchList(listId).first;
    if (list == null || list.deletedAt != null) {
      await _repository.forget(kind);
      return;
    }
    final summary = listSnapshot(
      list: list,
      todos: await todos.watchTodos(listId, doneLast: false).first,
      columnId: kind == .kanban ? config.columnId : null,
      position: position,
    );
    await _repository.publishList(
      kind,
      config,
      summary,
      pending: pending.any(
        (target) =>
            (target.entityType == EntityTypes.todoList &&
                target.entityId == listId) ||
            (target.containerType == EntityTypes.todoList &&
                target.containerId == listId),
      ),
    );
  }
}
