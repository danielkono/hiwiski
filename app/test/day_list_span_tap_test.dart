import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/calendar/calendar_items.dart';
import 'package:hiwiski/domain/calendar/occurrence.dart';
import 'package:hiwiski/features/calendar/overview/view/day_list.dart';
import 'package:hiwiski/features/calendar/view/calendar_keys.dart';

/// **An all-day event in the list opens like any other.** Its pill over the day was a
/// mere label: nothing happened on a tap.
void main() {
  testWidgets('tapping an all-day pill opens the event', (tester) async {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final holiday = Occurrence(
      event: const CalendarEvent(
        id: 'e1',
        ownerId: 'anna',
        version: 1,
        tags: '',
        calendarId: 'c1',
        title: 'Holiday',
        timeForm: 'ALL_DAY',
        exceptions: '',
        attendees: '',
      ),
      start: day,
      end: day,
      allDay: true,
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: DayList(
              occurrences: const [],
              pinned: [holiday],
              calendars: const {},
              padding: .zero,
              from: day,
              to: DateTime(day.year, day.month, day.day + 2),
            ),
          ),
        ),
        GoRoute(
          path: '/calendar/event/:eventId',
          builder: (context, state) =>
              Text('opened ${state.pathParameters['eventId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: const [
            L.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L.supportedLocales,
          locale: const Locale('en'),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(CalendarKeys.spanChip('e1')).first);
    await tester.pumpAndSettle();

    expect(find.text('opened e1'), findsOneWidget);
  });
}
