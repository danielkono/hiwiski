/// How the formatted editor shows a Markdown text — **the text itself stays the
/// source**.
///
/// The editor does not translate Markdown into a document model and back: what is saved
/// and synced, what the server reads its links from and what an export writes is the
/// text as typed, character for character. Only the way it is drawn changes. Headings
/// are large, `**bold**` is bold, a list item shows a bullet, a task a box, a link its
/// chip, an image line the image; the Markdown that does that is hidden.
///
/// - **Inline markers** (`**`, `*`, `~~`, `` ` ``, a link's brackets and address) show,
///   faded, while the cursor touches what they format — so they can be edited — and
///   are hidden otherwise.
/// - **A line's prefix** (`## `, `- `, `- [ ] `, `> `) and **a chip or an image** are
///   one piece: the cursor does not go into them ([MarkdownPreview.snap]), and Backspace
///   takes them as a whole ([MarkdownPreview.backspace]).
///
/// Every character keeps its place, so the offsets of the text are the offsets of what
/// is drawn: selection, the `#` suggestions and the toolbar work on the text as before.
/// This file only says what each character is; how that looks is the view's business.
library;

import 'dart:typed_data';

import '../../core/common/app_names.dart';
import '../common/match_groups.dart';
import '../links/link_text.dart';
import 'markdown_editing.dart';

/// What a character is, as bits — several at once (bold in a heading in a quote).
abstract final class PreviewFlags {
  static const bold = 1 << 0;
  static const italic = 1 << 1;
  static const strike = 1 << 2;

  /// Inline code.
  static const code = 1 << 3;

  /// A line of a fenced code block, its fences included.
  static const codeBlock = 1 << 4;
  static const quote = 1 << 5;

  /// A link's label, or a bare address.
  static const link = 1 << 6;

  /// Markdown syntax that is shown, faded — the cursor is at it.
  static const marker = 1 << 7;

  /// Markdown syntax that is not drawn.
  static const hidden = 1 << 8;

  /// A table row: kept as typed, in mono, so its columns line up.
  static const table = 1 << 9;

  /// The indentation in front of a list item, drawn wider than spaces are — the only
  /// thing that shows how deep it is nested.
  static const indent = 1 << 10;

  /// A horizontal rule (`---`).
  static const rule = 1 << 11;

  static const _headingShift = 12;
  static const _headingMask = 7 << _headingShift;

  /// The heading level, 1 to 6, in the bits after the others.
  static int headingFlag(int level) => level << _headingShift;

  /// The heading level of [flags] — `0` for none.
  static int headingOf(int flags) => (flags & _headingMask) >> _headingShift;
}

/// What a single character is drawn as instead of itself.
sealed class PreviewWidget {
  const PreviewWidget();
}

/// The marker of a bullet list item; [depth] `0` is the outermost list.
final class PreviewBullet extends PreviewWidget {
  const PreviewBullet(this.depth);

  final int depth;
}

/// The box of a task — the [index]-th of the text, as [toggleTask] counts.
final class PreviewTaskBox extends PreviewWidget {
  const PreviewTaskBox({required this.index, required this.checked});

  final int index;
  final bool checked;
}

/// One `>` of a quote.
final class PreviewQuoteBar extends PreviewWidget {
  const PreviewQuoteBar();
}

/// An image of the media store.
final class PreviewImage extends PreviewWidget {
  const PreviewImage(this.imageId);

  final String imageId;
}

/// A link to an item — `#TD-14` or the picker's `[Title](hiwiski://…)` — as its chip.
final class PreviewReference extends PreviewWidget {
  const PreviewReference(this.part);

  final ReferencePart part;
}

/// A stretch of the text drawn one way. A run with a [widget] is one character long.
final class PreviewRun {
  const PreviewRun(this.start, this.end, this.flags, [this.widget]);

  final int start;
  final int end;
  final int flags;
  final PreviewWidget? widget;

  @override
  String toString() =>
      'PreviewRun($start, $end, $flags, ${widget?.runtimeType})';
}

/// What a line's prefix is — for Backspace at the start of its text.
enum _PrefixKind { heading, list, quote }

