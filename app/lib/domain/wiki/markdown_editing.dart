import '../common/match_groups.dart';

// Small edits on Markdown source — for the page editor and the rendered page.

/// A task-list line: `- [ ] …`, `* [x] …`, `1. [ ] …` — also inside a quote
/// (`> - [ ] …`).
///
/// By the renderer's rules (the `markdown` package's list syntax): a space or tab must
/// follow the `]`. Counted otherwise, a bare `- [ ]` at a line end was a box here but
/// not on screen, a quoted one the other way round, and a tap ticked the wrong line.
final _task = RegExp(
  r'^(\s*(?:>\s*)*(?:[-*+]|\d+[.)])\s+)\[( |x|X)\](?=[ \t])',
);
const _checked = 'x';
final _fence = RegExp(r'^\s*(```|~~~)');

/// The line indices of the task checkboxes, in document order — the same ones Markdown
/// renders as checkboxes. Lines inside fenced code blocks do not count.
List<int> _taskLines(List<String> lines) {
  final result = <int>[];
  bool inFence = false;
  for (int i = 0; i < lines.length; i++) {
    if (_fence.hasMatch(lines[i])) {
      inFence = !inFence;
      continue;
    }
    if (!inFence && _task.hasMatch(lines[i])) result.add(i);
  }
  return result;
}

/// Whether [line] opens or closes a fenced code block.
bool isFenceLine(String line) => _fence.hasMatch(line);

/// The box of a task line — where its `[` stands in [line] and whether it is ticked —
/// or `null` for a line that is not a task.
///
/// By the same rule the boxes are counted and ticked ([toggleTask]): the formatted
/// editor's box `n` is the text's box `n`.
({int at, bool checked})? taskBoxIn(String line) {
  final match = _task.firstMatch(line);
  if (match == null) return null;
  return (at: match.groupOf(1).length, checked: match.group(2) != ' ');
}

/// How many checkboxes the page shows.
int taskCount(String markdown) => _taskLines(markdown.split('\n')).length;

final _indent = RegExp(r'^\s*(?:>\s*)*');

/// For the n-th checkbox the renderer builds, which checkbox of the text it is — both
/// counted in document order, the answer is the document index.
///
/// **The renderer builds a list item after its children**, so with nested boxes it asks
/// for the inner ones first: of "a" with "b" below it, it builds "b" first and "a"
/// second. Counting the builds as document order made a tap on "b" tick "a" (and the
/// parent of a ticked child look ticked). Nesting is read from the indentation: a box is
/// the child of the nearest box above it that stands further left.
List<int> taskRenderOrder(String markdown) {
  final lines = markdown.split('\n');
  final order = <int>[];
  // (indent, document index) of the boxes whose children may still follow.
  final open = <(int, int)>[];
  for (final (index, line) in _taskLines(lines).indexed) {
    final indent = _indent.firstMatch(lines[line])?.end ?? 0;
    while (open.isNotEmpty && open.last.$1 >= indent) {
      order.add(open.removeLast().$2);
    }
    open.add((indent, index));
  }
  while (open.isNotEmpty) {
    order.add(open.removeLast().$2);
  }
  return order;
}

/// The text with the [index]-th checkbox ticked or unticked — so a packing list can be
/// worked through on the rendered page, without opening the source.
String toggleTask(String markdown, int index) {
  final lines = markdown.split('\n');
  final tasks = _taskLines(lines);
  if (index < 0 || index >= tasks.length) return markdown;
  final line = tasks[index];
  lines[line] = lines[line].replaceFirstMapped(
    _task,
    (match) => '${match.group(1)}[${match.group(2) == ' ' ? _checked : ' '}]',
  );
  return lines.join('\n');
}

/// List markers that Enter carries on to the next line.
final _listItem = RegExp(r'^(\s*)([-*+]|(\d+)([.)]))(\s+)(\[[ xX]\]\s+)?');

