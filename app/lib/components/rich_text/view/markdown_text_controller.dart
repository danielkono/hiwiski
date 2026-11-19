import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_theme.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../domain/wiki/markdown_editing.dart';
import '../../../domain/wiki/markdown_preview.dart';
import '../../links/view/reference_chip.dart';
import 'rich_image.dart';

/// The controller of a text written in Markdown — a page, a description, a note —
/// that draws it **formatted or as its source**.
///
/// Formatted, the text is drawn as it will read ([MarkdownPreview]): the source stays
/// exactly what was typed, only its Markdown is hidden where the cursor is not. As
/// source, it is the plain text in mono. The mode can change at any time without the
/// text, the cursor or the undo history changing with it — it is the same field.
///
/// Until the member switches ([toggleFormatted]), the field follows their default
/// ([defaultFormatted], from Account → Customize).
class MarkdownTextController extends TextEditingController {
  MarkdownTextController({super.text});

  final _chosen = ValueNotifier<bool?>(null);

  /// The mode the member switched to in this field — `null` while it follows the
  /// default. Listened to by the field and the bar, which draw the mode.
  ValueListenable<bool?> get chosen => _chosen;

  /// The member's default, handed in by whoever shows the field. Set while building,
  /// and so without telling anyone: it only matters until the member switches.
  bool defaultFormatted = false;

  bool get formatted => _chosen.value ?? defaultFormatted;

  /// Formatted to source and back. The cursor stays where it is — out of a prefix
  /// that is drawn as one piece, once formatted.
  void toggleFormatted() {
    _chosen.value = !formatted;
    final selection = value.selection;
    if (formatted && selection.isValid && selection.isCollapsed) {
      final offset = _previewOf(text)
          .snap(selection.extentOffset, selection.extentOffset);
      if (offset != selection.extentOffset) {
        super.value = value.copyWith(selection: .collapsed(offset: offset));
      }
    }
    // The text is drawn anew; nothing about it changed.
    notifyListeners();
  }

  MarkdownPreview? _preview;

  /// The text read for drawing — once per text, not per cursor move.
  MarkdownPreview _previewOf(String text) {
    final cached = _preview;
    if (cached != null && cached.text == text) return cached;
    return _preview = MarkdownPreview.of(text);
  }

  /// Ticks or unticks the [index]-th box of the text — a tap on a box while writing.
  void toggleTaskAt(int index) {
    value = value.copyWith(text: toggleTask(text, index));
  }

  @override
  set value(TextEditingValue newValue) {
    final selection = newValue.selection;
    // Formatted, a line's prefix and a chip are one piece: the cursor goes around
    // them, never into them. Not while the keyboard still composes a word.
    if (formatted &&
        selection.isValid &&
        selection.isCollapsed &&
        !newValue.composing.isValid) {
      final old = value.selection;
      final from = old.isValid ? old.extentOffset : selection.extentOffset;
      final to = _previewOf(newValue.text).snap(from, selection.extentOffset);
      if (to != selection.extentOffset) {
        newValue = newValue.copyWith(selection: .collapsed(offset: to));
      }
    }
    super.value = newValue;
  }

  @override
  void dispose() {
    _chosen.dispose();
    super.dispose();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!formatted) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final looks = _Looks(context, style ?? const TextStyle());
    final selection = value.selection;
    final runs = _previewOf(text).runs(
      start: selection.isValid ? selection.start : -1,
      end: selection.isValid ? selection.end : -1,
    );
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;

