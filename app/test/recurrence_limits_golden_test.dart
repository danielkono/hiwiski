import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/common/recurrence.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

/// Which rules the devices expand, against `golden/recurrence-limits.json` — the
/// server refuses the same ones.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  final golden = jsonDecode(
    File('../golden/recurrence-limits.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final accepted = (golden['accepted'] as List).cast<String>();
  final refused = (golden['refused'] as List).cast<String>();

  test('the golden file contains rules', () {
    expect(accepted, isNotEmpty);
    expect(refused, isNotEmpty);
  });

  for (final rule in accepted) {
    test('expands $rule', () => expect(Recurrence.expandable(rule), isTrue));
  }
  for (final rule in refused) {
    test('does not expand $rule', () {
      expect(Recurrence.expandable(rule), isFalse);
    });
  }

  // The report's rules, each of which froze the app for more than a minute or ended
  // only when the date overflowed. A generous bound: they must not search at all.
  test('a refused rule shows once, on its start, at once', () {
    final start = DateTime(2026, 11, 3, 4);
    final watch = Stopwatch()..start();
    for (final rule in refused) {
      final occurrences = const Recurrence().expand(
        rrule: rule,
        start: start,
        timeZone: 'Europe/Berlin',
        from: DateTime(2026, 11, 2),
        to: DateTime(2026, 11, 9),
      );
      expect(occurrences, equals([start]), reason: rule);
    }
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}
