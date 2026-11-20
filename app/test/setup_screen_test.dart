import 'package:hiwiski/core/api/generated/export.dart' hide Mutation;
import 'package:hiwiski/core/api/hiwiski_failure.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/data/session/session_repository.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/features/setup/view/setup_keys.dart';
import 'package:hiwiski/features/setup/view/setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

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

  Future<void> pump(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localSettingsProvider.overrideWithValue(settings),
          ...overrides,
        ],
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

  // The default: on a home network the family sets up without reading the server's
  // log first.
  testWidgets('a server that asks for no code opens both ways at once', (
    tester,
  ) async {
    await pump(tester, overrides: [sessionAt(_setupWithoutCode)]);
    expect(find.byKey(SetupKeys.setupCode), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byKey(SetupKeys.startFresh)).onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(SetupKeys.restoreBackup))
          .onPressed,
      isNotNull,
    );
  });

  // A wrong code came back only after every step was filled in.
  testWidgets('a wrong code is said before the steps', (tester) async {
    final server = _CheckingCode();
    await pump(
      tester,
      overrides: [sessionAt(_setupWithCode, repository: server)],
    );
    await tester.enterText(find.byKey(SetupKeys.setupCode), 'WRON-GCOD');
    await tester.pump();
    await tester.tap(find.byKey(SetupKeys.startFresh));
    await tester.pumpAndSettle();

    expect(server.checked, equals(['WRON-GCOD']));
    expect(find.byKey(SetupKeys.familyName), findsNothing);
    expect(find.textContaining('Der Einrichtungscode stimmt nicht'), findsOne);

    await tester.enterText(find.byKey(SetupKeys.setupCode), 'K7M4-2QXP');
    await tester.pump();
    await tester.tap(find.byKey(SetupKeys.startFresh));
    await tester.pumpAndSettle();

    expect(server.checked, equals(['WRON-GCOD', 'K7M4-2QXP']));
    expect(find.byKey(SetupKeys.familyName), findsOneWidget);
    expect(
      find.textContaining('Der Einrichtungscode stimmt nicht'),
      findsNothing,
    );
  });

  // Its operator switched the code on after the handshake: without the field the
  // wizard could only show the error again.
  testWidgets('a code refused anyway brings its field back', (tester) async {
    final server = _RefusingSetup();
    await pump(
      tester,
      overrides: [sessionAt(_setupWithoutCode, repository: server)],
    );
    await tester.tap(find.byKey(SetupKeys.startFresh));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(SetupKeys.familyName), 'Familie');
    await tester.enterText(find.byKey(SetupKeys.timezone), 'Europe/Berlin');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(SetupKeys.displayName), 'Markus');
    await tester.enterText(find.byKey(SetupKeys.username), 'markus');
    await tester.enterText(find.byKey(SetupKeys.password), 'correct horse');
    await tester.enterText(
      find.byKey(SetupKeys.passwordRepeat),
      'correct horse',
    );
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
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
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    // The groups, then the last step.
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(server.sent, isNotNull);
    expect(server.sent?.setupCode, isNull, reason: 'none was asked for');
    expect(find.byKey(SetupKeys.setupCode), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(SetupKeys.startFresh)).onPressed,
      isNull,
      reason: 'from now on the code is needed',
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

/// A fresh server that asks for no setup code.
const _setupWithoutCode = SessionState(
  stage: .setupRequired,
  serverAddress: 'https://hiwiski.local',
  handshake: Handshake(
    apiVersion: 'v1',
    serverVersion: '2026.1.0',
    minClientVersion: '0',
    setupCompleted: false,
    cleartext: false,
    setupCodeRequired: false,
  ),
);

/// A fresh server that asks for the setup code — and can check it before the steps.
const _setupWithCode = SessionState(
  stage: .setupRequired,
  serverAddress: 'https://hiwiski.local',
  handshake: Handshake(
    apiVersion: 'v1',
    serverVersion: '2026.1.0',
    minClientVersion: '0',
    setupCompleted: false,
    cleartext: false,
    setupCodeRequired: true,
  ),
);

/// Takes only `K7M4-2QXP`, and remembers every code it was asked about.
class _CheckingCode implements SessionRepository {
  final checked = <String>[];

  @override
  Member? get localMember => null;

  @override
  Future<void> checkSetupCode(String setupCode) async {
    checked.add(setupCode);
    if (setupCode != 'K7M4-2QXP') {
      throw const HiwiskiFailure(
        code: FailureCodes.setupCodeInvalid,
        status: 403,
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Refuses the setup for a missing code, as a server does whose operator switched it
/// on after the app's handshake.
class _RefusingSetup implements SessionRepository {
  SetupRequest? sent;

  @override
  Member? get localMember => null;

  @override
  Future<DeviceRegistration> thisDevice({bool staySignedIn = true}) async =>
      const DeviceRegistration(deviceName: 'Test', platform: .web);

  @override
  Future<SignedIn> runSetup(SetupRequest request) async {
    sent = request;
    throw const HiwiskiFailure(
      code: FailureCodes.setupCodeInvalid,
      status: 403,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