    final children = <InlineSpan>[];
    for (final run in runs) {
      final look = looks.of(run.flags);
      final widget = run.widget;
      if (widget != null) {
        children.add(_widgetSpan(context, widget, look));
        continue;
      }
      // The word the keyboard is still composing is underlined, as in any field.
      final cuts = {
        run.start,
        if (composing.start > run.start && composing.start < run.end)
          composing.start,
        if (composing.end > run.start && composing.end < run.end) composing.end,
        run.end,
      }.toList()..sort();
      for (int i = 0; i + 1 < cuts.length; i++) {
        final a = cuts[i];
        final b = cuts[i + 1];
        final composed = a >= composing.start && b <= composing.end;
        children.add(
          TextSpan(
            text: text.substring(a, b),
            style: composed ? looks.composed(look) : look,
          ),
        );
      }
    }
    return TextSpan(style: style, children: children);
  }

  InlineSpan _widgetSpan(
    BuildContext context,
    PreviewWidget widget,
    TextStyle look,
  ) => switch (widget) {
    PreviewBullet(:final depth) => WidgetSpan(
      alignment: .middle,
      child: SizedBox(
        width: HiwiskiMetrics.editorBulletWidth,
        child: Center(
          child: _Bullet(depth: depth, color: look.color),
        ),
      ),
    ),
    PreviewTaskBox(:final index, :final checked) => WidgetSpan(
      alignment: .middle,
      child: _TaskBox(checked: checked, onTap: () => toggleTaskAt(index)),
    ),
    PreviewQuoteBar() => WidgetSpan(
      alignment: .middle,
      child: Container(
        width: HiwiskiMetrics.barHeight,
        height: (look.fontSize ?? HiwiskiMetrics.icon16) * (look.height ?? 1),
        margin: const .only(right: HiwiskiMetrics.space4),
        decoration: BoxDecoration(
          color: context.scheme.outlineVariant,
          borderRadius: const .all(.circular(HiwiskiMetrics.radiusBar)),
        ),
      ),
    ),
    PreviewImage(:final imageId) => WidgetSpan(
      alignment: .bottom,
      child: ClipRRect(
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
        child: SizedBox(
          width: HiwiskiMetrics.editorImageWidth,
          height: HiwiskiMetrics.editorImageHeight,
          child: RichImage(imageId: imageId, fit: .cover, preview: true),
        ),
      ),
    ),
    PreviewReference(:final part) => WidgetSpan(
      alignment: .middle,
      child: ReferenceChip(part: part, style: look),
    ),
  };
}

/// Backspace in a formatted text, where the character before the cursor is part of
/// something drawn as one piece: a line's prefix goes as the prefix
/// ([MarkdownPreview.backspace]) — a list item becomes text, a nested one moves out —
/// and a chip or an image as a whole.
///
/// A formatter and not a key handler: a phone's keyboard sends no key for Backspace,
/// only the text without the character.
class FormattedBackspace extends TextInputFormatter {
  FormattedBackspace(this.controller);

  final MarkdownTextController controller;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!controller.formatted) return newValue;
    final selection = oldValue.selection;
    if (!selection.isValid || !selection.isCollapsed) return newValue;
    final cursor = selection.baseOffset;
    final deletedOne =
        cursor > 0 &&
        newValue.text.length == oldValue.text.length - 1 &&
        newValue.selection.isCollapsed &&
        newValue.selection.baseOffset == cursor - 1 &&
        newValue.text == oldValue.text.replaceRange(cursor - 1, cursor, '');
    if (!deletedOne) return newValue;
    final edit = controller._previewOf(oldValue.text).backspace(cursor);
    if (edit == null) return newValue;
    return TextEditingValue(
      text: edit.text,
      selection: .collapsed(offset: edit.cursor),
    );
  }
}

/// The bullet of a list level, as the read page draws them: a dot, a ring, a square
/// — drawn, since the text's font has the characters for only the first.
class _Bullet extends StatelessWidget {
  const _Bullet({required this.depth, required this.color});

  final int depth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? context.scheme.onSurface;
    return SizedBox.square(
      dimension: HiwiskiMetrics.dotTiny,
      child: DecoratedBox(
        decoration: switch (depth % 3) {
          0 => BoxDecoration(color: ink, shape: .circle),
          1 => BoxDecoration(
            shape: .circle,
            border: .all(color: ink, width: HiwiskiMetrics.hairline),
          ),
          _ => BoxDecoration(color: ink),
        },
      ),
    );
  }
}

