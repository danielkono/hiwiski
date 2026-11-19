import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/api/hiwiski_failure.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/data/admin/admin_repository.dart';
import 'package:hiwiski/features/admin/trash/view/trash_screen.dart';
import 'package:hiwiski/data/sync/sync_repository.dart';
import 'package:hiwiski/data/todo/todo_repository.dart';
import 'package:hiwiski/domain/todo/todo_items.dart';
import 'package:hiwiski/domain/todo/todo_models.dart';

import 'support/fakes.dart';

/// **An item whose container is gone asks where it should go**.
///
/// The trash showed "Restore" on such an item, and every tap ended in
/// `trash.container_gone`.
void main() {
  TrashEntry entry({required bool restorable}) => .new(
    itemType: 'TODO',
    itemId: 't1',
    title: 'Rasen mähen',
    deletedAt: DateTime(2026, 10, 1),
    remainingDays: 20,
    restorable: restorable,
  );

  const garden = TodoListSummary(
    list: TodoList(
      id: 'garden',
      ownerId: 'anna',
      version: 1,
      name: 'Garten',
      kind: 'STANDARD',
      colorToken: 'green',
      position: 0,
      assignees: '[]',
      tags: '[]',
    ),
    open: 0,
    done: 0,
  );

  Future<_FakeAdmin> pump(WidgetTester tester, TrashEntry trashed) async {
    final admin = _FakeAdmin(trashed);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...quietSync,
          adminRepositoryProvider.overrideWithValue(admin),
          syncRepositoryProvider.overrideWithValue(_FakeSync()),
          familyRepositoryProvider.overrideWithValue(NoFamily()),
          todoRepositoryProvider.overrideWithValue(_FakeTodos([garden])),
        ],
        child: MaterialApp(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: const [
            L.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: TrashScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The retention the server sends, not the administrator's settings.
    expect(find.textContaining('stay here for 7 days'), findsOneWidget);
    return admin;
  }

  testWidgets('restoring an item without its container asks for a target', (
    tester,
  ) async {
    final admin = await pump(tester, entry(restorable: false));

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Restore to'), findsOneWidget);

    await tester.tap(find.text('Garten'));
    await tester.pumpAndSettle();

    expect(admin.restores, equals([('t1', 'garden')]));
  });

  testWidgets('closing the target sheet restores nothing', (tester) async {
    final admin = await pump(tester, entry(restorable: false));

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(admin.restores, isEmpty);
  });

  testWidgets('a container that went away since the list loaded asks too', (
    tester,
  ) async {
    final admin = await pump(tester, entry(restorable: true))
      ..goneOnce = true;

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Garten'));
    await tester.pumpAndSettle();

    expect(admin.restores, equals([('t1', null), ('t1', 'garden')]));
  });
}

class _FakeAdmin implements AdminRepository {
  _FakeAdmin(this.trashed);

  final TrashEntry trashed;
  final restores = <(String, String?)>[];
  bool goneOnce = false;

  @override
  Future<void> restoreFromTrash(
    String itemType,
    String itemId, {
    String? targetContainerId,
  }) async {
    restores.add((itemId, targetContainerId));
    if (goneOnce && targetContainerId == null) {
      goneOnce = false;
      throw const HiwiskiFailure(code: FailureCodes.trashContainerGone);
    }
  }

  @override
  Stream<TrashList> watchTrash() =>
      .value(TrashList(entries: [trashed], retentionDays: 7));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSync implements SyncRepository {
  @override
  Future<void> syncNow() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTodos implements TodoRepository {
  _FakeTodos(this.lists);

  final List<TodoListSummary> lists;

  @override
  Stream<List<TodoListSummary>> watchLists({bool archived = false}) =>
      .value(lists);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
