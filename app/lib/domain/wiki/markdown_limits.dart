/// The most characters one block of Markdown text may have to be rendered as
/// Markdown.
///
/// The `markdown` package's inline parser is quadratic in some inputs: 160 KB of
/// `[a](` took 17 s to render, 80 KB of `*a` 10 s — for every reader, on every
/// render. Below this size the worst of them stays
/// well under a second; a text with a longer block is shown as plain text. No family
/// note has a paragraph that long.
const maxMarkdownBlock = 10000;

/// Whether every block of [text] that the inline parser reads as one — a paragraph:
/// lines up to a blank line, a list item, a heading or a table row — has at most
/// [maxMarkdownBlock] characters. Fenced code is not parsed inline and not counted.
///
/// Linear in the length of [text], and conservative: a block it counts may be several
/// to the parser, never the other way round.
bool renderableAsMarkdown(String text) {
  if (text.length <= maxMarkdownBlock) return true;
  int run = 0;
  bool fenced = false;
  for (final line in text.split('\n')) {
    final trimmed = line.trimLeft();
    if (_fence.hasMatch(trimmed)) {
      fenced = !fenced;
      run = 0;
      continue;
    }
    if (fenced) continue;
    if (trimmed.trim().isEmpty || _startsBlock.hasMatch(trimmed)) run = 0;
    run += line.length + 1;
    if (run > maxMarkdownBlock) return false;
  }
  return true;
}

final _fence = RegExp('^(```|~~~)');

/// A list item, a heading or a table row: inline text of its own.
final _startsBlock = RegExp(r'^([-*+][ \t]|\d{1,9}[.)][ \t]|#|\|)');