/// A line's prefix: from the line's start to where its text begins.
final class const _Prefix({
  required final int lineStart,

  /// Where the innermost part begins — the list marker inside a quote, say. Backspace
  /// takes that part first.
  required final int innerStart,
  required final int end,
  required final _PrefixKind kind,

  /// The spaces in front of a list item.
  final int indent = 0,
});

/// Inline syntax that shows while the cursor touches [start]–[end].
final class const _Inline(
  final int start,
  final int end,
  final List<(int, int)> syntax,
);

/// A chip or an image: [start] is drawn as [widget], the rest of it not at all.
final class const _Token(
  final int start,
  final int end,
  final PreviewWidget widget, {

  /// Whether Backspace right after it takes it whole. Not for a typed `#TD-14`: it
  /// is short, and typed by hand it is corrected by hand — one digit at a time.
  final bool wholeOnBackspace = true,
});

final _heading = RegExp(r'^(#{1,6})[ \t]+');
final _listMarker = RegExp(r'^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+)');
final _quoteMarker = RegExp(r'^[ \t]{0,3}>[ \t]?');
final _rule = RegExp(r'^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$');
final _codeSpan = RegExp(r'(`+)(.+?)(?<!`)\1(?!`)');
final _markdownLink = RegExp(r'(!?)\[((?:\\.|[^\]\\\n])*)\]\(([^()\s]*)\)');
final _autolink = RegExp(r'https?://[^\s<>()\[\]]+');
final _escape = RegExp(r'\\.');
final _digit = RegExp(r'\d');
final _bold = RegExp(r'(\*\*|__)(?=[^\s])(.+?)(?<=[^\s])\1');
final _strike = RegExp(r'~~(?=[^\s~])(.+?)(?<=[^\s~])~~');
final _italicStar = RegExp(r'(?<!\*)\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?!\*)');
final _italicUnderscore = RegExp(
  r'(?<![\w_])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\w_])',
);

/// Stands in for what is taken already — by code, a link, a marker — so that the
/// emphasis patterns neither start nor end in it.
const _taken = '\u0001';
const _pipe = '|';
const _bang = '!';
const _imagePrefix = '${UriSchemes.hiwiskiImage}:';

/// A Markdown text, read for the formatted editor. Read once per text; [runs] then
/// says how it is drawn for wherever the cursor is.
class MarkdownPreview {
  MarkdownPreview._(
    this.text,
    this._flags,
    this._widgets,
    this._inlines,
    this._tokens,
    this._prefixes,
  );

  factory MarkdownPreview.of(String text) => _Reader(text).read();

  final String text;
  final Uint32List _flags;
  final Map<int, PreviewWidget> _widgets;
  final List<_Inline> _inlines;
  final List<_Token> _tokens;

  /// In the order of the text, one per line that has a prefix.
  final List<_Prefix> _prefixes;

  /// How the text is drawn while the selection is [start]–[end] — `-1` for none, and
  /// every marker stays hidden.
  ///
  /// The runs cover the whole text, in order.
  List<PreviewRun> runs({int start = -1, int end = -1}) {
    final flags = Uint32List.fromList(_flags);
    final widgets = {..._widgets};
    final from = start < end ? start : end;
    final to = start < end ? end : start;
    for (final inline in _inlines) {
      final touched = from >= 0 && from <= inline.end && to >= inline.start;
      final mark = touched ? PreviewFlags.marker : PreviewFlags.hidden;
      for (final (a, b) in inline.syntax) {
        for (int i = a; i < b; i++) {
          flags[i] |= mark;
        }
      }
    }
    for (final token in _tokens) {
      widgets[token.start] = token.widget;
      for (int i = token.start + 1; i < token.end; i++) {
        flags[i] |= PreviewFlags.hidden;
      }
    }

    final runs = <PreviewRun>[];
    int at = 0;
    while (at < text.length) {
      final widget = widgets[at];
      if (widget != null) {
        runs.add(PreviewRun(at, at + 1, flags[at], widget));
        at++;
        continue;
      }
      int next = at + 1;
      while (next < text.length &&
          flags[next] == flags[at] &&
          !widgets.containsKey(next)) {
        next++;
      }
      runs.add(PreviewRun(at, next, flags[at]));
      at = next;
    }
    return runs;
  }

