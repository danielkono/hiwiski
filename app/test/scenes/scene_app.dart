import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/core/api/generated/export.dart' show Session;
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/routing/routes.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/core/ui/scene_frame.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import 'scene_server.dart';
import 'scene_shots.dart';

// Renders a scene into a PNG: the website's pictures and the store's share this, so
// both show the demo's data the same way.

/// The screen a scene is drawn on.
///
/// [size] and [padding] are logical pixels, as the app lays itself out; [padding] is
/// the safe area a phone keeps free for its status bar and home indicator. [platform]
/// is the system the app behaves as (scrolling, page transitions); `null` keeps the
/// test's own.
class const SceneScreen(
  final Size size,
  final double pixelRatio, {
  final EdgeInsets padding = .zero,
  final TargetPlatform? platform,
});

final _frame = GlobalKey();

/// Draws [shot] on [screen], writes it to [file] if given, and returns the picture.
///
/// The picture is the caller's to dispose of.
///
/// [framed]: the screen alone, inside a [SceneFrame] — no navigation bar, no rail —
/// as the website embeds it. Without it the app shows its shell, as on a device.
///
/// [learned]: the member has used the app for a while — the hint above the filter
/// bars ("Pull for filters") has done its job and is gone.
Future<ui.Image> renderScene(
  WidgetTester tester,
  SceneShot shot, {
  required String language,
  required Brightness brightness,
  required SceneScreen screen,
  File? file,
  bool framed = true,
  bool learned = false,
}) async {
  // The platform override must be gone again before the test ends; flutter_test
  // checks it before any tear-down runs.
  debugDefaultTargetPlatformOverride = screen.platform;
  try {
    return await _render(
      tester,
      shot,
      language,
      brightness,
      screen,
      file,
      framed,
      learned,
    );
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<ui.Image> _render(
  WidgetTester tester,
  SceneShot shot,
  String language,
  Brightness brightness,
  SceneScreen screen,
  File? file,
  bool framed,
  bool learned,
) async {
  late LocalSettings settings;
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await LocalSettings.open();
    if (shot.calendarView case final String view) {
      await settings.setCalendarView(view);
    }
    if (learned) await settings.setPullHint(false);
  });
  final db = HiwiskiDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  // The kiosk keeps the tablet awake.
  tester.binding.defaultBinaryMessenger.setMockMessageHandler(
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
  );
  final api = HiwiskiApi(
    tokens: NoTokens(),
    baseUrl: shot.server ? _serverAddress : null,
  );
  final container = ProviderContainer(
    retry: noRetry,
    overrides: [
      databaseProvider.overrideWithValue(db),
      kioskDatabaseProvider.overrideWithValue(db),
      kioskRepositoryProvider.overrideWith(
        (ref) => SceneKiosk(ref.watch(boardRepositoryProvider)),
      ),
      localSettingsProvider.overrideWithValue(settings),
      hiwiskiApiProvider.overrideWithValue(api),
      deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
      sessionFrom(SessionState(stage: shot.stage, handshake: shot.handshake)),
      if (shot.server) ...quietSync,
    ],
  );
  addTearDown(container.dispose);

  final demo = container.read(demoProvider);
  final location = (await tester.runAsync(() async {
    // Before a server, there is no family yet: those screens show none.
    if (shot.stage != .localOnly) return shot.location(demo, db);
    await demo.start(language: language);
    // The categories of the shopping list, before the first frame asks for them.
    await container.read(catalogRepositoryProvider).refresh();
    await shot.prepare?.call(container, demo, db);
    if (shot.server) await _signIn(container, api, language);
    return shot.location(demo, db);
  }))!;

  final ratio = screen.pixelRatio;
  tester.view.physicalSize = screen.size * ratio;
  tester.view.devicePixelRatio = ratio;
  final padding = FakeViewPadding(
    left: screen.padding.left * ratio,
    top: screen.padding.top * ratio,
    right: screen.padding.right * ratio,
    bottom: screen.padding.bottom * ratio,
  );
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

  final router = GoRouter(routes: $appRoutes, initialLocation: location);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: _frame,
        child: _framedIf(
          framed,
          MaterialApp.router(
            routerConfig: router,
            locale: Locale(language),
            theme: HiwiskiTheme.light(),
            darkTheme: HiwiskiTheme.dark(),
            localizationsDelegates: const [
              L.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L.supportedLocales,
            debugShowCheckedModeBanner: false,
          ),
        ),
      ),
    ),
  );
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (shot.open case final open?) {
    await settleScene(tester);
    await open(tester, demo, await L.delegate.load(Locale(language)));
    await settleScene(tester);
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  final boundary =
      tester.renderObject(find.byKey(_frame)) as RenderRepaintBoundary;
  final image = (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: ratio);
    if (file != null) await writePng(image, file);
    return image;
  }))!;

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  return image;
}

/// Writes [image] to [file] as PNG. Outside the fake clock: from inside
/// `tester.runAsync`.
Future<void> writePng(ui.Image image, File file) async {
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(png!.buffer.asUint8List());
}

/// [child] inside a [SceneFrame] when [framed].
Widget _framedIf(bool framed, Widget child) =>
    framed ? SceneFrame(child: child) : child;

const _serverAddress = 'https://hiwiski.example';

/// The demo's member, signed in on a server that knows the sample family.
Future<void> _signIn(
  ProviderContainer container,
  HiwiskiApi api,
  String language,
) async {
  final session = container.read(sessionStoreProvider);
  final local = session.value.member;
  if (local == null) return;
  final me = local.copyWith(isAdmin: true);
  final family = [
    for (final member
        in await container.read(familyRepositoryProvider).watchMembers().first)
      if (member.id != me.id) member,
  ];
  api.dio.httpClientAdapter = SceneServer(
    language: language,
    me: me,
    family: family,
  );
  session.debugValue = SessionState(
    stage: .signedIn,
    serverAddress: _serverAddress,
    session: Session(
      member: me,
      deviceId: '00000000-0000-7000-8000-0000000000c1',
      mustChangePassword: false,
    ),
  );
}

/// The app's own fonts instead of the test font, which draws every letter as a box.
///
/// Flutter's own widgets (the arrow of a dropdown, among others) draw from
/// MaterialIcons, not from the app's symbols; the test bundle carries it because the
/// app uses Material.
Future<void> loadSceneFonts() async {
  for (final (family, file) in const [
    ('Roboto', 'fonts/Roboto.ttf'),
    ('RobotoMono', 'fonts/RobotoMono.ttf'),
    ('MaterialSymbolsRounded', 'fonts/MaterialSymbolsRounded.ttf'),
  ]) {
    final bytes = File(file).readAsBytesSync();
    await (FontLoader(
      family,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}
