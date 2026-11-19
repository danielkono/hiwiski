import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/calendar/calendar_tags.dart';
import 'package:hiwiski/domain/calendar/calendar_items.dart';

/// **A calendar's tags apply to all of its events** — imported and subscribed ones too.
void main() {
  CalendarEvent event(String tags) => .new(
    id: 'e1',
    ownerId: 'anna',
    version: 1,
    tags: tags,
    calendarId: 'c1',
    title: 'School holidays',
    timeForm: 'ALL_DAY',
    timeZone: 'Europe/Berlin',
    exceptions: '',
    attendees: '',
  );

  Calendar calendar(String tags) => .new(
    id: 'c1',
    ownerId: 'anna',
    version: 1,
    name: 'School',
    colorToken: 'BLUE',
    kind: 'EXTERNAL',
    position: 0,
    tags: tags,
  );

  test("the event's own tags and the calendar's, each once", () {
    expect(
      effectiveEventTags(event('kids'), calendar('school,kids')).split(','),
      equals(['kids', 'school']),
    );
  });

  test('without a calendar or calendar tags, the own ones', () {
    expect(effectiveEventTags(event('kids'), null), equals('kids'));
    expect(effectiveEventTags(event('kids'), calendar('')), equals('kids'));
  });
}