  /// Where a cursor that moved from [from] to [to] really goes: never into a line's
  /// prefix or into a chip, which are drawn as one piece.
  ///
  /// Moving left out of a line's text it lands at the end of the line above; any other
  /// way into a prefix — a tap at the left edge, Home, the line above — at the start of
  /// the text. Into a chip from its right it lands before it, otherwise after it.
  int snap(int from, int to) {
    final prefix = _prefixAt(to);
    if (prefix != null) {
      final leftOutOfText = from == prefix.end && to == prefix.end - 1;
      if (leftOutOfText && prefix.lineStart > 0) return prefix.lineStart - 1;
      return prefix.end;
    }
    for (final token in _tokens) {
      if (to > token.start && to < token.end) {
        return from >= token.end ? token.start : token.end;
      }
    }
    return to;
  }

  /// Backspace with the cursor at [cursor]: what happens instead of deleting the one
  /// character before it — `null` when that character is ordinary text.
  ///
  /// - At the start of a line's text: a nested list item moves out one level; any
  ///   other prefix goes — the innermost part first (the list marker inside a quote),
  ///   and the line is ordinary text.
  /// - Right after a chip or an image: it goes as a whole. One character of it would
  ///   leave a broken address, drawn as text.
  ({String text, int cursor})? backspace(int cursor) {
    final prefix = _prefixAt(cursor - 1);
    if (prefix != null && cursor == prefix.end) {
      if (prefix.kind == .list && prefix.indent > 0) {
        final lineStart = prefix.lineStart;
        final before = lineStart == 0
            ? const <String>[]
            : text.substring(0, lineStart - 1).split('\n');
        final lineEnd = text.indexOf('\n', lineStart);
        final line = text.substring(
          lineStart,
          lineEnd < 0 ? text.length : lineEnd,
        );
        final step = listIndentSteps(before, line).outdent;
        final innerIndentStart = prefix.innerStart;
        final take = step < prefix.indent ? step : prefix.indent;
        return (
          text: text.replaceRange(
            innerIndentStart,
            innerIndentStart + take,
            '',
          ),
          cursor: cursor - take,
        );
      }
      return (
        text: text.replaceRange(prefix.innerStart, prefix.end, ''),
        cursor: prefix.innerStart,
      );
    }
    for (final token in _tokens) {
      if (cursor == token.end && token.wholeOnBackspace) {
        return (
          text: text.replaceRange(token.start, token.end, ''),
          cursor: token.start,
        );
      }
    }
    return null;
  }

  /// The prefix of the line that holds [offset], if it has one.
  _Prefix? _prefixAt(int offset) {
    if (offset < 0) return null;
    int low = 0;
    int high = _prefixes.length - 1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      final prefix = _prefixes[middle];
      if (offset < prefix.lineStart) {
        high = middle - 1;
      } else if (offset >= prefix.end) {
        low = middle + 1;
      } else {
        return prefix;
      }
    }
    return null;
  }
}

/// Reads a text line by line into a [MarkdownPreview].
class _Reader {
  _Reader(this.text) : flags = Uint32List(text.length);

  final String text;
  final Uint32List flags;
  final widgets = <int, PreviewWidget>{};
  final inlines = <_Inline>[];
  final tokens = <_Token>[];
  final prefixes = <_Prefix>[];

  /// The indentation of the list items above that are still open, outermost first.
  final listIndents = <int>[];
  int taskIndex = 0;
  bool inFence = false;

  MarkdownPreview read() {
    int lineStart = 0;
    while (lineStart <= text.length) {
      final newline = text.indexOf('\n', lineStart);
      final lineEnd = newline < 0 ? text.length : newline;
      _line(lineStart, lineEnd);
      if (newline < 0) break;
      lineStart = newline + 1;
    }
    return MarkdownPreview._(text, flags, widgets, inlines, tokens, prefixes);
  }

