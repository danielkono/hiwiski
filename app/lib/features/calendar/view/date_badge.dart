import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_tokens.dart';

/// The day on the left of a list group: short weekday above the number, today filled
/// in `pri` — the calendar's anchor when scrolling.
class DateBadge extends StatelessWidget {
  const DateBadge({
    super.key,
    required this.day,
    required this.isToday,
    this.muted = false,
  });

  final DateTime day;
  final bool isToday;

  /// For a day with nothing on it: present, but quiet.
  final bool muted;

  static const width = HiwiskiMetrics.dateBadgeWidth;
  static const _circle = HiwiskiMetrics.dateBadgeCircle;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final locale = Localizations.localeOf(context).toString();
    final quiet = muted && !isToday;
    return SizedBox(
      width: width,
      child: Column(
        children: [
          Text(
            DateFormat.E(locale).format(day).replaceAll('.', '').toUpperCase(),
            style: context.texts.labelSmall?.copyWith(
              fontWeight: .w600,
              letterSpacing: 0.6,
              color: isToday ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: HiwiskiMetrics.space2),
          Container(
            width: _circle,
            height: _circle,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: .circle,
              color: isToday ? scheme.primary : null,
            ),
            child: Text(
              '${day.day}',
              style: context.texts.titleMedium?.copyWith(
                color: switch ((isToday, quiet)) {
                  (true, _) => scheme.onPrimary,
                  (false, true) => scheme.onSurfaceVariant,
                  (false, false) => scheme.onSurface,
                },
                fontWeight: quiet ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
