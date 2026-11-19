import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/ui/new_row_reveal.dart';

/// **A row just added comes into view** — also at the end of a long list whose rows
/// are built as they come into view.
void main() {
  Future<void> pumpList(
    WidgetTester tester,
    List<String> ids,
    NewRowReveal reveal,
    ScrollController scroll,
  ) async {
    reveal.reveal(
      ids,
      position: () => scroll.hasClients ? scroll.position : null,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: scroll,
          itemCount: ids.length,
          itemBuilder: (context, index) => SizedBox(
            key: reveal.keyOf(ids[index]),
            height: 60,
            child: Text(ids[index]),
          ),
        ),
      ),
    );
  }

  testWidgets('the new row at the end is scrolled to', (tester) async {
    final reveal = NewRowReveal();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final ids = [for (int i = 0; i < 100; i++) 'row $i'];
    await pumpList(tester, ids, reveal, scroll);
    expect(find.text('row 99'), findsNothing);

    reveal.expect(ids);
    await pumpList(tester, [...ids, 'new'], reveal, scroll);
    await tester.pumpAndSettle();

    expect(find.text('new'), findsOneWidget);
  });

  testWidgets('a row "Undo" brings back is scrolled to', (tester) async {
    final reveal = NewRowReveal();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final ids = [for (int i = 0; i < 100; i++) 'row $i'];
    await pumpList(tester, [...ids]..remove('row 90'), reveal, scroll);
    expect(find.text('row 90'), findsNothing);

    reveal.expectBack(['row 90']);
    await pumpList(tester, ids, reveal, scroll);
    await tester.pumpAndSettle();

    expect(find.text('row 90'), findsOneWidget);
  });

  testWidgets('a row from elsewhere is not followed', (tester) async {
    final reveal = NewRowReveal();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final ids = [for (int i = 0; i < 100; i++) 'row $i'];
    await pumpList(tester, ids, reveal, scroll);

    await pumpList(tester, [...ids, 'synced'], reveal, scroll);
    await tester.pumpAndSettle();

    expect(scroll.offset, equals(0));
  });
}
