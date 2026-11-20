import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/router.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/routing/routes.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'a11y/a11y_world.dart'
    show firstStartSession, mockPlugins, unmockPlugins;
import 'a11y/screens_a11y_test.dart' show settle, unmount;
import 'support/fakes.dart';

/// Connecting on the first screen: once a Hiwiski server answers, the app goes on by
/// itself. A confirmation with a "Continue" button only asked for one more tap —
/// sign-in names the server and warns of a connection without encryption.
void main() {
  setUp(mockPlugins);
  tearDown(unmockPlugins);

  /// The app on its first start, with [server] behind every address, at the screen
  /// the router shows — the server address. Returns where the router is.
  Future<String Function()> start(WidgetTester tester, _Server server) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final api = HiwiskiApi(tokens: NoTokens(), baseUrl: settings.serverAddress)
      ..dio.httpClientAdapter = server;
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        overrides: [
          sessionFrom(firstStartSession),
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(settings),
          tokenStoreProvider.overrideWithValue(NoTokens()),
          hiwiskiApiProvider.overrideWithValue(api),
          deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            theme: HiwiskiTheme.light(),
            localizationsDelegates: const [
              L.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L.supportedLocales,
            locale: const Locale('en'),
            routerConfig: ref.watch(routerProvider),
          ),
        ),
      ),
    );
    addTearDown(() => unmount(tester));
    await settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final router = container.read(routerProvider);
    return () => router.routeInformationProvider.value.uri.path;
  }

  Future<void> connect(WidgetTester tester) async {
    final l = await L.delegate.load(const Locale('en'));
    await tester.enterText(find.byType(TextField), 'hiwiski.test');
    await tester.tap(find.text(l.serverConnect));
    await settle(tester);
  }

  testWidgets('a server that is set up goes on to sign-in', (tester) async {
    final at = await start(tester, _Server());
    expect(at(), equals(const ServerAddressRoute().location));

    await connect(tester);

    expect(at(), equals(const LoginRoute().location));
  });

  testWidgets('a server not set up yet goes on to the wizard', (tester) async {
    final at = await start(tester, _Server(setUp: false));

    await connect(tester);

    expect(at(), equals(const SetupRoute().location));
  });

  testWidgets('where no server answers, the address stays with the error', (
    tester,
  ) async {
    final at = await start(tester, _Server(answers: false));
    final l = await L.delegate.load(const Locale('en'));

    await connect(tester);

    expect(at(), equals(const ServerAddressRoute().location));
    expect(find.text(l.serverUnreachable), findsOneWidget);
  });
}

/// A server that answers its handshake and nothing else — or does not answer at all.
class _Server implements HttpClientAdapter {
  _Server({this.setUp = true, this.answers = true});

  final bool setUp;
  final bool answers;

  static const _json = {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!answers) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'nothing there',
      );
    }
    if (options.uri.path.endsWith('/handshake')) {
      return .fromString(
        jsonEncode(
          Handshake(
            apiVersion: 'v1',
            serverVersion: '2026.1.0',
            minClientVersion: '0',
            setupCompleted: setUp,
            cleartext: false,
            familyName: 'Berger',
          ),
        ),
        200,
        headers: _json,
      );
    }
    return .fromString(
      jsonEncode({'code': 'not_found', 'message': 'fake'}),
      404,
      headers: _json,
    );
  }

  @override
  void close({bool force = false}) {}
}
