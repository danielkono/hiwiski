import 'package:flutter/material.dart';

import '../theme/hiwiski_metrics.dart';

/// Two fields side by side as long as each stays 160 wide — otherwise stacked
/// (in the design `repeat(auto-fit, minmax(160px, 1fr))`).
class FieldPair extends StatelessWidget {
  const FieldPair({super.key, required this.children});

  final List<Widget> children;

  static const _minWidth = 160.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = HiwiskiMetrics.space12;
      final side = children.length * _minWidth + (children.length - 1) * gap;
      if (constraints.maxWidth >= side) {
        return Row(
          crossAxisAlignment: .start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              Expanded(child: children[i]),
            ],
          ],
        );
      }
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: gap),
            children[i],
          ],
        ],
      );
    },
  );
}
