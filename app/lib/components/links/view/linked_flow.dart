import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/ui/flowing_text.dart';
import '../../../domain/links/link_index.dart';
import '../../../domain/wiki/markdown_limits.dart';
import '../../../domain/wiki/page_images.dart';
import '../../rich_text/view/image_stack.dart';
import '../links_view_model.dart';
import 'linked_markdown.dart';

/// A text with link chips and pictures that fills an outline line by line — a box,
/// or a circle whose lines are short at its top and long in its middle
/// ([FlowingText]). Read-only, as a note on a mind map is.
///
/// Everything in it stands where [place] puts it, lists and pictures too: a list's
/// marker leads its line wherever the line stands. Markdown's blocks become lines of
/// their own — a list item, a table's row, a line of code —; what a box draws around
/// a block, a quote's bar or a code block's background, a line in an outline cannot.
class LinkedFlow extends ConsumerStatefulWidget {
  const LinkedFlow({
    super.key,
    required this.data,
    required this.styleSheet,
    this.outline = const FlowBox(),
    this.place = AlignmentDirectional.topStart,
    this.onOpen,
    this.onToggleTask,
  });

  final String data;
  final MarkdownStyleSheet styleSheet;
  final FlowOutline outline;
  final AlignmentGeometry place;
  final ValueChanged<LinkItem>? onOpen;

  /// Ticks or unticks the n-th checkbox of the text, counted in document order
  /// (`toggleTask`) — a packing list worked through where it is shown. `null`: the
  /// boxes are shown, not tappable.
  final ValueChanged<int>? onToggleTask;

  @override
  ConsumerState<LinkedFlow> createState() => _LinkedFlowState();
}

class _LinkedFlowState extends ConsumerState<LinkedFlow> {
  List<FlowParagraph> _paragraphs = const [];

  /// What [_paragraphs] were made from. Made again only when it changes: new spans
  /// lay the text out again, and a map rebuilds its elements at every step of a
  /// zoom.
  Object? _madeOf;

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(linksViewModelProvider);
    final base = DefaultTextStyle.of(context).style;
    final rule = Theme.of(context).colorScheme.outline;
    final madeOf = (
      widget.data,
      widget.styleSheet,
      base,
      rule,
      LinkedMarkdown.shownTargetsOf(index, widget.data),
      widget.onToggleTask != null,
    );
    if (madeOf != _madeOf) {
      _madeOf = madeOf;
      _paragraphs = _Paragraphs(
        sheet: widget.styleSheet,
        base: base,
        rule: rule,
        index: index,
        onOpen: _open,
        onToggleTask: widget.onToggleTask == null ? null : _toggle,
      ).of(widget.data);
    }
    return FlowingText(
      paragraphs: _paragraphs,
      outline: widget.outline,
      place: widget.place,
    );
  }

  /// Through the widget as it is now: the chips are made once and outlive a build.
  void _open(LinkItem target) => widget.onOpen?.call(target);

  void _toggle(int task) => widget.onToggleTask?.call(task);
}

/// A text's paragraphs as lines of spans.
class _Paragraphs {
  _Paragraphs({
    required this.sheet,
    required this.base,
    required this.rule,
    required this.index,
    required this.onOpen,
    this.onToggleTask,
  });

  final MarkdownStyleSheet sheet;
  final TextStyle base;
  final Color rule;
  final LinkIndex index;
  final ValueChanged<LinkItem> onOpen;
  final ValueChanged<int>? onToggleTask;

  final _made = <FlowParagraph>[];

  /// The checkboxes so far, in document order — the next one's number for
  /// `toggleTask`. List items are made in that order, a nested list after its item.
  int _tasks = 0;

  /// The room between two blocks, as a page leaves it.
  double get _gap => sheet.blockSpacing ?? HiwiskiMetrics.space8;

  /// Soft line breaks inside a paragraph join its lines, as in Markdown.
  static final _softBreak = RegExp(r' ?\n *');

  /// The line break a code block ends with: no empty line after it.
  static final _lastBreak = RegExp(r'\n$');

  /// An em space: a list inside a list stands one step further in.
  static const _indent = ' ';

  /// A space no line breaks at: a list's marker stays with its first word.
  static const _markerGap = ' ';

