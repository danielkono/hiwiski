import 'package:flutter/widgets.dart';

/// The keys the tests find this area's widgets by.
abstract final class CalendarKeys {
  static const calendarDefaultReminder = ValueKey('calendar-default-reminder');
  static const calendarName = ValueKey('calendar-name');
  static const calendarPinnedStrip = ValueKey('calendar-pinned-strip');
  static const eventLocation = ValueKey('event-location');
  static const eventNote = ValueKey('event-note');
  static const eventTitle = ValueKey('event-title');
  static const feedName = ValueKey('feed-name');
  static const importCalendar = ValueKey('import-calendar');
  static const importFile = ValueKey('import-file');
  static const importLocked = ValueKey('import-locked');
  static const importName = ValueKey('import-name');
  static const importPickFile = ValueKey('import-pick-file');
  static const importSubmit = ValueKey('import-submit');
  static const importUrl = ValueKey('import-url');
  static const subscriptionName = ValueKey('subscription-name');
  static const subscriptionUrl = ValueKey('subscription-url');

  static const _dueTask = 'due-task-';
  static ValueKey<String> dueTask(String todoId) => .new('$_dueTask$todoId');

  static const _spanChip = 'span-chip-';
  static ValueKey<String> spanChip(String eventId) =>
      .new('$_spanChip$eventId');
}
