import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/core/ui/ui_keys.dart';
import 'package:hiwiski/domain/calendar/event_draft.dart';
import 'package:hiwiski/features/calendar/event/view/event_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **An event is edited where it is read**, like a task, a list and a wiki page:
/// "Edit" in its header turns the page into the event's fields, and "Cancel" and
/// "Save" stand where "Edit" was. It used to open a dialog over the page.
void main() {
  late HiwiskiDatabase db;
  late LocalSettings settings;
  late String eventId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await LocalSettings.open();
    db = HiwiskiDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      retry: noRetry,
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
        deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
      ],
    );
    final calendar = container.read(calendarRepositoryProvider);
    final calendarId = await calendar.createCalendar(
      name: 'Family',
      colorToken: ColorTokens.blue,
    );
    eventId = await calendar.createEvent(
      calendarId: calendarId,
      draft: EventDraft(
        title: 'Dentist',
        time: TimedEvent(DateTime(2026, 3, 2, 9), DateTime(2026, 3, 2, 10)),
      ),
    );
    container.dispose();
  });

  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
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
          home: Scaffold(body: EventScreen(eventId: eventId)),
        ),
      ),
    );
    await settle(tester);
  }

  // Drift closes its query streams with a zero timer; it has to run inside the test.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  const titleField = ValueKey('event-title');

  testWidgets('"Edit" opens the fields on the page, and "Save" writes them', (
    tester,
  ) async {
    await open(tester);
    expect(find.byKey(titleField), findsNothing);

    await tester.tap(find.text('Edit'));
    await settle(tester);
    expect(find.byKey(titleField), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Edit'), findsNothing);

    await tester.enterText(find.byKey(titleField), 'Dentist, check-up');
    await tester.tap(find.byKey(CoreKeys.editSave));
    await settle(tester);

    expect(find.byKey(titleField), findsNothing);
    expect(find.text('Edit'), findsOneWidget);
    final row = (await tester.runAsync(
      () => db.select(db.events).getSingle(),
    ))!;
    expect(row.title, equals('Dentist, check-up'));
    await unmount(tester);
  });

  testWidgets('"Cancel" closes the fields and writes nothing', (tester) async {
    await open(tester);
    await tester.tap(find.text('Edit'));
    await settle(tester);

    await tester.enterText(find.byKey(titleField), 'Something else');
    await tester.tap(find.byKey(CoreKeys.editCancel));
    await settle(tester);

    expect(find.byKey(titleField), findsNothing);
    final row = (await tester.runAsync(
      () => db.select(db.events).getSingle(),
    ))!;
    expect(row.title, equals('Dentist'));
    await unmount(tester);
  });
}
