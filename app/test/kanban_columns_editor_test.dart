import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/todo/kanban.dart';
import 'package:hiwiski/features/todo/view/kanban_columns_editor.dart';

/// **Several columns can be done columns** — but one always is, and one always stays
/// open.
void main() {
  const todo = KanbanColumn(id: 'todo', name: 'To do');
  const doing = KanbanColumn(id: 'doing', name: 'Doing');
  const done = KanbanColumn(id: 'done', name: 'Done', done: true);

  Future<void> editor(WidgetTester tester, List<KanbanColumn> initial) async {
    List<KanbanColumn> columns = initial;
    await tester.pumpWidget(
      MaterialApp(
        theme: HiwiskiTheme.light(),
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: KanbanColumnsEditor(
                columns: columns,
                onChanged: (next) => setState(() => columns = next),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconButton mark(WidgetTester tester, String id) =>
      tester.widget(find.byKey(ValueKey('kanban-column-done-$id')));

  testWidgets('a second column becomes a done column, the first stays one', (
    tester,
  ) async {
    await editor(tester, const [todo, doing, done]);
    // The only done column keeps its mark.
    expect(mark(tester, 'done').onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('kanban-column-done-doing')));
    await tester.pump();

    // Both done now — and either may be open again.
    expect(mark(tester, 'done').onPressed, isNotNull);
    expect(mark(tester, 'doing').onPressed, isNotNull);
    // The last open column stays open.
    expect(mark(tester, 'todo').onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('kanban-column-done-done')));
    await tester.pump();
    expect(mark(tester, 'doing').onPressed, isNull);
    expect(mark(tester, 'done').onPressed, isNotNull);
  });
}
