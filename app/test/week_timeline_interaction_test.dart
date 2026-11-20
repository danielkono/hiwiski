import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_metrics.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/core/ui/week_timeline.dart';
import 'package:hiwiski/domain/calendar/calendar_items.dart';
import 'package:hiwiski/domain/calendar/occurrence.dart';
import 'package:hiwiski/domain/calendar/reschedule.dart';
import 'package:hiwiski/domain/calendar/week_layout.dart';

/// **The week is worked in**: a tap into free hours, an event
/// dragged elsewhere, and the card it opens into.
void main() {
  final monday = DateTime(2026, 10, 12);
  final days = [for (int i = 0; i < 7; i++) DateTime(2026, 10, 12 + i)];
  final dentist = Occurrence(
    event: const CalendarEvent(
      id: 'e1',
      ownerId: 'anna',
      version: 1,
      tags: '',
      calendarId: 'c1',
      title: 'Dentist',
      timeForm: 'TIMED',
      exceptions: '',
      attendees: '',
    ),
    start: DateTime(2026, 10, 12, 10),
    end: DateTime(2026, 10, 12, 11),
    allDay: false,
  );

  Future<void> pump(
    WidgetTester tester, {
    ValueChanged<WeekSlot>? onSlotTap,
    void Function(Occurrence, WeekSlot)? onMove,
  }) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: HiwiskiTheme.light(),
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L.supportedLocales,
        locale: const Locale('de'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: WeekTimeline(
              days: days,
              occurrences: [dentist],
              calendars: const {},
              alwaysShown: const TimeSegment(8 * 60, 20 * 60),
              onSlotTap: onSlotTap,
              onMove: onMove ?? (_, _) {},
              preview: (context, occurrence) =>
                  Text('card ${occurrence.event.title}'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The y of an hour line: its label starts 8 above it.
  double lineOf(WidgetTester tester, String label) =>
      tester.getTopLeft(find.text(label)).dy + 8;

  /// The block shows the title with the time below it.
  final block = find.textContaining('Dentist');

  testWidgets('a tap into free hours gives the slot on the quarter hour', (
    tester,
  ) async {
    WeekSlot? tapped;
    await pump(tester, onSlotTap: (slot) => tapped = slot);
    final dayWidth = tester.getSize(find.byType(WeekTimeline)).width / 7.5;
    final y = lineOf(tester, '14:00') + 2;
    // Wednesday's column, a little after 14:00.
    final x =
        tester.getTopLeft(find.byType(WeekTimeline)).dx + 34 + 2.5 * dayWidth;

    await tester.tapAt(Offset(x, y));

    expect(tapped, equals(WeekSlot(DateTime(2026, 10, 14), 14 * 60)));
  });

  testWidgets('dragged with the mouse, an event lands an hour later', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    (Occurrence, WeekSlot)? dropped;
    await pump(
      tester,
      onMove: (occurrence, slot) => dropped = (occurrence, slot),
    );
    final hour = lineOf(tester, '12:00') - lineOf(tester, '11:00');

    final gesture = await tester.startGesture(
      tester.getCenter(block),
      kind: .mouse,
    );
    for (int i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, hour / 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(dropped?.$1, same(dentist));
    expect(dropped?.$2, equals(WeekSlot(monday, 11 * 60)));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('dragged onto the band, an event lands as all-day', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    WeekSlot? dropped;
    await pump(tester, onMove: (_, slot) => dropped = slot);
    final start = tester.getCenter(block);
    // Just below the day header: the band.
    final band = lineOf(tester, '08:00') - 16;

    final gesture = await tester.startGesture(start, kind: .mouse);
    for (int i = 1; i <= 10; i++) {
      await gesture.moveTo(
        Offset(start.dx, start.dy + (band - start.dy) * i / 10),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(dropped, equals(WeekSlot(monday)));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a long press on touch opens the card, and it stays', (
    tester,
  ) async {
    await pump(tester);

    final gesture = await tester.startGesture(tester.getCenter(block));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.text('card Dentist'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('card Dentist'), findsOneWidget);

    // A tap elsewhere closes it.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('card Dentist'), findsNothing);
  });

  testWidgets('hovering with the mouse opens the card', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await pump(tester);
    final mouse = await tester.createGesture(kind: .mouse);
    await mouse.addPointer(location: .zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(tester.getCenter(block));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('card Dentist'), findsOneWidget);

    // The card shrinks back into the event, then goes.
    await mouse.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('card Dentist'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the event grows into its card, in place', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await pump(tester);
    final blockRect = tester.getRect(block);
    final mouse = await tester.createGesture(kind: .mouse);
    await mouse.addPointer(location: .zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(blockRect.center);
    // The hover delay, then the first frame of the card: still the block's size.
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    final card = find.ancestor(
      of: find.text('card Dentist'),
      matching: find.byType(Material),
    );
    final start = tester.getRect(card.first);
    expect(start.width, lessThan(blockRect.width * 2));

    await tester.pumpAndSettle();
    final end = tester.getRect(card.first);
    expect(end.width, greaterThan(start.width * 2));
    // Grown where the event is, not beside it.
    expect(end.left, closeTo(blockRect.left, 40));
    // As tall as what it shows: a short card stood half empty at the maximum height.
    expect(end.height, lessThan(HiwiskiMetrics.weekPreviewMaxHeight / 2));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the now line moves on with the clock, and at once when the app '
      'comes back', (tester) async {
    // Wednesday of the week shown, running with the test's fake time; [away] is time
    // that passes while the app is in the background and its timers are held.
    final fake = clock;
    final started = fake.now();
    Duration away = .zero;
    final wednesday = Clock(
      () => DateTime(
        2026,
        10,
        14,
        10,
        0,
        30,
      ).add(fake.now().difference(started) + away),
    );

    await withClock(wednesday, () async {
      await pump(tester);
      final nowLine = find.byWidgetPredicate(
        (widget) => '${widget.runtimeType}' == '_NowLine',
      );
      final hour = lineOf(tester, '12:00') - lineOf(tester, '11:00');
      final atTen = tester.getTopLeft(nowLine).dy;

      // Left open, nothing else rebuilds the week.
      await tester.pump(const Duration(minutes: 30));
      expect(
        tester.getTopLeft(nowLine).dy,
        moreOrLessEquals(atTen + hour / 2, epsilon: 1),
      );

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      away = const Duration(hours: 2);
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(
        tester.getTopLeft(nowLine).dy,
        moreOrLessEquals(atTen + 2.5 * hour, epsilon: 1),
      );
    });
  });
}
