import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'a11y_screens.dart';
import 'a11y_world.dart';

/// **Every screen measured** ("accessibility measured"): contrast, tap targets
/// and labels, light and dark, on a phone and on a tablet — each with data in it,
/// since an empty screen hides most of what can fail.
void main() {
  setUp(mockPlugins);
  tearDown(unmockPlugins);

  final screens = screenCases;

  // The camera frame has no controls of its own, and a test has no camera: the
  // page is measured where the app drops the frame.
  const withoutCamera = {'redeem invitation'};

  // Light and dark on both sizes; on the phone also at 200 % text, the largest
  // most phones offer — what fits at 100 % has to fit there too.
  const variants = [
    ('phone, light', Size(390, 844), Brightness.light, 1.0),
    ('phone, dark', Size(390, 844), Brightness.dark, 1.0),
    ('phone, 200 % text', Size(390, 844), Brightness.light, 2.0),
    ('tablet, light', Size(1280, 800), Brightness.light, 1.0),
    ('tablet, dark', Size(1280, 800), Brightness.dark, 1.0),
  ];

  for (final MapEntry(key: name, value: (session, build)) in screens.entries) {
    for (final (variant, size, brightness, textScale) in variants) {
      testWidgets('$name — $variant', (tester) async {
        final world = (await tester.runAsync(
          () => A11yWorld.create(session: session),
        ))!;
        // Even after a failure: the screen goes first, its streams with it, and
        // only then the database — closed under a mounted screen, the next test
        // hangs.
        addTearDown(() async {
          await unmount(tester);
          await tester.runAsync(world.close);
        });
        if (withoutCamera.contains(name)) {
          debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        }
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          a11yApp(
            overrides: world.overrides(session),
            home: build(world),
            brightness: brightness,
            textScale: textScale,
          ),
        );
        await settle(tester);
        final overflows = overflowsOf(tester);
        if (overflows.isNotEmpty) {
          // ignore: avoid_print
          print('Overflows:\n$overflows');
        }

        // A call the fake does not answer turns into an error on the screen —
        // measured, but not what the screen looks like in use.
        expect(world.server.unknown, isEmpty);
        try {
          await expectAccessible(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
        await unmount(tester);
      });
    }
  }
}

/// Takes the screen down with its streams; Drift closes them on a timer of zero,
/// which has to run before the test ends.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
}

/// Lets streams, the fake server and animations come to rest — a bounded number of
/// frames, since some screens animate for as long as they are shown.
Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(seconds: 1));
}
