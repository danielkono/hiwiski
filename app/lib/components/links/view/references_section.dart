import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/ui/info_action.dart';
import '../../../core/ui/info_section.dart';
import '../../../core/ui/hiwiski_sheet.dart';
import '../../../core/ui/ui_keys.dart';
import '../../../domain/common/item_ref.dart';
import '../../../domain/links/link_index.dart';
import '../links_view_model.dart';
import 'link_item_row.dart';

/// **Links from here** and **Links to here** — the two sections of the info bar.
///
/// Both directions come from the same derivation: references live in the text of the
/// mirrored items, so the reverse direction is on the device too. That is why no call goes
/// out from here and why the bar is not empty offline.
class ReferencesSections extends ConsumerWidget {
  const ReferencesSections({super.key, required this.item, this.onOpen});

  final ItemRef item;
  final ValueChanged<LinkItem>? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final index = ref.watch(linksViewModelProvider);

    return Column(
      crossAxisAlignment: .stretch,
      spacing: HiwiskiMetrics.space20,
      children: [
        _LinkSection(
          label: l.linkOutgoing,
          items: index.outgoing(item.type, item.id),
          onOpen: onOpen,
        ),
        _LinkSection(
          label: l.linkIncoming,
          items: index.incoming(item.type, item.id),
          onOpen: onOpen,
        ),
      ],
    );
  }
}

/// One direction of links. **More than [_shown] fold into a sheet**: a much-linked page
/// pushed the rest of the info bar out of sight.
class _LinkSection extends StatelessWidget {
  const _LinkSection({required this.label, required this.items, this.onOpen});

  static const _shown = 3;

  final String label;
  final List<LinkItem> items;
  final ValueChanged<LinkItem>? onOpen;

  @override
  Widget build(BuildContext context) {
    final folded = items.length > _shown;
    return InfoSection(
      label: label,
      action: folded
          ? InfoAction(
              key: CoreKeys.linkShowAll,
              icon: HiwiskiSymbols.expandMore,
              label: L.of(context).linkShowAll(items.length),
              onTap: () => showHiwiskiSheet<void>(
                context: context,
                title: label,
                // A link from the list opens its preview on top; "Close" there comes
                // back to the list.
                builder: (context) => Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    for (final item in items)
                      LinkItemRow(target: item, onOpen: onOpen),
                  ],
                ),
              ),
            )
          : null,
      children: [
        for (final item in folded ? items.take(_shown) : items)
          LinkItemRow(target: item, onOpen: onOpen),
      ],
    );
  }
}
