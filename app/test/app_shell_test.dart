import 'package:hiwiski/core/shell/app_shell.dart';
import 'package:hiwiski/core/shell/breakpoints.dart';
import 'package:hiwiski/core/theme/hiwiski_metrics.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "The app usable at all three width groups" is an acceptance case.
/// This test verifies that the right navigation is shown at every
/// width — and that the four sections are reachable everywhere.
void main() {
  late LocalSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await LocalSettings.open();
  });

  Future<void> pumpAt(
    WidgetTester tester,
    double width, {
    String location = '/',
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [localSettingsProvider.overrideWithValue(settings)],
        child: MaterialApp(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: const [
            L.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: L.supportedLocales,
          home: AppShell(location: location, child: const SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Breakpoint', () {
    test('the boundaries are at 600 and 1024', () {
      // 1024 instead of Material 3's 840: from here on three columns fit side by side.
      expect(Breakpoint.forWidth(599), equals(Breakpoint.compact));
      expect(Breakpoint.forWidth(600), equals(Breakpoint.medium));
      expect(Breakpoint.forWidth(1023), equals(Breakpoint.medium));
      expect(Breakpoint.forWidth(1024), equals(Breakpoint.wide));
    });

    test('the page padding is 16 compact and 32 wide', () {
      expect(
        Breakpoint.compact.pagePadding,
        equals(HiwiskiMetrics.pagePaddingCompact),
      );
      expect(
        Breakpoint.wide.pagePadding,
        equals(HiwiskiMetrics.pagePaddingWide),
      );
    });
  });

  testWidgets('compact: tab bar at the bottom with four entries', (
    tester,
  ) async {
    await pumpAt(tester, 390);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    // Start · Calendar · Tasks · Wiki. Nothing more.
    expect(bar.destinations, hasLength(4));
    expect(bar.selectedIndex, equals(0));
  });

  testWidgets('medium: navigation rail on the left', (tester) async {
    await pumpAt(tester, 800);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('wide below 1200 (an iPad upright): still the rail', (
    tester,
  ) async {
    // With the drawer's 260 beside it, the wiki's article was left a strip.
    await pumpAt(tester, 1032);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('wide: drawer as a fixed, collapsible column', (tester) async {
    await pumpAt(tester, 1280);

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);

    // Not a `Drawer` in the slide-out sense, but a fixed column next to the content.
    expect(find.byType(Drawer), findsNothing);

    final drawer = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer).first,
    );
    expect(drawer.constraints?.maxWidth, equals(HiwiskiMetrics.drawerWidth));
  });

  testWidgets('a subscreen belongs to its section', (tester) async {
    // Someone in the task detail sees "Tasks" highlighted, not nothing at all.
    await pumpAt(tester, 390, location: '/tasks/TD-14');

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, equals(2));
  });

  // Account and search are no tab: "Start" looked selected there.
  testWidgets('outside every tab, none looks selected', (tester) async {
    await pumpAt(tester, 390, location: '/account');

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.indicatorColor, equals(Colors.transparent));
  });
}
