import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hiwiski_tokens.dart';
import '../../../domain/links/link_index.dart';
import '../../../domain/links/link_text.dart';
import '../links_view_model.dart';
import 'link_chip.dart';

/// Body text with link chips — a task's description, a note on an event.
///
/// The chips ride along in the text as `WidgetSpan`s instead of standing next to it: a
/// sentence with a link in it has to be able to wrap like any other.
///
/// **A link that does not exist, or that the reader may not see, stays plain text** —
/// no "access denied", because existence is information too.
class LinkedProse extends ConsumerWidget {
  const LinkedProse({super.key, required this.text, this.style, this.onOpen});

  final String text;
  final TextStyle? style;
  final ValueChanged<LinkItem>? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(linksViewModelProvider);
    final base = style ?? context.tokens.text.prose;
    final parts = splitReferences(text);

    if (parts.whereType<ReferencePart>().isEmpty) {
      return Text(text, style: base);
    }

    return Text.rich(
      TextSpan(
        children: [
          for (final part in parts)
            switch (part) {
              PlainPart(:final text) => TextSpan(text: text),
              final ReferencePart part => _span(index, part, base),
            },
        ],
      ),
      style: base,
    );
  }

  InlineSpan _span(LinkIndex index, ReferencePart part, TextStyle? base) {
    final target = index.resolve(part.reference);
    if (target == null) return TextSpan(text: part.fallback, style: base);
    return WidgetSpan(
      alignment: .middle,
      child: LinkChip(target: target, onOpen: onOpen),
    );
  }
}
