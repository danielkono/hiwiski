import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/links/link_text.dart';
import '../links_view_model.dart';
import 'link_chip.dart';

/// A link to an item in a text being written formatted: the chip with the target's
/// **current** title, as the read page draws it.
///
/// Where the target is not there for the reader — unknown, or not visible to them —
/// the words that stand in for it on the read page instead ([ReferencePart.fallback]),
/// in the text's own [style]. Not tappable: in the editor a tap places the cursor.
class ReferenceChip extends ConsumerWidget {
  const ReferenceChip({super.key, required this.part, this.style});

  final ReferencePart part;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(
      linksViewModelProvider.select((index) => index.resolve(part.reference)),
    );
    if (target == null) return Text(part.fallback, style: style);
    return LinkChip(target: target);
  }
}
