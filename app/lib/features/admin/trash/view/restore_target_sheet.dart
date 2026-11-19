import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/hiwiski_sheet.dart';
import '../trash_view_model.dart';

/// Whether an item of this type can be restored into another container.
bool hasRestoreTarget(String itemType) => switch (itemType) {
  EntityTypes.todo || EntityTypes.event || EntityTypes.wikiPage => true,
  _ => false,
};

/// Asks where an item goes whose container is gone.
///
/// Returns the chosen container, or `null` if the sheet was closed. Only containers
/// this device knows are offered — archived lists and pages and subscribed calendars
/// take nothing new. Write access is the server's call: it refuses a target the member
/// may not write.
Future<String?> showRestoreTargetSheet(
  BuildContext context, {
  required String itemType,
}) => showHiwiskiSheet<String>(
  context: context,
  title: L.of(context).trashRestoreTo,
  builder: (context) => _TargetBody(itemType: itemType),
);

class _TargetBody extends ConsumerWidget {
  const _TargetBody({required this.itemType});

  final String itemType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets =
        ref.watch(restoreTargetsViewModelProvider(itemType)).value ??
        const <RestoreTarget>[];
    final icon = switch (itemType) {
      EntityTypes.todo => HiwiskiSymbols.checklist,
      EntityTypes.event => HiwiskiSymbols.calendarMonth,
      _ => HiwiskiSymbols.description,
    };

    if (targets.isEmpty) {
      return Padding(
        padding: const .symmetric(vertical: HiwiskiMetrics.space16),
        child: Text(
          L.of(context).trashNoTarget,
          style: context.texts.bodyMedium?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        for (final (:id, :name) in targets)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, size: HiwiskiMetrics.icon18),
            title: Text(name, overflow: .ellipsis),
            onTap: () => Navigator.of(context).pop(id),
          ),
      ],
    );
  }
}
