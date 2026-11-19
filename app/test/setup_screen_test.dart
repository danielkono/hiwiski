import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/features/setup/view/setup_keys.dart';
import 'package:hiwiski/features/setup/view/setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The wizard builds every step at the same place in the widget tree.
///
/// Without their own `Key`s, Flutter reuses the `TextField` element and only attaches a
/// different controller — whatever is typed in the frame in between then lands in the
/// previous step's controller. On the first run against a real server, the username
/// therefore ended up in the database as the family name.
///
/// This test pins that down: it is a bug you only see when using the app.
void main() {
  late LocalSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await LocalSettings.open();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
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
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L.supportedLocales,
          locale: const Locale('de'),
          home: const SetupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the family name survives the step change', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(SetupKeys.setupCode), 'K7M4-2QXP');
    await tester.pump();
    await tester.tap(find.byKey(SetupKeys.startFresh));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('setup.familyName')),
      'Familie Berger',
    );
    await tester.enterText(
      find.byKey(const ValueKey('setup.timezone')),
      'Europe/Berlin',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();

    // Step 2 is shown, and with its own fields.
    expect(find.byKey(const ValueKey('setup.displayName')), findsOneWidget);
    expect(find.byKey(const ValueKey('setup.familyName')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('setup.displayName')),
      'Markus',
    );
    await tester.enterText(
      find.byKey(const ValueKey('setup.username')),
      'markus',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();

    // The point of the test: not "markus".
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('setup.familyName')))
          .controller
          ?.text,
      equals('Familie Berger'),
    );
  });

  testWidgets('Next stays disabled while a required field is missing', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byKey(SetupKeys.setupCode), 'K7M4-2QXP');
    await tester.pump();
    await tester.tap(find.byKey(SetupKeys.startFresh));
    await tester.pumpAndSettle();

    // A button that only produces an error message is not offered.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    // Otherwise the time zone comes from the device; in the test there is none.
    await tester.enterText(
      find.byKey(const ValueKey('setup.familyName')),
      'Familie Berger',
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
      reason: 'without a time zone there is no way forward',
    );

    await tester.enterText(
      find.byKey(const ValueKey('setup.timezone')),
      'Europe/Berlin',
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  // A fresh server is set up only with the code from
  // its log — and restored from a backup only with it, too.
  testWidgets('neither way opens without the setup code', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(SetupKeys.setupCode), '');
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byKey(SetupKeys.startFresh)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(SetupKeys.restoreBackup))
          .onPressed,
      isNull,
    );
  });

  /// The backup password has a step of its own, typed twice, and is not the
  /// administrator's.
  testWidgets('the backup password is not the administrator password', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byKey(SetupKeys.setupCode), 'K7M4-2QXP');
    await tester.pump();
    await tester.tap(find.byKey(SetupKeys.startFresh));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(SetupKeys.familyName), 'Familie');
    await tester.enterText(find.byKey(SetupKeys.timezone), 'Europe/Berlin');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(SetupKeys.displayName), 'Markus');
    await tester.enterText(find.byKey(SetupKeys.username), 'markus');
    await tester.enterText(find.byKey(SetupKeys.password), 'correct horse');
    await tester.enterText(
      find.byKey(SetupKeys.passwordRepeat),
      'correct horse',
    );
    await tester.pump();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();

    expect(find.textContaining('nobody can reset it'), findsNothing);
    expect(find.textContaining('niemand kann es zurücksetzen'), findsOneWidget);
    await tester.enterText(
      find.byKey(SetupKeys.backupPassword),
      'correct horse',
    );
    await tester.enterText(
      find.byKey(SetupKeys.backupPasswordRepeat),
      'correct horse',
    );
    await tester.pump();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(
      find.text('Nimm ein anderes als dein Administratorpasswort.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(SetupKeys.backupPassword),
      'battery staple',
    );
    await tester.enterText(
      find.byKey(SetupKeys.backupPasswordRepeat),
      'battery staple',
    );
    await tester.pump();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Eltern'), findsOneWidget);
  });

  // The password field rebuilt nothing: typed last, "Continue" stayed disabled.
  testWidgets('the password typed last enables Continue', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(SetupKeys.setupCode), 'K7M4-2QXP');
    await tester.pump();
    await tester.tap(find.byKey(SetupKeys.startFresh));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(SetupKeys.familyName), 'Familie');
    await tester.enterText(find.byKey(SetupKeys.timezone), 'Europe/Berlin');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(SetupKeys.displayName), 'Markus');
    await tester.enterText(find.byKey(SetupKeys.username), 'markus');
    await tester.enterText(find.byKey(SetupKeys.password), 'correct horse');
    await tester.pump();

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  // Fields keyed by position: deleting the first group handed the focused field's
  // element to another group, and the focus dropped.
  testWidgets('removing a group above keeps the focus where it was', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byKey(SetupKeys.setupCode), 'K7M4-2QXP');
    await tester.pump();
    await tester.tap(find.byKey(SetupKeys.startFresh));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(SetupKeys.familyName), 'Familie');
    await tester.enterText(find.byKey(SetupKeys.timezone), 'Europe/Berlin');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(SetupKeys.displayName), 'Markus');
    await tester.enterText(find.byKey(SetupKeys.username), 'markus');
    await tester.enterText(find.byKey(SetupKeys.password), 'correct horse');
    await tester.enterText(
      find.byKey(SetupKeys.passwordRepeat),
      'correct horse',
    );
    await tester.pump();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(SetupKeys.backupPassword),
      'battery staple',
    );
    await tester.enterText(
      find.byKey(SetupKeys.backupPasswordRepeat),
      'battery staple',
    );
    await tester.pump();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextField, 'Eltern'));
    await tester.pump();
    await tester.tap(find.byTooltip('Löschen').first);
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextField, 'Eltern'),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.focusNode.hasFocus, isTrue);
  });
}
