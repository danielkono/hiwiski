import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/common/wire.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/common/date_patterns.dart';
import '../../../../domain/calendar/occurrence.dart';
import '../../../../core/ui/color_tokens.dart';
import '../../../../domain/calendar/calendar_items.dart';
import '../../../../core/routing/item_navigation.dart';

/// The pinned strip for all-day and multi-day events.
///
/// "Summer holidays 29.09.–10.10." — **once with "from–to", not again on every day**.
/// That is the difference from a list that shows the same row twelve
/// times and blocks the view of everything else.
class PinnedStrip extends ConsumerWidget {
  const PinnedStrip({
    super.key,
    required this.occurrences,
    required this.calendars,
    required this.padding,
  });

  final List<Occurrence> occurrences;
  final Map<String, Calendar> calendars;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context).toString();
    final format = DateFormat(DatePatterns.dayMonth, locale);

    return Padding(
      padding: padding.add(const .only(top: HiwiskiMetrics.space4)),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          for (final occurrence in occurrences)
            Padding(
              padding: const .only(bottom: HiwiskiMetrics.space6),
              child: _StripRow(
                occurrence: occurrence,
                calendar: calendars[occurrence.event.calendarId],
                label: occurrence.isMultiDay
                    ? spanRange(occurrence, locale)
                    : format.format(occurrence.start),
              ),
            ),
        ],
      ),
    );
  }
}

class _StripRow extends StatelessWidget {
  const _StripRow({
    required this.occurrence,
    required this.calendar,
    required this.label,
  });

  final Occurrence occurrence;
  final Calendar? calendar;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tint =
        context.tokens.tags[tintOf(calendar?.colorToken ?? ColorTokens.blue)]!;

    // The tinted pill from the design: background in the light calendar color, symbol,
    // title in bold, "from–to" on the right.
    return Material(
      color: tint.background,
      borderRadius: const .all(.circular(HiwiskiMetrics.radiusPill)),
      child: InkWell(
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusPill)),
        onTap: () => openOccurrence(context, occurrence),
        child: Padding(
          padding: const .symmetric(
            horizontal: HiwiskiMetrics.space12,
            vertical: HiwiskiMetrics.space8,
          ),
          child: Row(
            children: [
              Icon(
                occurrence.isMultiDay
                    ? HiwiskiSymbols.beachAccess
                    : HiwiskiSymbols.event,
                size: HiwiskiMetrics.icon18,
                color: tint.foreground,
              ),
              const SizedBox(width: HiwiskiMetrics.space10),
              Expanded(
                child: Text(
                  occurrence.event.title,
                  overflow: .ellipsis,
                  style: context.texts.bodyMedium?.copyWith(
                    color: tint.foreground,
                    fontWeight: .w500,
                  ),
                ),
              ),
              const SizedBox(width: HiwiskiMetrics.space8),
              Text(
                label,
                style: context.texts.bodySmall?.copyWith(
                  color: tint.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "29.09.–10.10." for an all-day span, "29.09. 14:00 – 01.10. 10:00" for a timed one
/// that runs over several days — the strip and the list say it the same way.
String spanRange(Occurrence occurrence, String locale) {
  final date = DateFormat(DatePatterns.dayMonth, locale);
  if (occurrence.allDay) {
    return '${date.format(occurrence.start)}–${date.format(occurrence.end)}';
  }
  final time = DateFormat.Hm(locale);
  String at(DateTime moment) => '${date.format(moment)} ${time.format(moment)}';
  return '${at(occurrence.start)} – ${at(occurrence.end)}';
}
