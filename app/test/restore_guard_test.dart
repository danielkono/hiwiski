import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/shell/restore_guard.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// **While a backup is restored nothing can be ticked — anywhere.** The guard sat
/// inside the shell; a list opened from the overview lies above it, and there "Obst"
/// on the weekly shopping was ticked while the restore ran.
void main() {
  late LocalSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await LocalSettings.open();
  });

  Future<void> pump(WidgetTester tester, SessionState session) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...quietSync,
          localSettingsProvider.overrideWithValue(settings),
          sessionAt(session),
        ],
        child: MaterialApp(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: const [
            L.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: L.supportedLocales,
          locale: const Locale('en'),
          // A page pushed above everything, like an open list.
          builder: (context, child) => RestoreGuard(child: child!),
          home: Scaffold(
            body: Checkbox(value: false, onChanged: (_) => ticked++),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a restore under way takes no taps and says why', (tester) async {
    ticked = 0;
    await pump(
      tester,
      const SessionState(stage: .signedIn, restoreBegun: true),
    );

    expect(find.textContaining('A backup is being restored'), findsOneWidget);
    await tester.tap(find.byType(Checkbox), warnIfMissed: false);
    expect(ticked, equals(0));
  });

  testWidgets('without one, everything is as it was', (tester) async {
    ticked = 0;
    await pump(tester, const SessionState(stage: .signedIn));

    expect(find.textContaining('A backup is being restored'), findsNothing);
    await tester.tap(find.byType(Checkbox));
    expect(ticked, equals(1));
  });
}

int ticked = 0;
