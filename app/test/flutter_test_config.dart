import 'dart:async';
import 'dart:io';

/// Runs before every test file.
///
/// On the build server the tests have to run in a zone with clock changes: the calendar
/// tests about days of 23 and 25 hours prove nothing in UTC, and quietly skip there.
/// CI sets `TZ=Europe/Berlin`; this makes sure it stays set.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final shiftsClocks =
      DateTime(2026, 10, 25).timeZoneOffset !=
      DateTime(2026, 10, 26).timeZoneOffset;
  if (Platform.environment.containsKey('CI') && !shiftsClocks) {
    throw StateError(
      'The tests run in a zone without clock changes. Set TZ=Europe/Berlin.',
    );
  }
  await testMain();
}
