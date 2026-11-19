import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/common/wire.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/item_navigation.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/color_tokens.dart';
import '../../../core/ui/row_chevron.dart';
import '../../../core/ui/row_divider.dart';
import '../../../domain/calendar/calendar_items.dart';
import '../../../domain/calendar/calendar_kinds.dart';
import '../../../domain/calendar/occurrence.dart';

/// One event as a row: a strip in its calendar's colour, start and end stacked, title
/// and meta, the state symbols and the arrow on the right, a line below.
///
/// **A row like a task's**, flat and parted by a line: an event is opened as a task
/// is, and a card of its own around each one made the calendar's list a different
/// kind of list. The calendar still shows at a glance — by the strip, which keeps its
/// colour on the light and the dark surface alike.
///
/// The list and the month's day card show the same row — an event looks the same
/// wherever it appears.
class EventTile extends StatelessWidget {
  const EventTile({
    super.key,
    required this.occurrence,
    required this.calendar,
  });

  final Occurrence occurrence;
  final Calendar? calendar;

  static const _timeColumnWidth = HiwiskiMetrics.eventTimeColumnWidth;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;
    final color = context.tokens.accent(
      accentOf(calendar?.colorToken ?? ColorTokens.blue),
    );
    final time = DateFormat.Hm(Localizations.localeOf(context).toString());
    final locked = isLockedCalendar(calendar?.kind);

    // "Mom · Gartenstraße 4" — calendar and location.
    final meta = [
      ?calendar?.name,
      if (occurrence.event.location case final location?
          when location.isNotEmpty)
        location,
    ].join(' · ');

    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: [
        InkWell(
          onTap: () => openOccurrence(context, occurrence),
          child: ConstrainedBox(
            // As high as a task's row; `minHeight`, as a large system font needs
            // more.
            constraints: const BoxConstraints(
              minHeight: HiwiskiMetrics.listRowHeightTall,
            ),
            child: Padding(
              padding: const .symmetric(vertical: HiwiskiMetrics.space6),
              child: Row(
                children: [
                  Container(
                    width: HiwiskiMetrics.calendarStripeWidth,
                    height: HiwiskiMetrics.eventStripeHeight,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const .all(
                        .circular(HiwiskiMetrics.calendarStripeWidth),
                      ),
                    ),
                  ),
                  const SizedBox(width: HiwiskiMetrics.space12),
                  SizedBox(
                    width: _timeColumnWidth,
                    child: occurrence.allDay
                        ? Text(
                            l.calAllDay,
                            style: context.texts.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          )
                        : Column(
                            crossAxisAlignment: .start,
                            children: [
                              Text(
                                time.format(occurrence.start),
                                style: context.texts.bodySmall?.copyWith(
                                  fontWeight: .w600,
                                ),
                              ),
                              Text(
                                time.format(occurrence.end),
                                style: context.texts.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(width: HiwiskiMetrics.space10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        Text(
                          occurrence.event.title,
                          maxLines: 2,
                          overflow: .ellipsis,
                          style: context.texts.bodyLarge?.copyWith(
                            fontWeight: .w500,
                          ),
                        ),
                        if (meta.isNotEmpty)
                          Padding(
                            padding: const .only(top: HiwiskiMetrics.space4),
                            child: Text(
                              meta,
                              maxLines: 1,
                              overflow: .ellipsis,
                              style: context.texts.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (occurrence.isSeries)
                    Padding(
                      padding: const .only(left: HiwiskiMetrics.space4),
                      child: Icon(
                        HiwiskiSymbols.repeat,
                        size: HiwiskiMetrics.icon16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (locked)
                    Padding(
                      padding: const .only(left: HiwiskiMetrics.space4),
                      child: Icon(
                        HiwiskiSymbols.lock,
                        size: HiwiskiMetrics.icon16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(width: HiwiskiMetrics.space4),
                  const RowChevron(),
                ],
              ),
            ),
          ),
        ),
        const RowDivider(),
      ],
    );
  }
}
