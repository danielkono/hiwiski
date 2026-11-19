import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/invite_links.dart';
import 'package:hiwiski/app/router.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/core/ui/ui_keys.dart';
import 'package:hiwiski/data/session/session_repository.dart';
import 'package:hiwiski/domain/invite/invite_link.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:hiwiski/features/redeem_invitation/view/redeem_invitation_keys.dart';
import 'package:hiwiski/features/redeem_invitation/view/redeem_invitation_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _session = SessionState(
  stage: .signedOut,
  serverAddress: 'https://familie.example',
);

const _localizations = [
  L.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// An invitation's QR code names its server like a link does — the phone's camera
/// reads it and opens the link: the app asks before it switches, and "Redeem
/// invitation" says where the code goes.
void main() {
  late _Connections connections;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    connections = _Connections();
  });

  void tallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('the screen names the server the code goes to', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionAt(_session, repository: connections),
          localSettingsProvider.overrideWithValue(await LocalSettings.open()),
        ],
        child: MaterialApp(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: _localizations,
          supportedLocales: L.supportedLocales,
          locale: const Locale('en'),
          home: const RedeemInvitationScreen(),
        ),
      ),
    );

    expect(find.byKey(RedeemInvitationKeys.server), findsOneWidget);
    expect(find.textContaining('familie.example'), findsOneWidget);
  });

  testWidgets('a link for another server asks first', (tester) async {
    tallScreen(tester);
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late WidgetRef app;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionAt(_session, repository: connections),
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(await LocalSettings.open()),
          deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            app = ref;
            return MaterialApp.router(
              theme: HiwiskiTheme.light(),
              localizationsDelegates: _localizations,
              supportedLocales: L.supportedLocales,
              locale: const Locale('en'),
              routerConfig: ref.watch(routerProvider),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final link = parseInviteLink(
      'hiwiski://invite?host=https://andere.example&code=ABCDEFG',
    )!;
    final followed = followInviteLink(app, link);
    await tester.pumpAndSettle();

    expect(find.byKey(CoreKeys.inviteServerDialog), findsOneWidget);
    expect(find.textContaining('andere.example'), findsWidgets);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await followed;

    expect(find.byKey(CoreKeys.inviteServerDialog), findsNothing);
    expect(find.byType(RedeemInvitationScreen), findsNothing);
    expect(
      app.read(sessionProvider).serverAddress,
      equals('https://familie.example'),
    );
    expect(connections.calls, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}

/// Records whatever the session would do with its server: here, nothing may happen.
class _Connections implements SessionRepository {
  final calls = <Symbol>[];

  /// A device that was never used without a server.
  @override
  Member? get localMember => null;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    return super.noSuchMethod(invocation);
  }
}
