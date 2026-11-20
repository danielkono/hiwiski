import 'package:drift/native.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/domain/calendar/event_draft.dart';
import 'package:hiwiski/domain/calendar/occurrence.dart';
import 'package:hiwiski/features/calendar/event_sheet/view/event_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hiwiski/app/repositories.dart';

/// **A required field that is missing turns red and says so.**
///
/// When testing, "Save" on a new event without a title did nothing at all — no event, no
/// message, the sheet just stayed open.
void main() {
  late HiwiskiDatabase db;
  late LocalSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await LocalSettings.open();
    db = HiwiskiDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  // Not `pumpAndSettle`: the sheet shows progress indicators while providers load, and
  // those animate forever.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // Drift closes its query streams with a zero timer; it has to run inside the test.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  Future<void> openNewEvent(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(settings),
          deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
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
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showEventSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  testWidgets('saving without a title marks the title as required', (
    tester,
  ) async {
    await openNewEvent(tester);
    expect(find.text('Required'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await settle(tester);

    expect(find.text('Required'), findsOneWidget);
    expect(await db.select(db.events).get(), isEmpty);
    await unmount(tester);
  });

  testWidgets('a missing title is scrolled into view and focused', (
    tester,
  ) async {
    await openNewEvent(tester);
    // The sheet's own scroll view — not the note's insert bar, which scrolls
    // sideways.
    final sheetScroll = find
        .byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == .vertical,
        )
        .last;
    // A short window: the sheet scrolls, and "Save" stays at its bottom edge.
    tester.view.physicalSize = const Size(1200, 520);
    await settle(tester);
    await tester.drag(sheetScroll, const Offset(0, -600));
    await settle(tester);
    final title = find.byKey(const ValueKey('event-title'));
    final viewport = tester.getRect(sheetScroll);
    expect(
      tester.getRect(title).bottom,
      lessThan(viewport.top),
      reason: 'scrolled away first',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await settle(tester);

    expect(tester.getRect(title).top, greaterThanOrEqualTo(viewport.top));
    final field = tester.widget<TextField>(title);
    expect(field.focusNode?.hasFocus, isTrue);
    await unmount(tester);
  });

  // A second tap while the first save still ran wrote everything twice — two
  // events, and possibly two default calendars.
  testWidgets('a double tap on save writes the event once', (tester) async {
    await openNewEvent(tester);
    await tester.enterText(
      find.byKey(const ValueKey('event-title')),
      'Dentist',
    );
    final save = find.widgetWithText(FilledButton, 'Create');
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);

    final events = await tester.runAsync(() => db.select(db.events).get());
    expect(events, hasLength(1));
    await unmount(tester);
  });

  testWidgets('typing clears the mark again', (tester) async {
    await openNewEvent(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await settle(tester);

    await tester.enterText(
      find.byKey(const ValueKey('event-title')),
      'Dentist',
    );
    await tester.pump();

    expect(find.text('Required'), findsNothing);
    await unmount(tester);
  });

  /// **"Whole series" from one occurrence keeps the series' start.** The editor
  /// starts from the opened occurrence, and its start was written as the series'
  /// start: every occurrence before it was gone.
  testWidgets(
    'editing the whole series from a later occurrence keeps its start',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(settings),
          deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
        ],
      );
      addTearDown(container.dispose);
      final event = (await tester.runAsync(() async {
        final calendar = container.read(calendarRepositoryProvider);
        final calendarId = await calendar.createCalendar(
          name: 'Family',
          colorToken: ColorTokens.blue,
        );
        final id = await calendar.createEvent(
          calendarId: calendarId,
          draft: EventDraft(
            title: 'Swimming',
            rrule: 'FREQ=WEEKLY',
            time: RecurringEvent(
              DateTime(2026, 1, 5, 17),
              DateTime(2026, 1, 5, 18),
            ),
          ),
        );
        return await container
            .read(calendarRepositoryProvider)
            .watchEvent(id)
            .first;
      }))!;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
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
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showEventSheet(
                    context,
                    event: event,
                    occurrence: occurrenceNear(
                      event,
                      at: DateTime(2026, 10, 12, 17),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);

      await tester.enterText(
        find.byKey(const ValueKey('event-title')),
        'Swimming lessons',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);
      await tester.tap(find.text('The whole series'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await settle(tester);

      final row = (await tester.runAsync(
        () => db.select(db.events).getSingle(),
      ))!;
      expect(row.title, equals('Swimming lessons'));
      expect(row.localStart, startsWith('2026-01-05T17:00'));
      expect(row.localEnd, startsWith('2026-01-05T18:00'));
      await unmount(tester);
    },
  );

  /// **A new date takes the series' weekday along** — the form shows it before the
  /// save. The rule stayed on Thursday with the date on a Friday, and the saved
  /// occurrence was gone.
  testWidgets('a new date moves the weekday of the repeat rule', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
        deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
      ],
    );
    addTearDown(container.dispose);
    final event = (await tester.runAsync(() async {
      final calendar = container.read(calendarRepositoryProvider);
      final calendarId = await calendar.createCalendar(
        name: 'Family',
        colorToken: ColorTokens.blue,
      );
      final id = await calendar.createEvent(
        calendarId: calendarId,
        draft: EventDraft(
          title: 'Football',
          rrule: 'FREQ=WEEKLY;BYDAY=TH',
          time: RecurringEvent(
            DateTime(2026, 11, 5, 14),
            DateTime(2026, 11, 5, 15),
          ),
        ),
      );
      return await calendar.watchEvent(id).first;
    }))!;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showEventSheet(
                  context,
                  event: event,
                  occurrence: occurrenceNear(
                    event,
                    at: DateTime(2026, 11, 19, 14),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(find.text('Weekly, Thu'), findsOneWidget);

    await tester.tap(find.text('Thu, 11/19/2026'));
    await settle(tester);
    await tester.tap(find.text('20'));
    await tester.tap(find.text('OK'));
    await settle(tester);
    expect(find.text('Weekly, Fri'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);
    await tester.tap(find.text('The whole series'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);

    final row = (await tester.runAsync(
      () => db.select(db.events).getSingle(),
    ))!;
    expect(row.rrule, equals('FREQ=WEEKLY;BYDAY=FR'));
    expect(row.localStart, startsWith('2026-11-06T14:00'));
    await unmount(tester);
  });
}
