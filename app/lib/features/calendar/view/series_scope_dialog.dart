import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../domain/calendar/occurrence.dart';

/// "For a series event, saving asks: **only this event / this and all following / the
/// whole series.**"
///
/// The question comes **before** writing, not afterwards as a follow-up: whoever only
/// sees it afterwards has already made the mistake.
Future<SeriesScope?> askSeriesScope(
  BuildContext context, {
  required bool deleting,
}) {
  final l = L.of(context);
  return showDialog<SeriesScope>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(deleting ? l.calScopeDeleteQuestion : l.calScopeQuestion),
      contentPadding: const .only(bottom: HiwiskiMetrics.space12),
      children: [
        for (final entry in {
          SeriesScope.onlyThis: l.calScopeOnlyThis,
          SeriesScope.thisAndFollowing: l.calScopeFollowing,
          SeriesScope.wholeSeries: l.calScopeAll,
        }.entries)
          ListTile(
            title: Text(entry.value),
            onTap: () => Navigator.of(context).pop(entry.key),
          ),
      ],
    ),
  );
}