/// After Enter: the list continues — "- ", "- [ ] " (unticked), "2. " after "1. ".
///
/// Returns `null` when nothing is to be done: the new line did not follow a list item.
/// Enter on an **empty** item ends the list instead and removes the marker — the way
/// every editor does it.
({String text, int cursor})? continueList(String text, int cursor) {
  if (cursor <= 0 || cursor > text.length || text[cursor - 1] != '\n') {
    return null;
  }
  final lineStart = text.lastIndexOf('\n', cursor - 2) + 1;
  final previous = text.substring(lineStart, cursor - 1);
  final match = _listItem.firstMatch(previous);
  if (match == null) return null;

  final marker = match.groupOf(0);
  if (previous.trim() == marker.trim()) {
    // An empty item: the list ends here.
    final cleaned = text.replaceRange(lineStart, cursor, '');
    return (text: cleaned, cursor: lineStart);
  }

  final number = match.group(3);
  final bullet = number == null
      ? match.groupOf(2)
      : '${int.parse(number) + 1}${match.group(4)}';
  final task = match.group(6) == null ? '' : '[ ] ';
  final next = '${match.group(1)}$bullet${match.group(5)}$task';
  return (
    text: text.replaceRange(cursor, cursor, next),
    cursor: cursor + next.length,
  );
}

final _listLine = RegExp(r'^(\s*)(?:[-*+]|\d+[.)])(\s+)');

/// How far Tab pushes a line in, and how far Shift+Tab takes it back — as far as the
/// list above it needs to count it as nested.
///
/// **A nested item has to start under the text of its parent, not under its marker**:
/// two spaces under "- a", but three under "1. a" or under "-  a". A fixed two spaces
/// nested bullets and silently did not nest anything else — the item stayed on its
/// parent's level.
///
/// [before] are the lines above the one being moved, [line] that line. In: the
/// text of the nearest list item above that is not indented further than [line] (the
/// item it would sit under, or next to). Out: back to the level of the nearest one
/// above that is indented less. Without such an item, two spaces.
({int indent, int outdent}) listIndentSteps(List<String> before, String line) {
  const fallback = 2;
  final own =
      _listLine.firstMatch(line)?.group(1)?.length ??
      (line.length - line.trimLeft().length);
  int? indent;
  int? outdent;
  for (final above in before.reversed) {
    final match = _listLine.firstMatch(above);
    if (match == null) continue;
    final aboveIndent = match.group(1)?.length ?? 0;
    if (indent == null && aboveIndent <= own) {
      indent = match.end - aboveIndent;
    }
    if (outdent == null && aboveIndent < own) outdent = own - aboveIndent;
    if (indent != null && outdent != null) break;
  }
  return (indent: indent ?? fallback, outdent: outdent ?? fallback);
}

/// The block markers the toolbar sets — one replaces the other instead of stacking up.
const blockPrefixes = ['- [ ] ', '- ', '> ', '## '];

/// The toolbar's line prefix, **toggled**: when every selected line carries it already,
/// it comes off; otherwise it goes on, replacing a different block marker. Pressing
/// "list" twice used to give "- - ".
({String text, int start, int end}) togglePrefix(
  String text,
  int selectionStart,
  int selectionEnd,
  String prefix,
) {
  // At offset 0 the line starts at 0. Searching back from 0 found a newline right
  // there in "\nShopping" and put the start after the end — a RangeError.
  final start = selectionStart <= 0
      ? 0
      : text.lastIndexOf('\n', selectionStart - 1) + 1;
  final endOfLine = text.indexOf('\n', selectionEnd);
  final end = endOfLine == -1 ? text.length : endOfLine;
  final lines = text.substring(start, end).split('\n');

  // The marker a line carries — the longest first, so "- [ ] " is not taken for "- ".
  String? markerOf(String line) =>
      blockPrefixes.where(line.startsWith).firstOrNull;
  String strip(String line) => line.substring(markerOf(line)?.length ?? 0);

  final allHave = lines.every((line) => markerOf(line) == prefix);
  final changed = lines
      .map((line) => allHave ? strip(line) : '$prefix${strip(line)}')
      .join('\n');
  return (
    text: text.replaceRange(start, end, changed),
    start: start,
    end: start + changed.length,
  );
}