  static const _blockTags = {
    _Tags.p,
    _Tags.h1,
    _Tags.h2,
    _Tags.h3,
    _Tags.h4,
    _Tags.h5,
    _Tags.h6,
    _Tags.ul,
    _Tags.ol,
    _Tags.blockquote,
    _Tags.pre,
    _Tags.hr,
    _Tags.table,
    _Tags.section,
    _Tags.div,
  };

  List<FlowParagraph> of(String data) {
    for (final segment in pageSegments(data)) {
      switch (segment) {
        case ImageGroup(:final imageIds):
          _add(
            TextSpan(
              children: [
                WidgetSpan(
                  alignment: .top,
                  child: ImageStack(imageIds: imageIds),
                ),
              ],
            ),
          );
        case TextSegment(:final markdown):
          if (!renderableAsMarkdown(markdown)) {
            // A block the markdown package would take far too long to parse:
            // shown as it was written.
            _add(
              TextSpan(text: markdown, style: _style(sheet.p)),
              keepsSpaces: true,
            );
            continue;
          }
          _blocks(
            linkedMarkdownDocument().parseLines(
              const LineSplitter().convert(markdown),
            ),
            _style(sheet.p),
          );
      }
    }
    return _made;
  }

  TextStyle _style(TextStyle? style) => base.merge(style);

  void _add(InlineSpan span, {double? gap, bool keepsSpaces = false}) => _made
      .add(FlowParagraph(span, gap: gap ?? _gap, keepsSpaces: keepsSpaces));

  /// [nodes] as blocks: what is not one of its own — text between blocks — is a
  /// paragraph in [style].
  void _blocks(List<md.Node> nodes, TextStyle style) {
    final loose = <md.Node>[];
    void flush() {
      if (loose.isEmpty) return;
      _add(TextSpan(children: _inline(loose, style)));
      loose.clear();
    }

    for (final node in nodes) {
      if (node is md.Element && _blockTags.contains(node.tag)) {
        flush();
        _block(node, style);
      } else {
        loose.add(node);
      }
    }
    flush();
  }

  void _block(md.Element element, TextStyle style) {
    switch (element.tag) {
      case _Tags.p:
        _add(TextSpan(children: _inline(element.children, style)));
      case _Tags.h1 || _Tags.h2 || _Tags.h3 || _Tags.h4 || _Tags.h5 || _Tags.h6:
        _add(
          TextSpan(
            children: _inline(
              element.children,
              _style(sheet.styles[element.tag]),
            ),
          ),
        );
      case _Tags.ul || _Tags.ol:
        _list(element, style, depth: 0);
      case _Tags.blockquote:
        _blocks(element.children ?? const [], style.merge(sheet.blockquote));
      case _Tags.pre:
        _add(
          TextSpan(
            text: element.textContent.replaceAll(_lastBreak, ''),
            style: style.merge(sheet.code),
          ),
          keepsSpaces: true,
        );
      case _Tags.hr:
        _made.add(FlowParagraph.rule(rule, gap: _gap));
      case _Tags.table:
        _table(element, style);
      default:
        _blocks(element.children ?? const [], style);
    }
  }

  /// Each item a line of its own behind its marker; a list inside an item follows
  /// it, one step further in.
  void _list(md.Element list, TextStyle style, {required int depth}) {
    final ordered = list.tag == _Tags.ol;
    int number = int.tryParse(list.attributes[_Tags.start] ?? '') ?? 1;
    bool first = true;
    for (final item in list.children ?? const <md.Node>[]) {
      if (item is! md.Element || item.tag != _Tags.li) continue;
      final inline = <md.Node>[];
      final inner = <md.Element>[];
      bool? checked;
      for (final child in item.children ?? const <md.Node>[]) {
        switch (child) {
          case md.Element(tag: _Tags.ul || _Tags.ol):
            inner.add(child);
          case md.Element(tag: _Tags.input):
            checked = child.attributes.containsKey(_Tags.checked);
          case md.Element(tag: _Tags.p):
            // A loose list's item: its paragraphs on one line.
            if (inline.isNotEmpty) inline.add(md.Text(' '));
            inline.addAll(child.children ?? const []);
          default:
            inline.add(child);
        }
      }
      final bullet = style.merge(sheet.listBullet);
      final marker = switch (checked) {
        null => TextSpan(text: ordered ? '${number++}.' : '•', style: bullet),
        final ticked => WidgetSpan(
          alignment: .middle,
          child: _TaskBox(
            ticked: ticked,
            size: bullet.fontSize,
            color: bullet.color,
            onToggle: switch ((onToggleTask, _tasks++)) {
              (final toggle?, final task) => () => toggle(task),
              _ => null,
            },
          ),
        ),
      };
      _add(
        TextSpan(
          children: [
            if (depth > 0) TextSpan(text: _indent * depth, style: bullet),
            marker,
            TextSpan(text: _markerGap, style: bullet),
            ..._inline(inline, style),
          ],
        ),
        // The items of a list stand together.
        gap: first && depth == 0 ? null : 0,
      );
      first = false;
      for (final list in inner) {
        _list(list, style, depth: depth + 1);
      }
    }
  }