  void _mark(int start, int end, int flag) {
    for (int i = start; i < end; i++) {
      flags[i] |= flag;
    }
  }

  void _line(int start, int end) {
    final line = text.substring(start, end);
    if (isFenceLine(line)) {
      _mark(start, end, PreviewFlags.codeBlock | PreviewFlags.marker);
      inFence = !inFence;
      return;
    }
    if (inFence) {
      _mark(start, end, PreviewFlags.codeBlock);
      return;
    }
    final box = taskBoxIn(line);
    // Counted for every task line, as the toggle counts them — whatever else the line
    // turns out to be here.
    final boxIndex = box == null ? null : taskIndex++;
    if (line.trim().isEmpty) return;
    if (line.trimLeft().startsWith(_pipe)) {
      _mark(start, end, PreviewFlags.table);
      return;
    }
    if (_rule.hasMatch(line)) {
      _mark(start, end, PreviewFlags.rule | PreviewFlags.marker);
      return;
    }

    // A quote's `>`s, each a bar.
    int at = start;
    int quoteEnd = start;
    while (true) {
      final quote = _quoteMarker.matchAsPrefix(text.substring(at, end));
      if (quote == null) break;
      final bar = at + quote.groupOf(0).indexOf('>');
      _mark(at, bar, PreviewFlags.hidden);
      widgets[bar] = const PreviewQuoteBar();
      at += quote.end;
      quoteEnd = at;
    }
    final quoted = quoteEnd > start;
    final rest = text.substring(at, end);

    final heading = _heading.matchAsPrefix(rest);
    final list = heading == null ? _listMarker.matchAsPrefix(rest) : null;
    int contentStart = at;
    if (heading != null) {
      final level = heading.groupOf(1).length;
      contentStart = at + heading.end;
      _mark(at, contentStart, PreviewFlags.hidden);
      _mark(contentStart, end, PreviewFlags.headingFlag(level));
      prefixes.add(
        _Prefix(
          lineStart: start,
          innerStart: at,
          end: contentStart,
          kind: .heading,
        ),
      );
      listIndents.clear();
    } else if (list != null) {
      contentStart = _listItem(start, at, list, box, boxIndex);
    } else {
      if (quoted) {
        prefixes.add(
          _Prefix(lineStart: start, innerStart: start, end: at, kind: .quote),
        );
      }
      // Ordinary text at the left edge ends the lists above it; indented, it
      // continues the item it belongs to.
      if (!rest.startsWith(' ') && !rest.startsWith('\t')) listIndents.clear();
    }
    if (quoted) _mark(quoteEnd, end, PreviewFlags.quote);
    _inline(contentStart, end);
  }

  /// A list item from its marker on; returns where its text begins.
  int _listItem(
    int lineStart,
    int at,
    Match marker,
    ({int at, bool checked})? box,
    int? boxIndex,
  ) {
    final indent = marker.groupOf(1).length;
    final markerStart = at + indent;
    final markerText = marker.groupOf(2);
    final spacesEnd = at + marker.end;
    final bullet = !markerText.startsWith(_digit);

    while (listIndents.isNotEmpty && listIndents.last > indent) {
      listIndents.removeLast();
    }
    if (listIndents.isEmpty || listIndents.last < indent) {
      listIndents.add(indent);
    }
    final depth = listIndents.length - 1;

    _mark(at, markerStart, PreviewFlags.indent);
    int end = spacesEnd;
    // The box of a task, where the toggle finds it: `[`, then ` ` or `x`, then `]`.
    if (box != null && boxIndex != null && lineStart + box.at == spacesEnd) {
      final open = spacesEnd;
      if (bullet) _mark(markerStart, spacesEnd, PreviewFlags.hidden);
      widgets[open] = PreviewTaskBox(index: boxIndex, checked: box.checked);
      _mark(open + 1, open + 3, PreviewFlags.hidden);
      // The space after `]` stays: the gap between the box and the text.
      end = open + 4;
    } else if (bullet) {
      widgets[markerStart] = PreviewBullet(depth);
    }
    prefixes.add(
      _Prefix(
        lineStart: lineStart,
        innerStart: at,
        end: end,
        kind: .list,
        indent: indent,
      ),
    );
    return end;
  }

