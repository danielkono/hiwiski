import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/font_licenses.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/common/app_names.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/data/app_info/app_info_repository.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:hiwiski/features/account/about/view/about_screen.dart';
import 'package:hiwiski/features/account/view/account_keys.dart';

import 'support/fakes.dart';

/// **Account → About** says which app and which server, under which license, and
/// lists the licenses of everything the app is built from — fonts included, which
/// Flutter does not collect by itself.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    String version = '2026.1.1',
    String build = '42',
  }) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...quietSync,
          sessionAt(_session),
          appInfoRepositoryProvider.overrideWithValue(
            _FakeAppInfo(version, build),
          ),
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
          locale: const Locale('en'),
          home: const Scaffold(body: AboutScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the app and server version and the license', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('2026.1.1 (42)'), findsOneWidget);
    expect(find.text('2026.0.9'), findsOneWidget);
    expect(find.text('PolyForm Noncommercial 1.0.0'), findsOneWidget);
    // The source only while it leads anywhere; the app's own policy always.
    expect(
      find.text('Source code'),
      ProjectInfo.sourcePublic ? findsOneWidget : findsNothing,
    );
    expect(find.text('App privacy policy'), findsOneWidget);
  });

  testWidgets('a development build says so instead of an empty version', (
    tester,
  ) async {
    await pump(tester, version: '', build: '');

    expect(find.text('Development build'), findsOneWidget);
  });

  testWidgets('the package licenses include the fonts', (tester) async {
    registerFontLicenses();
    await pump(tester);

    await tester.tap(find.byKey(AccountKeys.packageLicenses));
    await tester.pumpAndSettle();

    // Wide enough for the master-detail layout: a font may show in both panes.
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('Roboto'), findsWidgets);
    expect(find.text('Roboto Mono'), findsWidgets);
    expect(find.text('Material Symbols Rounded'), findsWidgets);
  });
}

const _session = SessionState(
  stage: .signedIn,
  handshake: Handshake(
    apiVersion: 'v1',
    serverVersion: '2026.0.9',
    minClientVersion: '0',
    setupCompleted: true,
    cleartext: false,
  ),
);

class _FakeAppInfo implements AppInfoRepository {
  const _FakeAppInfo(this._version, this._build);

  final String _version;
  final String _build;

  @override
  Future<({String version, String build})> version() async =>
      (version: _version, build: _build);
}