  /// Each row a line of its own, its cells side by side.
  void _table(md.Element table, TextStyle style) {
    final rows = <md.Element>[];
    void collect(md.Element element) {
      for (final child in element.children ?? const <md.Node>[]) {
        if (child is! md.Element) continue;
        if (child.tag == _Tags.tr) {
          rows.add(child);
        } else {
          collect(child);
        }
      }
    }

    collect(table);
    for (final (index, row) in rows.indexed) {
      final cells = [
        for (final cell in row.children ?? const <md.Node>[])
          if (cell is md.Element) cell,
      ];
      _add(
        TextSpan(
          children: [
            for (final (column, cell) in cells.indexed) ...[
              if (column > 0) TextSpan(text: ' · ', style: style),
              ..._inline(
                cell.children,
                cell.tag == _Tags.th ? style.merge(sheet.tableHead) : style,
              ),
            ],
          ],
        ),
        gap: index == 0 ? null : 0,
      );
    }
  }

  List<InlineSpan> _inline(List<md.Node>? nodes, TextStyle style) => [
    for (final node in nodes ?? const <md.Node>[]) ..._span(node, style),
  ];

  Iterable<InlineSpan> _span(md.Node node, TextStyle style) sync* {
    if (node is md.Text) {
      yield TextSpan(text: node.text.replaceAll(_softBreak, ' '), style: style);
      return;
    }
    if (node is! md.Element) return;
    if (linkSpanOf(node, index: index, style: style, onOpen: onOpen)
        case final span?) {
      yield span;
      return;
    }
    switch (node.tag) {
      case _Tags.strong:
        yield* _inline(node.children, style.merge(sheet.strong));
      case _Tags.em:
        yield* _inline(node.children, style.merge(sheet.em));
      case _Tags.del:
        yield* _inline(node.children, style.merge(sheet.del));
      case _Tags.code:
        yield TextSpan(text: node.textContent, style: style.merge(sheet.code));
      case _Tags.br:
        yield TextSpan(text: '\n', style: style);
      case _Tags.input:
        return;
      default:
        yield* _inline(node.children, style);
    }
  }
}

/// A list item's box, ticked or not — and ticked or unticked with a tap where the
/// text may be changed, as on a page. As large as the text it stands in: a box a
/// finger's width large would make its line that high.
class _TaskBox extends StatelessWidget {
  const _TaskBox({
    required this.ticked,
    required this.size,
    required this.color,
    this.onToggle,
  });

  final bool ticked;
  final double? size;
  final Color? color;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final box = Icon(
      ticked ? HiwiskiSymbols.checkBox : HiwiskiSymbols.checkBoxOutlineBlank,
      size: size,
      fill: ticked ? 1 : 0,
      color: color,
    );
    final toggle = onToggle;
    if (toggle == null) return box;
    return Semantics(
      checked: ticked,
      label: L.of(context).wikiTaskToggle,
      onTap: toggle,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: .opaque,
          excludeFromSemantics: true,
          onTap: toggle,
          child: box,
        ),
      ),
    );
  }
}

/// The elements and attributes the markdown package makes of a text.
abstract final class _Tags {
  static const p = 'p';
  static const h1 = 'h1';
  static const h2 = 'h2';
  static const h3 = 'h3';
  static const h4 = 'h4';
  static const h5 = 'h5';
  static const h6 = 'h6';
  static const ul = 'ul';
  static const ol = 'ol';
  static const li = 'li';
  static const blockquote = 'blockquote';
  static const pre = 'pre';
  static const hr = 'hr';
  static const table = 'table';
  static const section = 'section';
  static const div = 'div';
  static const tr = 'tr';
  static const th = 'th';
  static const strong = 'strong';
  static const em = 'em';
  static const del = 'del';
  static const code = 'code';
  static const br = 'br';
  static const input = 'input';
  static const start = 'start';
  static const checked = 'checked';
}
