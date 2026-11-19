import 'package:flutter/material.dart';

import '../../../core/common/wire.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/choice_picker.dart';

/// The fixed choices, in minutes before the start.
const _choices = <int>[0, 5, 15, 30, 60, 1440];

/// "30 minutes before" — the same words in the sheets and in the view.
String reminderLabel(L l, int? minutes) => switch (minutes) {
  null || ReminderMinutes.none => l.calReminderNone,
  0 => l.calReminderAtStart,
  5 => l.calReminder5,
  15 => l.calReminder15,
  30 => l.calReminder30,
  60 => l.calReminder60,
  _ => l.calReminder1440,
};

/// An event's reminder as it is in effect: its own, or "… · from the calendar" when it
/// takes its calendar's default.
String eventReminderLabel(L l, int? own, int? calendarDefault) =>
    own == null && calendarDefault != null
    ? l.calReminderFromCalendar(reminderLabel(l, calendarDefault))
    : reminderLabel(l, own);

/// Picks a reminder. `null` back means cancelled; otherwise `minutes` is the choice.
///
/// For an event in a calendar with a default ([calendarDefault]) the first choice is
/// "as the calendar" (`null`), and "none" is [ReminderMinutes.none] — so the event stays
/// silent instead of falling back to the default. Without one, and for the calendar's
/// own default ([forCalendar]), "none" is `null`.
Future<({int? minutes})?> pickReminder(
  BuildContext context, {
  required int? current,
  int? calendarDefault,
  bool forCalendar = false,
}) {
  final l = L.of(context);
  final inherits = !forCalendar && calendarDefault != null;
  final options = <(int?, String)>[
    if (inherits)
      (null, l.calReminderFromCalendar(reminderLabel(l, calendarDefault))),
    (inherits ? ReminderMinutes.none : null, l.calReminderNone),
    for (final minutes in _choices) (minutes, reminderLabel(l, minutes)),
  ];
  return pickChoice<int?>(
    context,
    current: current,
    choices: [
      for (final (minutes, label) in options)
        Choice(value: minutes, label: label),
    ],
  ).then((chosen) => chosen == null ? null : (minutes: chosen.value));
}