  /// Inline syntax in [start]–[end] of one line.
  void _inline(int start, int end) {
    if (start >= end) return;
    final line = text.substring(start, end);
    final taken = List<bool>.filled(line.length, false);
    bool free(int a, int b) {
      for (int i = a; i < b; i++) {
        if (taken[i]) return false;
      }
      return true;
    }

    void take(int a, int b) {
      for (int i = a; i < b; i++) {
        taken[i] = true;
      }
    }

    for (final match in _codeSpan.allMatches(line)) {
      final ticks = match.groupOf(1).length;
      _mark(start + match.start, start + match.end, PreviewFlags.code);
      inlines.add(
        _Inline(start + match.start, start + match.end, [
          (start + match.start, start + match.start + ticks),
          (start + match.end - ticks, start + match.end),
        ]),
      );
      take(match.start, match.end);
    }

    // Links to items and images: one piece each, drawn as a chip or the image.
    for (final match in LinkScanner().allMatches(line)) {
      final reference = referenceIn(match);
      if (reference == null || !free(match.start, match.end)) continue;
      tokens.add(
        _Token(
          start + match.start,
          start + match.end,
          PreviewReference(
            ReferencePart(
              reference,
              raw: match.groupOf(0),
              label: labelIn(match),
            ),
          ),
          wholeOnBackspace: reference is! KeyReference,
        ),
      );
      take(match.start, match.end);
    }
    for (final match in _markdownLink.allMatches(line)) {
      if (!free(match.start, match.end)) continue;
      final url = match.groupOf(3);
      final bang = match.groupOf(1);
      if (bang == _bang && url.startsWith(_imagePrefix)) {
        tokens.add(
          _Token(
            start + match.start,
            start + match.end,
            PreviewImage(url.substring(_imagePrefix.length)),
          ),
        );
        take(match.start, match.end);
        continue;
      }
      // An image from elsewhere is not fetched, on the page neither
      // (`LinkedMarkdown`): it reads as a link to it.
      final labelStart = start + match.start + bang.length + 1;
      final labelEnd = labelStart + match.groupOf(2).length;
      if (labelEnd == labelStart) {
        // No label to show in place of the address: the address it is.
        _mark(start + match.start, start + match.end, PreviewFlags.link);
      } else {
        _mark(labelStart, labelEnd, PreviewFlags.link);
        inlines.add(
          _Inline(start + match.start, start + match.end, [
            (start + match.start, labelStart),
            (labelEnd, start + match.end),
          ]),
        );
      }
      take(match.start, match.end);
    }
    for (final match in _autolink.allMatches(line)) {
      if (!free(match.start, match.end)) continue;
      _mark(start + match.start, start + match.end, PreviewFlags.link);
      take(match.start, match.end);
    }

    // Emphasis, on the line with what is taken masked out — and escapes, so `\*`
    // stays a star.
    final masked = StringBuffer();
    for (int i = 0; i < line.length; i++) {
      masked.write(taken[i] ? _taken : line[i]);
    }
    String plain = masked.toString().replaceAllMapped(
      _escape,
      (match) => _taken * match.groupOf(0).length,
    );
    String emphasis(RegExp pattern, int flag, int markerLength, String source) {
      final out = source.split('');
      for (final match in pattern.allMatches(source)) {
        final a = start + match.start;
        final b = start + match.end;
        _mark(a, b, flag);
        inlines.add(
          _Inline(a, b, [(a, a + markerLength), (b - markerLength, b)]),
        );
        for (int i = 0; i < markerLength; i++) {
          out[match.start + i] = _taken;
          out[match.end - 1 - i] = _taken;
        }
      }
      return out.join();
    }

    plain = emphasis(_bold, PreviewFlags.bold, 2, plain);
    plain = emphasis(_strike, PreviewFlags.strike, 2, plain);
    plain = emphasis(_italicStar, PreviewFlags.italic, 1, plain);
    emphasis(_italicUnderscore, PreviewFlags.italic, 1, plain);
  }
}
