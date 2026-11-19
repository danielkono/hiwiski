import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../../../domain/wiki/markdown_editing.dart';
import '../../../../../domain/wiki/wiki_page.dart';
import 'text_block.dart';

/// A page's whole text as [TextBlock]s, one after the other — where it is not built
/// as slivers: a recipe's preparation. Images on lines of their own show as images
/// and stacks here too, and a box's number counts across the blocks.
class TextBlocks extends StatelessWidget {
  const TextBlocks({
    super.key,
    required this.page,
    required this.writable,
    required this.styleSheet,
  });

  final WikiPage page;
  final bool writable;
  final MarkdownStyleSheet styleSheet;

  @override
  Widget build(BuildContext context) {
    final chunks = markdownChunks(page.content);
    final blocks = <Widget>[];
    int offset = 0;
    for (final (i, chunk) in chunks.indexed) {
      blocks.add(
        TextBlock(
          page: page,
          chunk: chunk,
          first: i == 0,
          offset: offset,
          writable: writable,
          styleSheet: styleSheet,
        ),
      );
      offset += taskCount(chunk);
    }
    return Column(crossAxisAlignment: .stretch, children: blocks);
  }
}