/// The toolbar's inline marker — `**`, `*`, `` ` `` — **toggled**: a selection that
/// stands between the markers already, or holds them at its edges, loses them; any
/// other gets them, and stays selected inside them. Without a selection the markers go
/// in with the cursor between them, and an empty pair around the cursor comes out.
///
/// In the formatted editor the markers are not seen, so pressing "bold" again on bold
/// text has to take it back — before, it only ever added another pair.
///
/// A run of the marker's character counts as the marker only when it is exactly as
/// long, or three long (bold and italic at once): italic on `**Soup**` adds a star
/// instead of eating into the bold.
({String text, int start, int end}) toggleWrap(
  String text,
  int start,
  int end,
  String marker,
) {
  final m = marker.length;
  final char = marker[0];
  bool fits(int run) => run == m || (run >= 3 && m < 3);

  int runBefore(int at) {
    int run = 0;
    while (at - run - 1 >= 0 && text[at - run - 1] == char) {
      run++;
    }
    return run;
  }

  int runAfter(int at) {
    int run = 0;
    while (at + run < text.length && text[at + run] == char) {
      run++;
    }
    return run;
  }

  // The markers inside the selection, at its edges.
  final selected = text.substring(start, end);
  if (selected.length >= 2 * m &&
      selected.startsWith(marker) &&
      selected.endsWith(marker) &&
      fits(runAfter(start)) &&
      fits(runBefore(end))) {
    final inner = selected.substring(m, selected.length - m);
    return (
      text: text.replaceRange(start, end, inner),
      start: start,
      end: start + inner.length,
    );
  }
  // The markers just outside it.
  final before = runBefore(start);
  final after = runAfter(end);
  if (before >= m && after >= m && fits(before) && fits(after)) {
    return (
      text: text
          .replaceRange(end, end + m, '')
          .replaceRange(start - m, start, ''),
      start: start - m,
      end: end - m,
    );
  }
  return (
    text: text.replaceRange(start, end, '$marker$selected$marker'),
    start: start + m,
    end: end + m,
  );
}

/// A line that continues the block above it.
final _leadingSpace = RegExp(r'\s');

/// About how much Markdown one rendered block holds. A page below it stays one block.
const markdownChunkSize = 3000;

/// The page in blocks of about [size] characters, cut only where Markdown itself ends a
/// block — so each can be rendered on its own, and a long page is built as it scrolls
/// into view instead of all at once. Rendered whole, a page of 32,000 characters took
/// over half a second in one frame on a Galaxy S9+.
///
/// A cut lies on a blank line, never inside a fenced code block, never between two
/// items of a list (a loose list stays one list, its numbering intact) and never before
/// an indented line (it continues the block above). The blocks joined with a line break
/// are the text again, and the checkboxes of all blocks are those of the page, in order.
List<String> markdownChunks(String markdown, {int size = markdownChunkSize}) {
  if (markdown.length <= size) return [markdown];
  final lines = markdown.split('\n');
  final chunks = <String>[];
  int start = 0;
  int length = 0;
  bool inFence = false;
  String? lastContent;
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    length += line.length + 1;
    if (_fence.hasMatch(line)) inFence = !inFence;
    if (line.trim().isNotEmpty) {
      lastContent = line;
      continue;
    }
    if (inFence || length < size) continue;
    final next = lines
        .skip(i + 1)
        .where((l) => l.trim().isNotEmpty)
        .firstOrNull;
    if (next == null) continue;
    final continues = next.startsWith(_leadingSpace);
    final listGoesOn =
        lastContent != null &&
        _listItem.hasMatch(lastContent) &&
        _listItem.hasMatch(next);
    if (continues || listGoesOn) continue;
    chunks.add(lines.sublist(start, i + 1).join('\n'));
    start = i + 1;
    length = 0;
  }
  chunks.add(lines.sublist(start).join('\n'));
  return chunks;
}
