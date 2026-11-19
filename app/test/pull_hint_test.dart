import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/ui/pull_filter.dart';
import 'package:hiwiski/core/ui/pull_hint.dart';
import 'package:hiwiski/data/preferences/preferences_store.dart';
import 'package:hiwiski/domain/preferences/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The hint above a filter bar ("Pull for filters") teaches a gesture: after a few
/// pulls it goes away and gives its line back to the content. Account → Customize
/// switches it off sooner, or on for good.
void main() {
  late PreferencesStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = PreferencesStore(await LocalSettings.open());
  });

  group('learned', () {
    test('it shows until the bar was pulled down a few times', () async {
      for (int i = 0; i < Preferences.pullHintLearned; i++) {
        expect(store.value.showsPullHint, isTrue, reason: 'after $i pulls');
        await store.recordPull();
      }
      expect(store.value.showsPullHint, isFalse);
    });

    test('the count survives a restart', () async {
      for (int i = 0; i < Preferences.pullHintLearned; i++) {
        await store.recordPull();
      }
      final again = PreferencesStore(await LocalSettings.open());
      expect(again.value.showsPullHint, isFalse);
    });

    test('switched off, it is gone before it is learned', () async {
      await store.setPullHint(false);
      expect(store.value.showsPullHint, isFalse);
    });

    test('switched on, it stays for good, however often one pulls', () async {
      await store.setPullHint(true);
      for (int i = 0; i < 2 * Preferences.pullHintLearned; i++) {
        await store.recordPull();
      }
      expect(store.value.showsPullHint, isTrue);
      final again = PreferencesStore(await LocalSettings.open());
      expect(again.value.showsPullHint, isTrue);
    });
  });

  group('the bar', () {
    const hint = 'Pull for filters';

    Future<void> pump(
      WidgetTester tester, {
      required bool show,
      VoidCallback? onPulled,
    }) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PullHint(
              show: show,
              onPulled: onPulled ?? () {},
              child: PullToRevealFilter(
                hint: hint,
                filter: const Text('Filters'),
                child: ListView(
                  children: [for (int i = 0; i < 40; i++) Text('Row $i')],
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('learned, the hint is gone and the content moves up', (
      tester,
    ) async {
      await pump(tester, show: true);
      final withHint = tester.getTopLeft(find.text('Row 0')).dy;
      expect(find.text(hint), findsOneWidget);

      await pump(tester, show: false);
      // The line closes with the bar's own animation.
      await tester.pumpAndSettle();
      expect(find.text(hint), findsNothing);
      expect(tester.getTopLeft(find.text('Row 0')).dy, lessThan(withHint));
    });

    testWidgets('pulled down, it counts once; the bar comes anyway', (
      tester,
    ) async {
      int pulls = 0;
      await pump(tester, show: true, onPulled: () => pulls++);
      await tester.drag(find.text('Row 0'), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(find.text('Filters'), findsOneWidget);
      // Pulled again on the same page: the hint is already gone there.
      await tester.drag(find.text('Row 0'), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(pulls, equals(1));
    });

    testWidgets('learned, pulling still brings the bar', (tester) async {
      await pump(tester, show: false);
      await tester.drag(find.text('Row 0'), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(find.text('Filters'), findsOneWidget);
    });
  });
}
