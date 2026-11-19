import 'package:hiwiski/domain/common/recurrence_spec.dart';
import 'package:flutter_test/flutter_test.dart';

/// "**The recurrence dialog must be able to do what the server and the expansion can
/// do:** interval, weekdays, nth weekday of the month, `COUNT` and `UNTIL`. An earlier version only
/// offered daily/weekly/monthly/yearly and threw away the rest."
///
/// Both are checked: that each of these five options finds its way into the `RRULE` —
/// and that it arrives again when read back. A dialog that produces a rule it does not
/// recognize itself mangles it on the next save.
///
/// **Without the `RRULE:` prefix**, just as the server stores it. With the prefix the
/// ICS export contained `RRULE:RRULE:FREQ=WEEKLY`, and another calendar program could
/// not read the series.
void main() {
  group('what an earlier version could not do', () {
    test('interval: every 2 weeks', () {
      const spec = RecurrenceSpec(
        frequency: .weekly,
        interval: 2,
        weekdays: {DateTime.wednesday},
      );
      expect(spec.toRrule(), equals('FREQ=WEEKLY;INTERVAL=2;BYDAY=WE'));
    });

    test('weekdays', () {
      const spec = RecurrenceSpec(
        frequency: .weekly,
        weekdays: {DateTime.friday, DateTime.monday, DateTime.wednesday},
      );
      // Ascending, so that the same selection always yields the same string.
      expect(spec.toRrule(), equals('FREQ=WEEKLY;BYDAY=MO,WE,FR'));
    });

    test('nth weekday of the month', () {
      const spec = RecurrenceSpec(
        frequency: .monthly,
        monthlyMode: .nthWeekday,
        nth: 2,
        nthWeekday: DateTime.tuesday,
      );
      expect(spec.toRrule(), equals('FREQ=MONTHLY;BYDAY=2TU'));
    });

    test('last weekday of the month', () {
      const spec = RecurrenceSpec(
        frequency: .monthly,
        monthlyMode: .nthWeekday,
        nth: -1,
        nthWeekday: DateTime.friday,
      );
      expect(spec.toRrule(), equals('FREQ=MONTHLY;BYDAY=-1FR'));
    });

    test('COUNT', () {
      const spec = RecurrenceSpec(frequency: .daily, end: .count, count: 10);
      expect(spec.toRrule(), equals('FREQ=DAILY;COUNT=10'));
    });

    test('UNTIL includes the chosen day', () {
      final spec = RecurrenceSpec(
        frequency: .daily,
        end: .until,
        until: DateTime(2026, 10, 31),
      );
      // The end of the chosen day *here*, as a UTC instant — not 23:59:59 UTC, which
      // in Berlin is 00:59 the next day and in New York 19:59 the same day.
      final end = DateTime(2026, 10, 31, 23, 59, 59).toUtc();
      String two(int value) => value.toString().padLeft(2, '0');
      expect(
        spec.toRrule(),
        equals(
          'FREQ=DAILY;UNTIL=${end.year}${two(end.month)}${two(end.day)}'
          'T${two(end.hour)}${two(end.minute)}${two(end.second)}Z',
        ),
      );
      expect(
        RecurrenceSpec.parse(spec.toRrule()).until,
        equals(DateTime(2026, 10, 31)),
      );
    });

    test('UNTIL in the old end-of-day-in-UTC form keeps its date', () {
      expect(
        RecurrenceSpec.parse('FREQ=DAILY;UNTIL=20261031T235959Z').until,
        equals(DateTime(2026, 10, 31)),
      );
    });
  });

  group('round trip', () {
    final cases = <RecurrenceSpec>[
      const RecurrenceSpec(frequency: .daily),
      const RecurrenceSpec(
        frequency: .weekly,
        interval: 2,
        weekdays: {DateTime.monday, DateTime.thursday},
      ),
      const RecurrenceSpec(
        frequency: .monthly,
        monthlyMode: .nthWeekday,
        nth: 3,
        nthWeekday: DateTime.sunday,
      ),
      const RecurrenceSpec(
        frequency: .yearly,
        interval: 2,
        end: .count,
        count: 5,
      ),
      RecurrenceSpec(
        frequency: .weekly,
        weekdays: const {DateTime.saturday},
        end: .until,
        until: DateTime(2027),
      ),
    ];

    for (final spec in cases) {
      test(spec.toRrule(), () {
        expect(spec.toRrule(), isNot(startsWith('RRULE:')));
        expect(RecurrenceSpec.parse(spec.toRrule()), equals(spec));
        expect(RecurrenceSpec.understands(spec.toRrule()), isTrue);
        // A rule with the prefix must still be read: it may come from an
        // import.
        expect(RecurrenceSpec.parse('RRULE:${spec.toRrule()}'), equals(spec));
      });
    }
  });

  group('a foreign rule is not mangled', () {
    test('the dialog does not understand BYSETPOS', () {
      expect(
        RecurrenceSpec.understands('FREQ=MONTHLY;BYDAY=MO;BYSETPOS=-1'),
        isFalse,
      );
    });

    test('the dialog does not understand BYMONTH', () {
      expect(RecurrenceSpec.understands('FREQ=YEARLY;BYMONTH=3'), isFalse);
    });

    test('the dialog does not understand several nth weekdays', () {
      expect(RecurrenceSpec.understands('FREQ=MONTHLY;BYDAY=1MO,3MO'), isFalse);
    });

    test('the dialog does not understand weekdays without WEEKLY', () {
      // `FREQ=DAILY;BYDAY=MO,TU` means something different from "weekly on Mondays and
      // Tuesdays" — the dialog would offer no representation for it.
      expect(RecurrenceSpec.understands('FREQ=DAILY;BYDAY=MO,TU'), isFalse);
    });
  });

  // A frequency the dialog does not offer is a foreign rule — shown, not rewritten
  // into "every 4 weeks" on save.
  test('an hourly rule is not the dialog\'s to edit', () {
    expect(RecurrenceSpec.understands('FREQ=HOURLY;INTERVAL=4'), isFalse);
    expect(RecurrenceSpec.understands('INTERVAL=2'), isFalse);
    expect(RecurrenceSpec.understands('FREQ=DAILY;INTERVAL=2'), isTrue);
  });

  // Every second week with WKST=SU: dropping the week start on save moved the Sunday
  // occurrences by a week. Such a rule is shown, not edited.
  test('a week start other than Monday is not the dialog\'s to edit', () {
    expect(
      RecurrenceSpec.understands('FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,MO;WKST=SU'),
      isFalse,
    );
    expect(
      RecurrenceSpec.understands('FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,MO;WKST=MO'),
      isTrue,
    );
  });

  test('the 29th to 31st are the last of their weekday, never the fifth', () {
    expect(RecurrenceSpec.nthOfMonth(DateTime(2026, 12, 29)), equals(-1));
    expect(RecurrenceSpec.nthOfMonth(DateTime(2026, 12, 31)), equals(-1));
    expect(RecurrenceSpec.nthOfMonth(DateTime(2026, 12, 22)), equals(4));
    expect(RecurrenceSpec.nthOfMonth(DateTime(2026, 12, 1)), equals(1));
  });
}
