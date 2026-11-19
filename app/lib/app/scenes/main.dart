import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' show FlutterView;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/platform/device_time_zone.dart';
import '../../core/routing/routes.dart';
import '../../core/ui/scene_frame.dart';
import '../../core/storage/local_settings.dart';
import '../../core/theme/hiwiski_theme.dart';
import '../../core/ui/tap_away_keyboard.dart';
import '../../core/ui/undo_snack_bar.dart';
import '../data_providers.dart';
import '../font_licenses.dart';
import '../native_licenses.dart';
import '../stores.dart';
import 'scene.dart';

/// The website's scenes: real views of the app on the
/// demo's sample data. One engine for the whole page, a Flutter view per scene the
/// page adds, and one `ProviderScope` above them all — the scenes of a page share
/// their data.
///
/// Built for the web only, with `HIWISKI_DEMO=true`: without a server, like the demo.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  registerNativeLicenses();
  // Nothing goes into the browser's storage — the site promises none.
  // The settings live in memory for the page's life.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final (settings, timeZone) = await (
    LocalSettings.open(),
    loadDeviceTimeZone(),
  ).wait;
  // The calendar's scene is its week (2.2).
  await settings.setCalendarView(_week);
  _listenToPage();

  runWidget(
    ProviderScope(
      retry: noRetry,
      overrides: [
        localSettingsProvider.overrideWithValue(settings),
        deviceTimeZoneProvider.overrideWithValue(timeZone),
      ],
      child: const _SceneViews(),
    ),
  );
}

/// The calendar view the settings store for the week.
const _week = 'WEEK';

/// What the page passes with each view: `{scene, lang}`.
const _sceneKey = 'scene';
const _languageKey = 'lang';

/// What the page and the scenes say to each other (site/assets/js/scenes.js):
/// - the page sets the theme of all scenes — its own switch, not the system's;
/// - the page sends a scene back to where it began;
/// - a scene tells the page whether it has left where it began, so the page can
///   offer the way back beside it — the scene has no shell to go back through.
const _setTheme = 'hiwiskiScenesTheme';
const _goHome = 'hiwiskiScenesHome';
const _moved = 'hiwiskiScenesMoved';
const _dark = 'dark';
const _light = 'light';

/// The theme the page chose; the system's until it chooses.
final _theme = ValueNotifier(ThemeMode.system);

/// Each scene's way back to where it began, by its view.
final _homes = <int, VoidCallback>{};

void _listenToPage() {
  globalContext[_setTheme] = ((JSString mode) {
    _theme.value = switch (mode.toDart) {
      _dark => ThemeMode.dark,
      _light => ThemeMode.light,
      _ => ThemeMode.system,
    };
  }).toJS;
  globalContext[_goHome] = ((JSNumber viewId) {
    _homes[viewId.toDartInt]?.call();
  }).toJS;
}

void _tellPage(int viewId, {required bool away}) {
  if (globalContext[_moved] case final JSFunction moved) {
    moved.callAsFunction(null, viewId.toJS, away.toJS);
  }
}

/// Every view the page has added, each with its scene.
class _SceneViews extends StatefulWidget {
  const _SceneViews();

  @override
  State<_SceneViews> createState() => _SceneViewsState();
}

class _SceneViewsState extends State<_SceneViews> with WidgetsBindingObserver {
  var _views = _current();

  static List<FlutterView> _current() =>
      WidgetsBinding.instance.platformDispatcher.views.toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A view added or removed by the page arrives as a change of the metrics.
  @override
  void didChangeMetrics() => setState(() => _views = _current());

  @override
  Widget build(BuildContext context) => ViewCollection(
    views: [
      for (final view in _views)
        View(
          key: ValueKey(view.viewId),
          view: view,
          child: _SceneView(viewId: view.viewId),
        ),
    ],
  );
}

class _SceneView extends ConsumerStatefulWidget {
  const _SceneView({required this.viewId});

  final int viewId;

  @override
  ConsumerState<_SceneView> createState() => _SceneViewState();
}

class _SceneViewState extends ConsumerState<_SceneView> {
  late final Scene? _scene;
  late final String? _language;
  late final Future<GoRouter?> _router;
  GoRouter? _active;
  String? _location;
  bool _away = false;

  @override
  void dispose() {
    _homes.remove(widget.viewId);
    _active?.routerDelegate.removeListener(_moved);
    _active?.dispose();
    super.dispose();
  }

  /// Tells the page when the scene leaves where it began, and when it is back.
  void _moved() {
    final away =
        _active?.routerDelegate.currentConfiguration.uri.toString() !=
        _location;
    if (away == _away) return;
    _away = away;
    _tellPage(widget.viewId, away: away);
  }

  @override
  void initState() {
    super.initState();
    final data = ui_web.views.getInitialData(widget.viewId)?.dartify();
    final map = data is Map ? data : const <Object?, Object?>{};
    _scene = Scene.byId(map[_sceneKey]);
    _language = map[_languageKey] as String?;
    _router = _start();
  }

  /// The sample data once per page, then a router that stays on the scene.
  Future<GoRouter?> _start() async {
    final scene = _scene;
    if (scene == null) return null;
    final demo = ref.read(demoProvider);
    await demo.start(language: _language);
    final location = scene.location(demo);
    final path = Uri.parse(location).path;
    final home = const HomeRoute().location;
    final router = GoRouter(
      routes: $appRoutes,
      initialLocation: location,
      // The page's own address is not the scene's.
      overridePlatformDefaultLocation: true,
      // A scene does not lead into the rest of the app — only deeper into itself:
      // a task of the list, the next page of the wiki.
      redirect: (context, state) {
        final to = state.uri.path;
        final inside = path == home ? to == home : to.startsWith(path);
        return inside ? null : location;
      },
    );
    _homes[widget.viewId] = () => router.go(location);
    _active = router;
    _location = location;
    router.routerDelegate.addListener(_moved);
    return router;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _router,
    builder: (context, snapshot) => switch (snapshot.data) {
      final GoRouter router => SceneFrame(
        child: ValueListenableBuilder(
          valueListenable: _theme,
          builder: (context, theme, _) => MaterialApp.router(
            themeMode: theme,
            routerConfig: router,
            locale: switch (_language) {
              final String language => Locale(language),
              null => null,
            },
            theme: HiwiskiTheme.light(),
            darkTheme: HiwiskiTheme.dark(),
            builder: (context, child) => UndoWindow(
              duration: ref.watch(
                preferencesProvider.select((p) => p.undoWindow),
              ),
              child: TapAwayKeyboard(child: child ?? const SizedBox.shrink()),
            ),
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
      _ => const SizedBox.shrink(),
    },
  );
}
