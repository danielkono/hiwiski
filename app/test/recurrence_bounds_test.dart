import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/common/recurrence.dart';
import 'package:rrule/rrule.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// A rule from a shared calendar or a subscribed feed is expanded on every reader's
/// device. A hostile one froze the app: a minutely rule from 1990 took 14 s per
/// expansion.
// A generous bound: the tests run as debug JIT, on shared CI runners too. The bugs they
// guard against took 14 and 30 seconds; five seconds still catches them without
// turning red on a slow runner.
const _budget = Duration(seconds: 5);

void main() {
  setUpAll(tzdata.initializeTimeZones);

  const recurrence = Recurrence();
  const zone = 'Europe/Berlin';
  final from = DateTime(2026, 11, 2);
  final to = DateTime(2026, 11, 9);

  List<DateTime> expand(String rrule, DateTime start) => recurrence.expand(
    rrule: rrule,
    start: start,
    timeZone: zone,
    from: from,
    to: to,
  );

  test('a minutely rule over decades returns fast, from the window on', () {
    final watch = Stopwatch()..start();

    final minutes = expand('FREQ=MINUTELY', DateTime(1990));
    final seconds = expand('FREQ=SECONDLY', DateTime(1990));
    final odd = expand('FREQ=MINUTELY;INTERVAL=7', DateTime(1990, 1, 1, 0, 3));

    expect(watch.elapsed, lessThan(_budget));
    expect(minutes, hasLength(Recurrence.maxOccurrences));
    expect(minutes.first, equals(from));
    // The `rrule` package cannot step a secondly rule; it must not hang on it.
    expect(seconds.length, lessThanOrEqualTo(1));
    // On the series' own beat: every seventh minute counted from 00:03 in 1990.
    final sinceStart = odd.first.difference(DateTime(1990, 1, 1, 0, 3));
    expect(sinceStart.inMinutes % 7, equals(0));
    expect(odd.first.isBefore(from.add(const Duration(minutes: 7))), isTrue);
  });

  test('a rule that never occurs returns fast', () {
    final watch = Stopwatch()..start();

    final never = expand('FREQ=DAILY;BYMONTH=2;BYMONTHDAY=30', DateTime(2020));

    expect(watch.elapsed, lessThan(_budget));
    expect(never, isEmpty);
  });

  test('a rule whose instances mostly fall before the window stops', () {
    final watch = Stopwatch()..start();

    // COUNT counts from the first occurrence, so it cannot skip ahead.
    final counted = expand('FREQ=MINUTELY;COUNT=2000000000', DateTime(1990));

    expect(watch.elapsed, lessThan(_budget));
    expect(counted, isEmpty);
  });

  // Skipping ahead must not change a single occurrence. The reference steps from the
  // first one, as the expansion used to; starts are kept close enough for that.
  group('skipping ahead yields what stepping yields', () {
    final cases = <(String, DateTime)>[
      ('FREQ=DAILY;INTERVAL=3', DateTime(2024, 3, 5, 8, 30)),
      ('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH', DateTime(2024, 1, 4, 18)),
      ('FREQ=WEEKLY;BYDAY=MO,FR;BYSETPOS=1', DateTime(2025, 6, 6, 9)),
      ('FREQ=DAILY;BYHOUR=2,20;BYMINUTE=30', DateTime(2025, 3, 1)),
      ('FREQ=HOURLY;INTERVAL=5;BYDAY=SA', DateTime(2026, 1, 1, 1)),
      ('FREQ=MINUTELY;INTERVAL=7;BYHOUR=2', DateTime(2026, 9, 1, 0, 1)),
      ('FREQ=MINUTELY;INTERVAL=13;BYHOUR=2,3', DateTime(2026, 10, 20, 0, 5)),
      ('FREQ=MONTHLY;BYMONTHDAY=-1', DateTime(2020, 1, 31, 7)),
    ];
    // Around the end of summer time in Berlin, so the margin is exercised too.
    final windows = [
      (DateTime(2026, 10, 24), DateTime(2026, 10, 27)),
      (DateTime(2026, 3, 28, 1), DateTime(2026, 3, 30)),
      (DateTime(2026, 11, 2), DateTime(2026, 11, 9)),
    ];
    for (final (rrule, start) in cases) {
      test(rrule, () {
        for (final (windowFrom, windowTo) in windows) {
          expect(
            recurrence.expand(
              rrule: rrule,
              start: start,
              timeZone: zone,
              from: windowFrom,
              to: windowTo,
            ),
            equals(_stepping(rrule, start, zone, windowFrom, windowTo)),
            reason: '$windowFrom',
          );
        }
      });
    }
  });
}

/// The expansion as it was: every instance from the first one on.
List<DateTime> _stepping(
  String rrule,
  DateTime start,
  String zone,
  DateTime from,
  DateTime to,
) {
  final rule = RecurrenceRule.fromString('RRULE:$rrule');
  final location = tz.getLocation(zone);
  final result = <DateTime>[];
  final seed = DateTime.utc(
    start.year,
    start.month,
    start.day,
    start.hour,
    start.minute,
    start.second,
  );
  for (final naive in rule.getInstances(start: seed)) {
    final inZone = tz.TZDateTime(
      location,
      naive.year,
      naive.month,
      naive.day,
      naive.hour,
      naive.minute,
      naive.second,
    );
    final local = DateTime(
      inZone.year,
      inZone.month,
      inZone.day,
      inZone.hour,
      inZone.minute,
      inZone.second,
    );
    if (local.isBefore(from)) continue;
    if (!local.isBefore(to)) break;
    result.add(local);
    if (result.length >= Recurrence.maxOccurrences) break;
  }
  return result;
}
