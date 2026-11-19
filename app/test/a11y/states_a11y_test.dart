import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'a11y_screens.dart';
import 'a11y_world.dart';
import 'screens_a11y_test.dart' show settle, unmount;

/// **No screen without its empty and its error state**: every
/// screen once for a family that has only just been set up, and once with nothing on
/// the device and the server out of reach. Measured like the screens in use, and
/// never still loading once things have settled — offline, "Loading" forever is the
/// error state nobody built.
///
/// `--dart-define=A11Y_REPORT=true` prints what each one says, to read through.
void main() {
  setUp(mockPlugins);
  tearDown(unmockPlugins);

  const report = bool.fromEnvironment('A11Y_REPORT');
  const variants = [('phone', Size(390, 844)), ('tablet', Size(1280, 800))];

  for (final family in [Family.empty, Family.offline]) {
    for (final MapEntry(key: name, value: (session, build))
        in screenCases.entries) {
      for (final (device, size) in variants) {
        testWidgets('$name — ${family.name}, $device', (tester) async {
          final world = (await tester.runAsync(
            () => A11yWorld.create(session: session, family: family),
          ))!;
          addTearDown(() async {
            await unmount(tester);
            await tester.runAsync(world.close);
          });
          if (name == 'redeem invitation') {
            debugDefaultTargetPlatformOverride = TargetPlatform.linux;
          }
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            a11yApp(overrides: world.overrides(session), home: build(world)),
          );
          await settle(tester);

          if (report) {
            final texts = [
              for (final text in tester.widgetList<Text>(find.byType(Text)))
                ?text.data ?? text.textSpan?.toPlainText(),
            ].where((text) => text.trim().isNotEmpty).toSet();
            // ignore: avoid_print
            print(
              'REPORT $name | ${family.name} | $device | ${texts.join(' ¦ ')}',
            );
          }
          try {
            // Without a value: something still loading. With one it is a step
            // counter, like the set-up's.
            expect(
              find.byWidgetPredicate(
                (widget) => widget is ProgressIndicator && widget.value == null,
              ),
              findsNothing,
              reason: 'still loading after everything has answered',
            );
            if (family == .empty) expect(world.server.unknown, isEmpty);
            await expectAccessible(tester);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
          await unmount(tester);
        });
      }
    }
  }
}