/// The styles of the flags, made once per build.
class _Looks {
  _Looks(BuildContext context, this.base)
    : _theme = Theme.of(context),
      _tokens = context.tokens;

  final TextStyle base;
  final ThemeData _theme;
  final HiwiskiTokens _tokens;
  final _made = <int, TextStyle>{};

  /// Hidden Markdown: there, but taking no room and showing nothing.
  static const _hidden = TextStyle(
    fontSize: HiwiskiMetrics.editorHiddenGlyph,
    color: Colors.transparent,
    letterSpacing: 0,
  );

  TextStyle of(int flags) => _made[flags] ??= _make(flags);

  TextStyle composed(TextStyle look) => look.copyWith(
    decoration: TextDecoration.combine([
      ?look.decoration,
      TextDecoration.underline,
    ]),
  );

  TextStyle _make(int flags) {
    if (flags & PreviewFlags.hidden != 0) return _hidden;
    final scheme = _theme.colorScheme;
    final texts = _theme.textTheme;
    TextStyle look = base;
    // The heading sizes of the read page (`MarkdownStyleSheet.fromTheme`).
    final heading = switch (PreviewFlags.headingOf(flags)) {
      1 => texts.headlineSmall,
      2 => texts.titleLarge,
      3 => texts.titleMedium,
      4 || 5 || 6 => texts.bodyLarge?.withWeight(.w600),
      _ => null,
    };
    if (heading != null) {
      look = look.merge(heading).copyWith(color: base.color);
    }
    if (flags & (PreviewFlags.codeBlock | PreviewFlags.table) != 0) {
      look = look
          .merge(_tokens.text.monoSmall)
          .copyWith(
            color: scheme.onSurface,
            backgroundColor: flags & PreviewFlags.codeBlock != 0
                ? scheme.surfaceContainerHigh
                : null,
          );
    }
    if (flags & PreviewFlags.code != 0) {
      look = look
          .merge(_tokens.text.monoSmall)
          .copyWith(
            color: scheme.onSurface,
            backgroundColor: scheme.surfaceContainerHigh,
          );
    }
    if (flags & PreviewFlags.bold != 0) look = look.withWeight(.w700);
    if (flags & PreviewFlags.italic != 0) {
      look = look.copyWith(fontStyle: .italic);
    }
    final decorations = <TextDecoration>[
      if (flags & PreviewFlags.strike != 0) TextDecoration.lineThrough,
      if (flags & PreviewFlags.link != 0) TextDecoration.underline,
    ];
    if (decorations.isNotEmpty) {
      look = look.copyWith(decoration: TextDecoration.combine(decorations));
    }
    if (flags & PreviewFlags.link != 0) {
      look = look.copyWith(color: scheme.primary);
    }
    if (flags & PreviewFlags.quote != 0) {
      look = look.copyWith(color: scheme.onSurfaceVariant);
    }
    if (flags & (PreviewFlags.marker | PreviewFlags.rule) != 0) {
      look = look.copyWith(color: scheme.outline);
    }
    if (flags & PreviewFlags.indent != 0) {
      look = look.copyWith(letterSpacing: HiwiskiMetrics.editorIndentSpacing);
    }
    return look;
  }
}

/// A task's box in the text being written: a tap ticks it, as on the read page.
///
/// Left out for screen readers: there the field reads its text, and "[x]" says the
/// same — a box of its own would be a second, separate control for one line.
class _TaskBox extends StatelessWidget {
  const _TaskBox({required this.checked, required this.onTap});

  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: .opaque,
        onTap: onTap,
        child: Padding(
          padding: const .only(right: HiwiskiMetrics.space2),
          child: Icon(
            checked
                ? HiwiskiSymbols.checkBox
                : HiwiskiSymbols.checkBoxOutlineBlank,
            size: HiwiskiMetrics.icon20,
            fill: checked ? 1 : 0,
            color: context.scheme.primary,
          ),
        ),
      ),
    ),
  );
}
