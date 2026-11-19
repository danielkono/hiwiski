import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show BooleanExpressionOperators, OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/demo.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/components/sharing/view/share_sheet.dart';
import 'package:hiwiski/core/api/generated/export.dart' hide Mutation;
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/data/board/board_repository.dart';
import 'package:hiwiski/data/board/kiosk_repository.dart';
import 'package:hiwiski/domain/board/widget_kinds.dart';
import 'package:hiwiski/domain/common/item_ref.dart';
import 'package:hiwiski/features/calendar/manage_calendars/view/calendar_sheets.dart';
import 'package:hiwiski/features/calendar/view/calendar_keys.dart';
import 'package:hiwiski/features/family/view/invite_sheet.dart';
import 'package:hiwiski/features/wiki/recipe_import/view/recipe_import_sheet.dart';
import 'package:hiwiski/features/wiki/view/wiki_keys.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/routing/routes.dart';
import 'package:hiwiski/domain/session/session_state.dart';

// The scenes: the screens of the app the demo's sample data can show, each where it
// opens and with what a member would have done there. The website's pictures
// (`scene_screenshots_test.dart`) and the store's (`test/store/`) both take them
// from here, so a screen looks the same in both.

/// A screenshot: where it opens, and how high it is (the width is the site's).
///
/// [server]: signed in, with a [SceneServer] behind the app — for what only a server
/// has. [open] then does what a member would on the screen: opens a sheet, fills it
/// in, scrolls to the part shown.
class SceneShot(
  final String name,
  final double height,
  final Future<String> Function(Demo demo, HiwiskiDatabase db) location, {
  final String? calendarView,
  final Future<void> Function(ProviderContainer, Demo, HiwiskiDatabase)?
  prepare,
  final SessionStage stage = .localOnly,
  final double width = sceneWidth,
  final bool server = false,
  final Future<void> Function(WidgetTester tester, Demo demo, L l)? open,
});

const sceneWidth = 720.0;

String _list(Demo demo, String key) =>
    TodoListRoute(listId: demo.idOf(key) ?? '').location;

String _page(Demo demo, String key) =>
    WikiRoute(pageId: demo.idOf(key)).location;

