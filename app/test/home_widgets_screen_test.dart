import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/features/account/home_widgets/view/home_widgets_screen.dart';
import 'package:hiwiski/features/account/view/account_keys.dart';

import 'a11y/a11y_world.dart';

/// Account → Widgets: a widget's settings are saved with "Done" and named in its row.
void main() {
  // Drift's streams run outside the fake clock: each step gives them real time.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 1));
  }

  // Inside the test, not only in its tear-down: the check for pending timers runs before
  // the tear-down does.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets('the agenda is set up with Done', (tester) async {
    final world = (await tester.runAsync(A11yWorld.create))!;
    // Even after a failure: the screen goes first, its streams with it, and only then
    // the database.
    addTearDown(() async {
      await unmount(tester);
      await tester.runAsync(world.close);
    });

    await tester.pumpWidget(
      a11yApp(
        overrides: world.overrides(annaSession),
        home: const HomeWidgetsScreen(),
      ),
    );
    await settle(tester);

    await tester.tap(find.byKey(AccountKeys.homeWidgetRow('agenda')));
    await settle(tester);
    await tester.tap(find.byKey(AccountKeys.homeWidgetDone));
    await settle(tester);

    expect(world.settings.homeWidgets, contains('agenda'));
    expect(find.byKey(AccountKeys.homeWidgetDone), findsNothing);
    expect(find.text('Not set up'), findsNWidgets(3));
    await unmount(tester);
  });

  testWidgets('a shopping list is chosen and saved', (tester) async {
    final world = (await tester.runAsync(A11yWorld.create))!;
    // Even after a failure: the screen goes first, its streams with it, and only then
    // the database.
    addTearDown(() async {
      await unmount(tester);
      await tester.runAsync(world.close);
    });

    await tester.pumpWidget(
      a11yApp(
        overrides: world.overrides(annaSession),
        home: const HomeWidgetsScreen(),
      ),
    );
    await settle(tester);

    await tester.tap(find.byKey(AccountKeys.homeWidgetRow('shopping')));
    await settle(tester);
    await tester.tap(find.byKey(AccountKeys.homeWidgetList));
    await settle(tester);
    await tester.tap(find.byType(DropdownMenuItem<String>).last);
    await settle(tester);
    await tester.tap(find.byKey(AccountKeys.homeWidgetDone));
    await settle(tester);

    expect(world.settings.homeWidgets, contains('shopping'));
    expect(find.byKey(AccountKeys.homeWidgetDone), findsNothing);
    await unmount(tester);
  });
}
