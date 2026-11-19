import 'package:flutter/material.dart';

import '../common/wire.dart';
import '../theme/hiwiski_accents.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';
import '../theme/hiwiski_tokens.dart';

/// A list's symbol by its kind: `checklist`, `shopping_cart`, or `view_kanban` for a
/// board.
IconData listKindIcon(String kind) => switch (kind) {
  ListKinds.shopping => HiwiskiSymbols.shoppingCart,
  ListKinds.kanban => HiwiskiSymbols.viewKanban,
  _ => HiwiskiSymbols.checklist,
};

/// A list's icon tile: `checklist` on `pc` for tasks, `shopping_cart` on the shopping
/// orange for shopping, `view_kanban` on `pc` for a board.
///
/// One component, because it appears in four places — overview, start widget, search,
/// shopping sheet — and has to look the same in all four.
class ListKindTile extends StatelessWidget {
  const ListKindTile({
    super.key,
    required this.kind,
    this.size = HiwiskiMetrics.tileSize,
  });

  final String kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final shopping = kind == ListKinds.shopping;
    final amber = context.tokens.tag(TagToken.amber);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: shopping ? amber.background : scheme.primaryContainer,
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusMenu)),
      ),
      child: Icon(
        listKindIcon(kind),
        size: size * 0.55,
        color: shopping ? amber.foreground : scheme.onPrimaryContainer,
      ),
    );
  }
}