final sceneShots = [
  SceneShot('tasks-overview', 480, (_, _) async => const TodoRoute().location),
  SceneShot(
    'shopping-list',
    560,
    (demo, _) async => _list(demo, 'list:shopping'),
  ),
  SceneShot('task-list', 520, (demo, _) async => _list(demo, 'list:chores')),
  SceneShot(
    'kanban-board',
    520,
    (demo, _) async => _list(demo, 'list:bathroom'),
  ),
  SceneShot('task-detail', 520, (demo, db) async {
    // A task with a description: the tax return in the paperwork.
    final listId = demo.idOf('list:paperwork') ?? '';
    final todo =
        await (db.select(db.todos)
              ..where(
                (t) => t.listId.equals(listId) & t.description.isNotNull(),
              )
              ..limit(1))
            .getSingle();
    return TodoDetailRoute(listId: listId, todoId: todo.id).location;
  }),
  SceneShot(
    'calendar-week',
    560,
    (_, _) async => const CalendarRoute().location,
    calendarView: 'WEEK',
  ),
  SceneShot(
    'calendar-month',
    520,
    (_, _) async => const CalendarRoute().location,
    calendarView: 'MONTH',
  ),
  SceneShot('wiki-page', 560, (demo, _) async => _page(demo, 'page:router')),
  // The phone beside the task overview at the top of the home page.
  SceneShot(
    'wiki-page-phone',
    780,
    (demo, _) async => _page(demo, 'page:router'),
    width: 390,
  ),
  SceneShot('wiki-edit', 560, (demo, _) async => _page(demo, 'page:wifi')),
  SceneShot('recipe', 600, (demo, _) async => _page(demo, 'page:spaetzle')),
  SceneShot('start-board', 560, (_, _) async => const HomeRoute().location),
  SceneShot('search', 520, (_, _) async => const SearchRoute().location),
  SceneShot(
    'archive',
    440,
    (_, _) async => const ArchiveRoute().location,
    // Last summer's holiday and the garden list, done with for the year.
    prepare: (container, demo, _) async {
      final todos = container.read(todoRepositoryProvider);
      for (final key in const ['list:holiday', 'list:gardening']) {
        final list = await todos.watchList(demo.idOf(key) ?? '').first;
        if (list != null) await todos.archiveList(list);
      }
    },
  ),
  SceneShot(
    'server-address',
    520,
    (_, _) async => const ServerAddressRoute().location,
    stage: .noServer,
  ),
  SceneShot(
    'setup-wizard',
    520,
    (_, _) async => const SetupRoute().location,
    stage: .setupRequired,
  ),
  SceneShot(
    'trash',
    440,
    (_, _) async => const TrashRoute().location,
    // Two chores nobody does any more.
    prepare: (container, demo, db) async {
      final todos = container.read(todoRepositoryProvider);
      final listId = demo.idOf('list:chores') ?? '';
      final rows =
          await (db.select(db.todos)
                ..where((t) => t.listId.equals(listId))
                ..orderBy([(t) => OrderingTerm(expression: t.title)])
                ..limit(2))
              .get();
      for (final row in rows) {
        final todo = await todos.watchTodo(row.id).first;
        if (todo != null) await todos.deleteTodo(todo);
      }
    },
  ),
  // What only a server has.
  SceneShot(
    'devices',
    440,
    (_, _) async => const DevicesRoute().location,
    server: true,
  ),
  SceneShot(
    'settings-backup',
    480,
    (_, _) async => const SettingsRoute().location,
    server: true,
    open: (tester, _, l) async {
      await tester.scrollUntilVisible(
        find.text(l.settingsBackupNow),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await _reveal(tester, find.text(l.settingsBackup));
    },
  ),
  SceneShot(
    'sharing',
    480,
    (demo, _) async => _list(demo, 'list:chores'),
    server: true,
    open: (tester, demo, _) async => unawaited(
      showShareSheet(
        _context(tester),
        item: ItemRef.todoList(demo.idOf('list:chores') ?? ''),
      ),
    ),
  ),
  SceneShot(
    'invite',
    620,
    (_, _) async => const FamilyRoute().location,
    server: true,
    open: (tester, _, l) async {
      unawaited(showInviteSheet(_context(tester)));
      await settleScene(tester);
      await tester.tap(find.text(l.inviteCreateSubmit));
    },
  ),
  SceneShot(
    'calendar-subscribe',
    520,
    (_, _) async => const ManageCalendarsRoute().location,
    server: true,
    open: (tester, _, _) async {
      unawaited(showSubscriptionSheet(_context(tester)));
      await settleScene(tester);
      await tester.enterText(
        find.byKey(CalendarKeys.subscriptionUrl),
        'https://www.schulferien.example/baden-wuerttemberg.ics',
      );
      // The preview comes by itself once the address rests.
      await tester.pump(const Duration(seconds: 1));
    },
  ),
  SceneShot(
    'ics-link',
    440,
    (_, _) async => const ManageCalendarsRoute().location,
    server: true,
    prepare: (container, demo, _) async {
      final de = demo.language == 'de';
      final calendars = container.read(calendarRepositoryProvider);
      final all = await calendars.watchCalendars().first;
      final ids = [for (final calendar in all) calendar.id];
      await calendars.createFeed(
        name: de ? 'Familie' : 'Family',
        calendarIds: ids,
        contentMode: FeedContentModes.full,
      );
      await calendars.createFeed(
        name: de ? 'Büro' : 'Office',
        calendarIds: ids.take(1).toList(),
        contentMode: FeedContentModes.busy,
      );
    },
    open: (tester, _, l) => _reveal(tester, find.text(l.calFeeds)),
  ),
  SceneShot(
    'recipe-import',
    760,
    (demo, _) async => _page(demo, 'page:spaetzle'),
    server: true,
    open: (tester, _, l) async {
      unawaited(showRecipeImportSheet(_context(tester), onCreated: (_) {}));
      await settleScene(tester);
      await tester.enterText(
        find.byKey(WikiKeys.recipeUrl),
        'https://rezepte.example/linsensuppe',
      );
      await tester.tap(find.text(l.recipeImportFetch));
    },
  ),
  // On the wall tablet, landscape.
  SceneShot(
    'dashboard',
    800,
    (_, _) async => const KioskRoute(token: _kioskToken).location,
    width: 1280,
    // A board of its own, as one sets it up for the kitchen.
    prepare: (container, demo, _) async {
      final boards = container.read(boardRepositoryProvider);
      final board = await boards.ensure(BoardKinds.dashboard);
      for (final (kind, config) in [
        (WidgetKind.clock.id, <String, Object?>{}),
        (WidgetKind.calendar.id, <String, Object?>{}),
        (
          WidgetKind.shoppingList.id,
          {WidgetConfigKeys.listId: demo.idOf('list:shopping')},
        ),
        (
          WidgetKind.todoList.id,
          {WidgetConfigKeys.listId: demo.idOf('list:chores')},
        ),
      ]) {
        await boards.addWidget(
          board: board,
          kind: kind,
          config: WidgetConfig(config),
          existing: await boards.watchWidgets(board.id).first,
        );
      }
    },
    // The board comes from the database on the real clock.
    open: (_, _, _) async {},
  ),
];

/// The kiosk's address in the dashboard scene; the board is the demo's own.
const _kioskToken = 'scene';

/// Somewhere inside the screen shown — a sheet opens from there.
BuildContext _context(WidgetTester tester) =>
    tester.element(find.byType(Scaffold).last);

/// Brings [target] to the top of the screen.
Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target.first);
  await Scrollable.ensureVisible(tester.element(target.first));
}

Future<void> settleScene(WidgetTester tester) async {
  for (int i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The demo's start board on the wall tablet, the tiles reading the demo's data.
class SceneKiosk implements KioskRepository {
  SceneKiosk(this._boards);

  final BoardRepository _boards;

  @override
  Future<BoardView> publicBoard(String token) async {
    final boards = await _boards.watchBoards().first;
    final board =
        boards.where((b) => b.kind == BoardKinds.dashboard).firstOrNull ??
        boards.first;
    final widgets = await _boards.watchWidgets(board.id).first;
    return BoardView(
      boardId: board.id,
      ownerId: board.ownerId,
      name: board.name,
      layout: .grid,
      columns: board.columns,
      widgets: [
        for (final widget in widgets)
          WidgetView(
            id: widget.id,
            kind: widget.kind,
            gridX: widget.gridX,
            gridY: widget.gridY,
            gridW: widget.gridW,
            gridH: widget.gridH,
            position: widget.position,
            config: jsonDecode(widget.config),
          ),
      ],
    );
  }

  /// The tiles read the scene's own database: the demo's data is already there.
  @override
  Future<void> refreshTiles(String token) async {}

  @override
  Stream<int> changes(String token) => const .empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
