import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/data/calendar/reminder_repository.dart';

/// **A reminder keeps its id across app starts.** The plugin restores scheduled
/// reminders after a reboot by id; with `Object.hash`, which Dart seeds anew on every
/// start, the next rescheduling could not have matched them.
void main() {
  final start = DateTime.utc(2026, 10, 5, 9, 30);

  test('the id is pinned, not seeded per run', () {
    expect(ReminderRepository.idFor('e1', start), equals(1102313687));
  });

  test('occurrences of one event get different ids that fit into 31 bits', () {
    final first = ReminderRepository.idFor('e1', start);
    final second = ReminderRepository.idFor(
      'e1',
      // `start` is UTC, which has no clock change.
      // ignore: many_lints/avoid_dst_unsafe_date_arithmetic
      start.add(const Duration(days: 7)),
    );
    expect(first, isNot(second));
    expect(second, inInclusiveRange(0, 0x7fffffff));
  });
}
