import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/todo/todo_items.dart';
import 'package:hiwiski/features/todo/view/removable_row.dart';
import 'package:hiwiski/features/todo/view/todo_row.dart';

/// **A click on the delete symbol says how to delete** — on the web it went through
/// to the row and opened the task.
void main() {
  testWidgets('a mouse click shows the hint and does not open the task', (
    tester,
  ) async {
    int opened = 0;
    const todo = Todo(
      id: 'todo-1',
      ownerId: 'member-1',
      version: 1,
      listId: 'list-1',
      title: 'Clean windows',
      status: TodoStatuses.open,
      assignees: '[]',
      tags: '[]',
      position: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: HiwiskiTheme.light(),
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: RemovableRow(
            onRemoved: () {},
            child: TodoRowTile(
              todo: todo,
              shopping: false,
              deletable: true,
              onOpen: () => opened++,
            ),
          ),
        ),
      ),
    );

    final symbol = tester.getCenter(
      find.byKey(const ValueKey('delete-todo-todo-1')),
    );
    final mouse = await tester.createGesture(kind: .mouse);
    await mouse.addPointer(location: symbol);
    addTearDown(mouse.removePointer);
    await mouse.down(symbol);
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 300));

    expect(opened, equals(0));
    final l = await L.delegate.load(const Locale('en'));
    expect(find.text(l.todoDeleteHint), findsOneWidget);

    await tester.tap(find.text('Clean windows'));
    expect(opened, equals(1));
  });
}
