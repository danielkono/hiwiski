import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../common/wire.dart';

/// Loads the zone database and reads the device's zone.
///
/// Without [tz_data.initializeTimeZones] `timezone` knows **not a single zone**, and the
/// expansion silently falls back to UTC — `UNTIL` would then end an hour too early or
/// too late depending on the season. A bug that only shows up sometimes is the worst
/// kind; that is why initialization happens at startup and not in a `lazy` path.
Future<String> loadDeviceTimeZone() async {
  tz_data.initializeTimeZones();
  try {
    final name = await FlutterTimezone.getLocalTimezone();
    // Check whether the database knows it: Windows reports names that are not IANA.
    tz.getLocation(name.identifier);
    return name.identifier;
  } on Object catch (_) {
    if (kDebugMode) {
      debugPrint('hiwiski: local time zone unavailable, falling back to UTC');
    }
    return utcTimeZone;
  }
}
