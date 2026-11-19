import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/hiwiski_symbols.dart';
import 'notice_bar.dart';
import 'ui_keys.dart';

/// "Archived by Anna on 12.03.2026 — read-only." with "Restore" — above the content.
///
/// Without [onRestore] the line stays, the button does not: whoever may only read sees
/// why nothing can be changed, but cannot bring it back.
class ArchivedBanner extends StatelessWidget {
  const ArchivedBanner({
    super.key,
    required this.archivedAt,
    this.archivedBy,
    this.onRestore,
  });

  final DateTime archivedAt;

  /// The display name of whoever archived — `null` when unknown (removed member).
  final String? archivedBy;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).toString();
    final name = archivedBy;
    final date = DateFormat.yMd(locale).format(archivedAt.toLocal());
    return NoticeBar(
      key: CoreKeys.archivedBanner,
      icon: HiwiskiSymbols.inventory2,
      text: name == null
          ? l.archivedBannerOn(date)
          : l.archivedBannerBy(name, date),
      actionLabel: onRestore == null ? null : l.archiveRestore,
      onAction: onRestore,
    );
  }
}
