import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/calendar/calendar_items.dart';
import 'package:hiwiski/domain/calendar/occurrence.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

/// The expansion of whole events against `golden/occurrences.json`: the time forms,
/// multi-day events and the exceptions of a series.
///
/// **The server checks the same file** — it expands the agenda of the home screen
/// widget itself, so that the widget is current while the app is closed. Whoever adds a
/// case adds it right there; whoever gets it green on only one side has found the
/// difference that needs to be resolved.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  final golden = jsonDecode(
    File('../golden/occurrences.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cases = (golden['cases'] as List).cast<Map<String, dynamic>>();

  test('the golden file contains cases', () => expect(cases, isNotEmpty));

  for (final testCase in cases) {
    test(testCase['name'] as String, () {
      final fields = testCase['event'] as Map<String, dynamic>;
      final timed = fields['timeForm'] == 'TIMED';
      final actual = const EventExpander().expand(
        _event(fields),
        DateTime.parse(testCase['from'] as String),
        DateTime.parse(testCase['to'] as String),
      );

      expect(
        [
          for (final item in actual)
            {
              'start': _format(item.start, utc: timed),
              'end': _format(item.end, utc: timed),
              'allDay': item.allDay,
              'moved': item.moved,
            },
        ],
        testCase['expected'],
        reason: testCase['why'] as String?,
      );
    });
  }
}

CalendarEvent _event(Map<String, dynamic> fields) => .new(
  id: 'golden',
  ownerId: 'golden',
  version: 1,
  calendarId: 'golden',
  title: 'Golden',
  timeForm: fields['timeForm'] as String,
  startsAt: _instant(fields['startsAt']),
  endsAt: _instant(fields['endsAt']),
  startDate: _date(fields['startDate']),
  endDate: _date(fields['endDate']),
  localStart: fields['localStart'] as String?,
  localEnd: fields['localEnd'] as String?,
  timeZone: fields['timeZone'] as String?,
  rrule: fields['rrule'] as String?,
  exceptions: jsonEncode(fields['exceptions'] ?? <String, dynamic>{}),
  attendees: '',
  tags: '',
);

DateTime? _instant(Object? raw) => raw == null ? null : .parse(raw as String);

/// A date as the database hands it over: the local midnight of that day.
DateTime? _date(Object? raw) {
  if (raw == null) return null;
  final parsed = DateTime.parse(raw as String);
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// TIMED results are instants: formatted in UTC, so the case holds on any machine.
String _format(DateTime value, {required bool utc}) {
  final shown = utc ? value.toUtc() : value;
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${shown.year.toString().padLeft(4, '0')}-${pad(shown.month)}-'
      '${pad(shown.day)}T${pad(shown.hour)}:${pad(shown.minute)}'
      '${utc ? 'Z' : ''}';
}
