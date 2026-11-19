import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app/background_sync.dart';
import 'app/carryover.dart';
import 'app/data_providers.dart';
import 'app/font_licenses.dart';
import 'app/native_licenses.dart';
import 'app/home_widgets.dart';
import 'app/invite_links.dart';
import 'app/reminder_taps.dart';
import 'data/calendar/reminder_repository.dart';
import 'app/repositories.dart';
import 'app/router.dart';
import 'app/stores.dart';
import 'core/ui/keyboard_bar_room.dart';
import 'core/ui/tap_away_keyboard.dart';
import 'core/common/app_names.dart';
import 'core/common/build_flavor.dart';
import 'core/l10n/generated/app_localizations.dart';
import 'core/shell/restore_guard.dart';
import 'core/platform/device_time_zone.dart';
import 'core/platform/viewport.dart';
import 'core/storage/local_settings.dart';
import 'core/theme/hiwiski_color_schemes.dart';
import 'core/theme/hiwiski_theme.dart';
import 'core/theme/system_bars.dart';
import 'core/theme/theme_modes.dart';
import 'core/ui/undo_snack_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  keepInputsFromZooming();
  keepPageInPlace();
  registerFontLicenses();
  registerNativeLicenses();

  // Addresses without `#`. The dashboard address is `…/board/<token>` and is **typed in
  // by hand** on a wall tablet — a `/#/` in it is a source of errors nobody
  // needs. For that, the server serves `index.html` for unknown paths.
  // A Flutter web function whose name starts with `use`, not a hook.
  // ignore: many_lints/avoid_hooks_outside_build
  usePathUrlStrategy();

  // The sync runs without the app, too. The token
  // has to be readable for that while the phone is locked. Neither is needed for the
  // first frame: they run alongside, and a failure is only logged.
  unawaited(
    initializeBackgroundSync().onError<Object>(
      (error, _) => debugPrint('hiwiski: background sync not set up: $error'),
    ),
  );

  // Before the first frame, side by side — they do not depend on each other:
  // - the theme belongs to the member and is also kept locally so the first frame
  //   after startup is already right; later, the app flashes light;
  // - without a loaded zone database a series expands in UTC, and "every Monday
  //   8:00" moves to 9:00 when the clocks change;
  // - the app draws behind the system bars, which take on its colour (SystemBars).
  final (settings, timeZone, _) = await (
    LocalSettings.open(),
    loadDeviceTimeZone(),
    SystemBars.enableEdgeToEdge(),
  ).wait;

  runApp(
    ProviderScope(
      retry: noRetry,
      overrides: [
        localSettingsProvider.overrideWithValue(settings),
        deviceTimeZoneProvider.overrideWithValue(timeZone),
      ],
      child: const HiwiskiApp(),
    ),
  );
}

class HiwiskiApp extends ConsumerStatefulWidget {
  const HiwiskiApp({super.key});

  @override
  ConsumerState<HiwiskiApp> createState() => _HiwiskiAppState();
}

