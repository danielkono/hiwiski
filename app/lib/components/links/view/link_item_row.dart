import 'package:flutter/material.dart';

import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../domain/links/link_index.dart';
import 'link_chip.dart';

/// A row in the info bar: **icon, title, mono number**.
class LinkItemRow extends StatelessWidget {
  const LinkItemRow({super.key, required this.target, this.onOpen});

  final LinkItem target;
  final ValueChanged<LinkItem>? onOpen;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: switch (onOpen) {
      null => null,
      final onOpen => () => onOpen(target),
    },
    child: Padding(
      padding: const .symmetric(vertical: HiwiskiMetrics.space6),
      child: Row(
        children: [
          Icon(linkItemIcon(target.itemType), size: HiwiskiMetrics.icon20),
          const SizedBox(width: HiwiskiMetrics.space8),
          Expanded(
            child: Text(
              target.title,
              style: context.texts.bodyMedium,
              overflow: .ellipsis,
            ),
          ),
          if (target.entityKey case final key?) ...[
            const SizedBox(width: HiwiskiMetrics.space8),
            Text(key, style: context.tokens.text.entityKey),
          ],
        ],
      ),
    ),
  );
}
