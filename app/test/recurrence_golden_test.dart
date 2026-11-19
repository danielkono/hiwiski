import 'dart:convert';
import 'dart:io';

import 'package:hiwiski/domain/common/recurrence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

/// The expansion against `golden/recurrence.json`.
///
/// **The server checks the same file.** Whoever adds a case adds it right there; whoever
/// gets it green on only one side has found the difference that needs to be resolved.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  final golden = jsonDecode(
    File('../golden/recurrence.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cases = (golden['cases'] as List).cast<Map<String, dynamic>>();

  test('the golden file contains cases', () => expect(cases, isNotEmpty));

  for (final testCase in cases) {
    test(testCase['name'] as String, () {
      final actual = const Recurrence().expand(
        rrule: testCase['rrule'] as String?,
        start: DateTime.parse(testCase['start'] as String),
        timeZone: testCase['timeZone'] as String,
        from: DateTime.parse(testCase['from'] as String),
        to: DateTime.parse(testCase['to'] as String),
      );

      expect(
        actual.map(_format).toList(),
        testCase['expected'],
        reason: testCase['why'] as String?,
      );
    });
  }
}

String _format(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}T'
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';
