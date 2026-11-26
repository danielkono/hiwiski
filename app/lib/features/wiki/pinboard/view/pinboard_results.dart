import 'package:flutter/material.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/row_divider.dart';
import '../../../../domain/wiki/pinboard.dart';
import '../../view/pinboard/pinboard_scene.dart';
import 'pinboard_keys.dart';

/// What a search on the canvas found, as a list in the order chosen above it: a tap
/// goes to the element and marks it. The list a screen reader reads the map by, too.
class PinboardResults extends StatelessWidget {
  const PinboardResults({
    super.key,
    required this.hits,
    required this.current,
    required this.onTap,
    required this.order,
    required this.descending,
    required this.onOrder,
  });

  final List<PinboardHit> hits;

  /// The hit shown on the canvas now.
  final int current;
  final ValueChanged<int> onTap;

  /// How the hits are put in order, and a change of it.
  final PinboardHitOrder order;
  final bool descending;
  final void Function(PinboardHitOrder order, bool descending) onOrder;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    String nameOf(PinboardHitOrder order) => switch (order) {
      .place => l.pinboardOrderPlace,
      .alphabetical => l.pinboardOrderAlphabetical,
      .created => l.pinboardOrderCreated,
    };
    return Material(
      color: context.scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Padding(
            padding: const .symmetric(horizontal: HiwiskiMetrics.space8),
            child: Row(
              children: [
                Expanded(
                  child: PopupMenuButton<PinboardHitOrder>(
                    key: PinboardKeys.hitOrder,
                    tooltip: l.pinboardOrderBy,
                    initialValue: order,
                    onSelected: (chosen) => onOrder(chosen, descending),
                    itemBuilder: (_) => [
                      for (final choice in PinboardHitOrder.values)
                        PopupMenuItem(
                          key: PinboardKeys.hitOrderOf(choice.name),
                          value: choice,
                          child: Text(nameOf(choice)),
                        ),
                    ],
                    child: Padding(
                      padding: const .symmetric(
                        horizontal: HiwiskiMetrics.space8,
                        vertical: HiwiskiMetrics.space12,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            HiwiskiSymbols.sort,
                            size: HiwiskiMetrics.icon20,
                          ),
                          const SizedBox(width: HiwiskiMetrics.space8),
                          Flexible(
                            child: Text(
                              nameOf(order),
                              maxLines: 1,
                              overflow: .ellipsis,
                              style: context.texts.labelLarge,
                            ),
                          ),
                          const Icon(
                            HiwiskiSymbols.arrowDropDown,
                            size: HiwiskiMetrics.icon20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: PinboardKeys.hitDirection,
                  tooltip: descending
                      ? l.pinboardOrderDescending
                      : l.pinboardOrderAscending,
                  icon: Icon(
                    descending
                        ? HiwiskiSymbols.arrowDownward
                        : HiwiskiSymbols.arrowUpward,
                  ),
                  onPressed: () => onOrder(order, !descending),
                ),
              ],
            ),
          ),
          const RowDivider(),
          Expanded(
            child: _HitList(hits: hits, current: current, onTap: onTap),
          ),
        ],
      ),
    );
  }
}

class _HitList extends StatelessWidget {
  const _HitList({
    required this.hits,
    required this.current,
    required this.onTap,
  });

  final List<PinboardHit> hits;
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return ListView.separated(
      // Not the screen's safe area: the list lies at the foot of the screen or
      // beside the map, below the header — given the room at the top, a phone
      // showed a strip of nothing above the first hit.
      padding: .zero,
      itemCount: hits.length,
      separatorBuilder: (_, _) => const RowDivider(),
      itemBuilder: (context, index) {
        final hit = hits[index];
        return ListTile(
          key: PinboardKeys.hit(hit.id),
          selected: index == current,
          dense: true,
          leading: Icon(
            hit.isEdge
                ? HiwiskiSymbols.timeline
                : PinboardElementView.iconOfKind(hit.kind),
            size: HiwiskiMetrics.icon20,
          ),
          title: Text(hit.snippet, maxLines: 2, overflow: .ellipsis),
          subtitle: hit.isEdge ? Text(l.pinboardEdge) : null,
          onTap: () => onTap(index),
        );
      },
    );
  }
}
