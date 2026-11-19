import 'package:clock/clock.dart';

import '../../domain/common/calendar_days.dart';
import '../store.dart';

/// The day the calendar stands on. Set from elsewhere too: a link to an event sets it
/// to the event's day, so that "Back" lands where the event sits in the calendar.
class CalendarDayStore extends Store<DateTime> {
  CalendarDayStore() : super(startOfDay(clock.now()));

  void select(DateTime day) => value = startOfDay(day);
}