class _HiwiskiAppState extends ConsumerState<HiwiskiApp>
    with WidgetsBindingObserver {
  StreamSubscription<Uri>? _links;
  StreamSubscription<ReminderTarget>? _reminderTaps;
  ForegroundSync? _foreground;
  Brightness _platformBrightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _links?.cancel();
    _reminderTaps?.cancel();
    _foreground?.close();
    super.dispose();
  }

  /// Back in the foreground: what was changed on the way goes out now, not at the
  /// next change of one's own or after the backoff — on iOS the timer stood still in
  /// the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == .resumed) {
      // Catching up reports through the sync banner.
      _catchUp().ignore();
    }
  }

  /// The sync a background run asks for in its place, and the reminders right after it.
  ///
  /// The reminders usually follow the tables two seconds later. That is too late here:
  /// the background run ends with this sync, and iOS suspends the app again at once —
  /// what was pulled would only remind after the next run or the next time the app is
  /// opened.
  Future<void> _syncForBackgroundRun() async {
    await ref.read(syncRepositoryProvider).syncNow();
    await ref.read(reminderRepositoryProvider).rescheduleAll();
  }

  /// A background run may have written meanwhile: settings and database are read
  /// afresh before syncing.
  ///
  /// In the browser no background run exists — the database is in memory — and
  /// "resumed" comes with every tab switch: re-reading everything there re-ran every
  /// watched query each time. What the browser checks instead, whether the server was
  /// updated, runs on its own: behind the sync it waited for a full push and pull, and
  /// a failing sync skipped it.
  Future<void> _catchUp() async {
    if (kIsWeb) {
      // A failed check is the same as no update; the next one comes.
      ref.read(webUpdateStoreProvider).check().ignore();
    } else {
      await ref.read(preferencesStoreProvider).reload();
      final db = ref.read(databaseProvider);
      db.markTablesUpdated(db.allTables);
    }
    await ref.read(syncRepositoryProvider).syncNow();
  }

  /// The demo's sample data. Should it fail, the demo is empty but usable.
  Future<void> _startDemo() async {
    try {
      await ref.read(demoProvider).start();
    } on Object catch (error) {
      debugPrint('hiwiski: demo not started: $error');
    }
  }

  /// `MaterialApp.color` becomes `theme-color` in the browser — it has to follow the
  /// system's brightness when the theme does.
  @override
  void didChangePlatformBrightness() => setState(
    () => _platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The build this tab runs is the one the server serves now — asked at page load.
    // Asked first when the sync banner appeared after sign-in, a tab left on the
    // sign-in page across an update took the new build for its own and never
    // offered the reload.
    if (kIsWeb) ref.read(webUpdateStoreProvider);
    // What a device used without a server takes along besides its outbox follows
    // each sync.
    ref.read(carryoverProvider);
    // The demo begins on its sample data, on every page load.
    if (BuildFlavor.demo) unawaited(_startDemo());
    // The invitation QR carries `hiwiski://invite?…`; scanned with the
    // phone's camera, it opens the app right here.
    _links = listenForInviteLinks(ref);
    // The home screen widgets follow the session and this device's data.
    ref.read(homeWidgetsProvider);
    _reminderTaps = listenForReminderTaps(ref);
    // The sync without the app runs for as long as a member is signed in.
    ref.read(backgroundSyncScheduleProvider);
    // A background run that finds the app alive lets it sync instead of running a
    // second sync next to it.
    _foreground = serveForegroundSync(
      sync: _syncForBackgroundRun,
      caughtUp: _catchUp,
    );
    // As soon as a session exists: pull once and hook into the stream. Before that
    // there is nothing to sync, and the stream needs a ticket.
    ref.listenManual(sessionProvider.select((session) => session.stage), (
      previous,
      next,
    ) {
      // Without a server nothing syncs, but reminders ring all the same — they come
      // from the device's own data.
      if (next == .localOnly && previous != .localOnly) {
        // A reminder that cannot be scheduled is logged by the repository.
        _startReminders().ignore();
      }
      if (next == .signedIn && previous != .signedIn) {
        final engine = ref.read(syncRepositoryProvider);
        // The sync reports its own failures: banner, retry.
        engine.syncNow().ignore();
        // A lost signal stream reconnects itself.
        engine.listenForSignals().ignore();
        // Reminders are scheduled from the **mirrored** data.
        // Hence only here: before sign-in there is nothing to schedule one from.
        _startReminders().ignore();
      }
    }, fireImmediately: true);
  }

  /// Schedules the reminders, then opens the event of the one the app was started
  /// with.
  Future<void> _startReminders() async {
    await ref.read(reminderRepositoryProvider).initialize();
    if (mounted) await openLaunchReminder(ref);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(
      preferencesProvider.select((p) => p.themeMode.mode),
    );
    final undoWindow = ref.watch(
      preferencesProvider.select((p) => p.undoWindow),
    );
    final dark = switch (themeMode) {
      .dark => true,
      .light => false,
      .system => _platformBrightness == .dark,
    };

    return MaterialApp.router(
      title: AppNames.product,
      onGenerateTitle: (context) => L.of(context).appName,
      // The task switcher and the browser's bars show the page, not a brand colour.
      color:
          (dark ? HiwiskiColorSchemes.dark : HiwiskiColorSchemes.light).surface,
      theme: HiwiskiTheme.light(),
      darkTheme: HiwiskiTheme.dark(),
      themeMode: themeMode,
      builder: (context, child) => UndoWindow(
        duration: undoWindow,
        child: SystemBars(
          child: KeyboardBarRoom(
            overlap: keyboardBarOverlap(),
            child: TapAwayKeyboard(
              child: RestoreGuard(child: child ?? const SizedBox.shrink()),
            ),
          ),
        ),
      ),
      routerConfig: router,
      localizationsDelegates: const [
        L.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L.supportedLocales,
      debugShowCheckedModeBanner: false,
    );
  }
}
