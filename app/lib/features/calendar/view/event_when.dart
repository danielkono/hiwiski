import 'package:intl/intl.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../domain/calendar/occurrence.dart';

/// When an occurrence takes place, in two parts: the date ("Wednesday, 7 October 2026",
/// a span for a multi-day one) and the time ("14:00 – 15:00", "All day"). The event's
/// view and a link's preview say it the same way.
({String date, String time}) occurrenceWhen(
  L l,
  String locale,
  Occurrence occurrence,
) {
  final dateFormat = DateFormat.yMMMMEEEEd(locale);
  final time = DateFormat.Hm(locale);
  if (occurrence.allDay) {
    return (
      date: occurrence.isMultiDay
          ? '${dateFormat.format(occurrence.start)} – '
                '${dateFormat.format(occurrence.end)}'
          : dateFormat.format(occurrence.start),
      time: l.calAllDay,
    );
  }
  return (
    date: dateFormat.format(occurrence.start),
    time: occurrence.end.isAfter(occurrence.start)
        ? l.calTimeRange(
            time.format(occurrence.start),
            time.format(occurrence.end),
          )
        : l.calTimeFrom(time.format(occurrence.start)),
  );
}
