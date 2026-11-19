import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/app/router.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/core/common/ids.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/domain/calendar/event_draft.dart';
import 'package:hiwiski/domain/todo/kanban.dart';
import 'package:hiwiski/main.dart' as app;

/// Opens every screen once against a fresh instance and checks that each one comes
/// out of its loading state without an error.
///
/// ```sh
/// adb reverse tcp:8095 tcp:8095
/// flutter test integration_test/smoke_test.dart -d <device> \
///   --dart-define=SERVER=http://localhost:8095 --dart-define=USER=… \
///   --dart-define=PASSWORD=…
/// ```
const _server = String.fromEnvironment('SERVER');
const _user = String.fromEnvironment('USER');
const _password = String.fromEnvironment('PASSWORD');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('every screen loads', (tester) async {
    final failures = <String>[];

    /// Pumps until no indeterminate progress indicator is left — or [limit].
    Future<bool> settle({Duration limit = const Duration(seconds: 15)}) async {
      final watch = Stopwatch()..start();
      int quiet = 0;
      while (watch.elapsed < limit) {
        await tester.pump(const Duration(milliseconds: 50));
        final spinning = find
            .byType(LinearProgressIndicator)
            .evaluate()
            .any((e) => (e.widget as ProgressIndicator).value == null);
        quiet = spinning ? 0 : quiet + 1;
        if (quiet >= 10) return true;
      }
      return false;
    }

    void type(Finder field, String text) =>
        tester.widget<TextField>(field).controller!.text = text;
    Future<void> press(Finder button) async {
      FocusManager.instance.primaryFocus?.unfocus();
      tester.widget<ButtonStyleButton>(button).onPressed!();
      await tester.pump(const Duration(milliseconds: 100));
    }

    unawaited(app.main());
    while (find.byType(TextField).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    type(find.byType(TextField).first, _server);
    await press(find.byType(FilledButton).first);
    while (find.byType(TextField).evaluate().length < 2) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(FilledButton).evaluate().length > 1) {
        await press(find.byType(FilledButton).last);
        await tester.pump(const Duration(milliseconds: 300));
      }
    }
    type(find.byType(TextField).at(0), _user);
    type(find.byType(TextField).at(1), _password);
    await press(find.byType(FilledButton).first);

    ProviderContainer container() =>
        ProviderScope.containerOf(tester.element(find.byType(app.HiwiskiApp)));
    final limit = Stopwatch()..start();
    while (limit.elapsed < const Duration(minutes: 2)) {
      await tester.pump(const Duration(milliseconds: 100));
      final status = container().read(syncStatusProvider);
      if (status.lastSyncedAt != null && !status.syncing) break;
    }

    // Something on every screen.
    final todos = container().read(todoRepositoryProvider);
    final checklist = await todos.createList(
      name: 'Weekend',
      kind: ListKinds.standard,
    );
    final todo = await todos.createTodo(listId: checklist, title: 'Mow lawn');
    final shopping = await todos.createList(
      name: 'Groceries',
      kind: ListKinds.shopping,
    );
    await todos.createTodo(listId: shopping, title: 'Milk', amount: 2);
    final board = await todos.createList(
      name: 'Move',
      kind: ListKinds.standard,
    );
    await todos.createTodo(listId: board, title: 'Pack boxes');
    final boardRow = await todos.watchList(board).firstWhere((l) => l != null);
    await todos.convertToKanban(
      boardRow!,
      [
        KanbanColumn(id: newId(), name: 'To do'),
        KanbanColumn(id: newId(), name: 'Done', done: true),
      ],
      [...await todos.watchTodos(board).first],
    );
    final calendars = container().read(calendarRepositoryProvider);
    final calendar = await calendars.createCalendar(
      name: 'Family',
      colorToken: ColorTokens.blue,
    );
    final now = DateTime.now();
    final event = await calendars.createEvent(
      calendarId: calendar,
      draft: EventDraft(
        title: 'Swimming',
        time: TimedEvent(now, now.add(const Duration(hours: 1))),
      ),
    );
    final page = await container()
        .read(wikiRepositoryProvider)
        .createPage(title: 'Packing list');
    await settle();

    final screens = {
      'start': '/',
      'tasks': '/tasks',
      'checklist': '/tasks/list/$checklist',
      'task': '/tasks/list/$checklist/task/$todo',
      'shopping': '/tasks/list/$shopping',
      'kanban': '/tasks/list/$board',
      'new task': '/tasks/new',
      'calendar': '/calendar',
      'event': '/calendar/event/$event',
      'manage calendars': '/calendar/manage',
      'wiki': '/wiki',
      'wiki page': '/wiki?pageId=$page',
      'search': '/search',
      'account': '/account',
      'my account': '/account/me',
      'family': '/account/family',
      'devices': '/account/devices',
      'tags': '/account/tags',
      'categories': '/account/categories',
      'customize': '/account/customize',
      'archive': '/account/archive',
      'trash': '/account/trash',
      'settings': '/account/settings',
      'dashboard': '/account/dashboard',
    };
    final reported = <String>[];
    final original = FlutterError.onError;
    FlutterError.onError = (details) => reported.add(details.toString());
    for (final MapEntry(key: name, value: location) in screens.entries) {
      reported.clear();
      container().read(routerProvider).go(location);
      final settled = await settle();
      final error = reported.isEmpty ? null : reported.first;
      // ignore: avoid_print
      if (error != null) print('DETAILS $name\n$error');
      final problems = [
        if (!settled) 'still loading',
        if (error != null) 'exception: $error',
        if (find.textContaining('could not be reached').evaluate().isNotEmpty)
          'unreachable',
        if (find.textContaining('server had a problem').evaluate().isNotEmpty)
          'server error',
      ];
      // ignore: avoid_print
      print('SMOKE $name: ${problems.isEmpty ? 'ok' : problems.join(', ')}');
      if (problems.isNotEmpty) failures.add('$name: ${problems.join(', ')}');
    }
    FlutterError.onError = original;
    expect(failures, isEmpty);
  });
}
