import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:hiwiski/domain/calendar/calendar_items.dart';
import 'package:hiwiski/domain/calendar/occurrence.dart';
import 'package:hiwiski/features/calendar/overview/view/pinned_strip.dart';

/// **An event over several days says "from–to" in the list too**, not only in the
/// pinned strip (calendar list).
void main() {
  setUpAll(() => initializeDateFormatting('de'));

  Occurrence occurrence(DateTime start, DateTime end, {required bool allDay}) =>
      .new(
        event: CalendarEvent(
          id: 'e1',
          ownerId: 'anna',
          version: 1,
          tags: '',
          calendarId: 'c1',
          title: 'Trip',
          timeForm: allDay ? 'ALL_DAY' : 'TIMED',
          timeZone: 'Europe/Berlin',
          exceptions: '',
          attendees: '',
        ),
        start: start,
        end: end,
        allDay: allDay,
      );

  test('all day: the dates', () {
    final span = occurrence(
      DateTime(2026, 9, 29),
      DateTime(2026, 10, 10),
      allDay: true,
    );
    expect(spanRange(span, 'de'), equals('29.09.–10.10.'));
  });

  test('timed over several days: dates with times', () {
    final span = occurrence(
      DateTime(2026, 10, 5, 14),
      DateTime(2026, 10, 7, 10),
      allDay: false,
    );
    expect(spanRange(span, 'de'), equals('05.10. 14:00 – 07.10. 10:00'));
  });
}
