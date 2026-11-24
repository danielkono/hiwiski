import 'package:flutter/material.dart';

import '../../../../components/member_avatar/view/member_avatar.dart';
import '../../../../components/rich_text/view/markdown_text_controller.dart';
import '../../../../components/rich_text/view/rich_text_editor.dart';
import '../../../../core/api/generated/export.dart';
import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/ui/hiwiski_sheet.dart';
import '../../../../domain/common/item_ref.dart';
import '../../../../domain/wiki/mindmap.dart';
import '../../view/mindmap/mindmap_scene.dart';
import 'mindmap_keys.dart';

/// A plain text — an element's, a connection's label: written in a sheet and saved
/// with "Save". `null` when it was cancelled.
Future<String?> showMindmapTextSheet(
  BuildContext context, {
  required String title,
  required String text,
}) {
  final l = L.of(context);
  final controller = TextEditingController(text: text);
  return showHiwiskiSheet<String>(
    context: context,
    title: title,
    owns: [controller],
    builder: (context) => TextField(
      key: MindmapKeys.textField,
      controller: controller,
      autofocus: true,
      minLines: 2,
      maxLines: 8,
      textCapitalization: .sentences,
    ),
    actions: (context) => [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l.actionCancel),
      ),
      FilledButton(
        key: MindmapKeys.save,
        onPressed: () => Navigator.of(context).pop(controller.text),
        child: Text(l.actionSave),
      ),
    ],
  );
}

/// A note, written as a page is written: the bar with headings, lists, links and
/// pictures, formatted or as Markdown. Pictures go onto the page and up with the sync.
/// `null` when it was cancelled.
Future<String?> showMindmapNoteSheet(
  BuildContext context, {
  required String pageId,
  required String text,
}) {
  final l = L.of(context);
  final controller = MarkdownTextController(text: text);
  return showHiwiskiSheet<String>(
    context: context,
    title: l.mindmapNote,
    owns: [controller],
    // The bar stays in view: the field scrolls under it, not the sheet.
    scrolls: false,
    builder: (context) => RichTextEditor(
      controller: controller,
      carrier: ItemRef.wikiPage(pageId),
      fieldKey: MindmapKeys.textField,
      autofocus: true,
      scrollsField: true,
    ),
    actions: (context) => [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l.actionCancel),
      ),
      // Greyed out while pictures are still being read in: saved before, the text
      // would lack them.
      ValueListenableBuilder<bool>(
        valueListenable: MarkdownTextController.addingImagesAnywhere,
        builder: (context, adding, _) => FilledButton(
          key: MindmapKeys.save,
          onPressed: adding
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  await controller.imagesAdded;
                  navigator.pop(controller.text);
                },
          child: Text(l.actionSave),
        ),
      ),
    ],
  );
}

/// The element to connect [from] with — the way to connect without drawing a line,
/// for a screen reader and a keyboard. `null` when none was chosen.
///
/// Only elements a name tells apart are offered: a list of dashes for the strokes
/// and of "Picture" for every picture let no one pick the one they meant.
Future<MindmapNode?> showMindmapConnectSheet(
  BuildContext context, {
  required Mindmap map,
  required MindmapNode from,
  required MindmapLinkTarget linkTarget,
  required String? Function(String? target) memberName,
}) {
  final l = L.of(context);
  final others = [
    for (final node in map.nodes.reversed)
      if (node.id != from.id)
        if (MindmapSheetText.labelOf(
              l,
              node,
              linkTarget: linkTarget,
              memberName: memberName,
            )
            case final label?)
          (node: node, label: label),
  ];
  return showHiwiskiSheet<MindmapNode>(
    context: context,
    title: l.mindmapConnect,
    builder: (context) => others.isEmpty
        ? Padding(
            padding: const .all(HiwiskiMetrics.space16),
            child: Text(l.mindmapConnectNone),
          )
        : Column(
            mainAxisSize: .min,
            children: [
              for (final (:node, :label) in others)
                ListTile(
                  key: MindmapKeys.connectTo(node.id),
                  leading: Icon(MindmapSheetText.iconOf(node.kind)),
                  title: Text(label, maxLines: 2, overflow: .ellipsis),
                  onTap: () => Navigator.of(context).pop(node),
                ),
            ],
          ),
  );
}

/// Where a note's text is to stand — one of [MindmapTextAligns.all], picked from a
/// square of nine as they lie. `null` when it was closed without a choice.
Future<String?> showMindmapAlignSheet(
  BuildContext context, {
  required String current,
}) {
  final l = L.of(context);
  return showHiwiskiSheet<String>(
    context: context,
    title: l.mindmapTextAlign,
    builder: (context) => Center(
      child: Column(
        mainAxisSize: .min,
        children: [
          for (int row = 0; row < _alignRows; row++)
            Row(
              mainAxisSize: .min,
              children: [
                for (final align in MindmapTextAligns.all.sublist(
                  row * _alignRows,
                  row * _alignRows + _alignRows,
                ))
                  _AlignChoice(align: align, on: align == current),
              ],
            ),
        ],
      ),
    ),
  );
}

const _alignRows = 3;

/// One place in the square of nine.
class _AlignChoice extends StatelessWidget {
  const _AlignChoice({required this.align, required this.on});

  final String align;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = MindmapSheetText.alignNameOf(L.of(context), align);
    return Padding(
      padding: const .all(HiwiskiMetrics.space4),
      child: Tooltip(
        message: label,
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          excludeSemantics: true,
          child: Material(
            color: on ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
              side: BorderSide(
                color: on ? scheme.primary : scheme.outlineVariant,
              ),
            ),
            child: InkWell(
              key: MindmapKeys.textAlignOf(align),
              customBorder: const RoundedRectangleBorder(
                borderRadius: .all(.circular(HiwiskiMetrics.radiusChip)),
              ),
              onTap: () => Navigator.of(context).pop(align),
              child: SizedBox.square(
                dimension: HiwiskiMetrics.minTapTarget * 1.5,
                child: Padding(
                  padding: const .all(HiwiskiMetrics.space12),
                  child: CustomPaint(
                    painter: _AlignGlyph(
                      align,
                      on ? scheme.onSecondaryContainer : scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlignGlyph extends CustomPainter {
  const _AlignGlyph(this.align, this.color);

  final String align;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      paintTextAlignGlyph(canvas, size, color, align);

  @override
  bool shouldRepaint(_AlignGlyph oldDelegate) =>
      oldDelegate.align != align || oldDelegate.color != color;
}

/// How an element is named in a list: its text, or what it shows.
abstract final class MindmapSheetText {
  /// The name of [node] — `null` for one nothing tells apart from another: a stroke,
  /// a picture without a name, an empty text, a link whose target is not here.
  static String? labelOf(
    L l,
    MindmapNode node, {
    required MindmapLinkTarget linkTarget,
    required String? Function(String? target) memberName,
  }) {
    final text = switch (node.kind) {
      MindmapKinds.note => plainOfMarkdown(node.text),
      MindmapKinds.link => switch (node.target) {
        final target? => linkTarget(target)?.title,
        null => null,
      },
      MindmapKinds.member => memberName(node.target),
      MindmapKinds.image => pictureNameOf(node.text),
      MindmapKinds.drawing => null,
      _ => node.text,
    };
    final named = text?.trim();
    return named == null || named.isEmpty ? null : named;
  }

  static IconData iconOf(String kind) => MindmapElementView.iconOfKind(kind);

  /// Where a note's text stands, in words; an unknown place, or none, is the top
  /// left.
  static String alignNameOf(L l, String? align) => switch (align) {
    MindmapTextAligns.topCenter => l.mindmapAlignTopCenter,
    MindmapTextAligns.topRight => l.mindmapAlignTopRight,
    MindmapTextAligns.middleLeft => l.mindmapAlignMiddleLeft,
    MindmapTextAligns.center => l.mindmapAlignCenter,
    MindmapTextAligns.middleRight => l.mindmapAlignMiddleRight,
    MindmapTextAligns.bottomLeft => l.mindmapAlignBottomLeft,
    MindmapTextAligns.bottomCenter => l.mindmapAlignBottomCenter,
    MindmapTextAligns.bottomRight => l.mindmapAlignBottomRight,
    _ => l.mindmapAlignTopLeft,
  };
}

/// The member a member element shows: the family, each with their picture. `null`
/// when it was closed without a choice.
Future<Member?> showMindmapMemberSheet(
  BuildContext context, {
  required List<Member> members,
  String? current,
}) => showHiwiskiSheet<Member>(
  context: context,
  title: L.of(context).mindmapMemberPick,
  builder: (context) => Column(
    mainAxisSize: .min,
    crossAxisAlignment: .stretch,
    children: [
      for (final member in members)
        ListTile(
          key: MindmapKeys.member(member.id),
          contentPadding: .zero,
          leading: MemberAvatar.of(member),
          title: Text(member.displayName),
          trailing: member.id == current
              ? const Icon(HiwiskiSymbols.check)
              : null,
          onTap: () => Navigator.of(context).pop(member),
        ),
    ],
  ),
);

/// One of [choices] — or, where [own] is given, a number of one's own from
/// [own].min to [own].max, made into a value by [own].toValue. `null` when it was
/// closed without a choice.
Future<T?> showMindmapChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T value, String label)> choices,
  required T? current,
  ({int min, int max, int? value, T Function(int number) toValue})? own,
}) => showHiwiskiSheet<T>(
  context: context,
  title: title,
  builder: (context) =>
      _Choices<T>(choices: choices, current: current, own: own),
);

class _Choices<T> extends StatefulWidget {
  const _Choices({
    required this.choices,
    required this.current,
    required this.own,
  });

  final List<(T value, String label)> choices;
  final T? current;
  final ({int min, int max, int? value, T Function(int number) toValue})? own;

  @override
  State<_Choices<T>> createState() => _ChoicesState<T>();
}

class _ChoicesState<T> extends State<_Choices<T>> {
  late final _number = TextEditingController(
    text: widget.own?.value?.toString() ?? '',
  );

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  /// The number typed, if it is one the value may be.
  int? get _typed => switch ((widget.own, int.tryParse(_number.text.trim()))) {
    (final own?, final int number)
        when number >= own.min && number <= own.max =>
      number,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final own = widget.own;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        for (final (value, label) in widget.choices)
          ListTile(
            key: MindmapKeys.choice('$value'),
            contentPadding: .zero,
            title: Text(label),
            trailing: value == widget.current
                ? const Icon(HiwiskiSymbols.check)
                : null,
            onTap: () => Navigator.of(context).pop(value),
          ),
        if (own != null) ...[
          const SizedBox(height: HiwiskiMetrics.space8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: MindmapKeys.ownNumber,
                  controller: _number,
                  keyboardType: .number,
                  decoration: InputDecoration(
                    labelText: l.mindmapOwnValue,
                    helperText: l.mindmapOwnRange(own.min, own.max),
                  ),
                  onSubmitted: (_) {
                    if (_typed case final number?) {
                      Navigator.of(context).pop(own.toValue(number));
                    }
                  },
                ),
              ),
              const SizedBox(width: HiwiskiMetrics.space8),
              // Ready once what is typed is a number the value may be.
              ListenableBuilder(
                listenable: _number,
                builder: (context, _) => FilledButton(
                  key: MindmapKeys.ownApply,
                  onPressed: switch (_typed) {
                    final number? => () => Navigator.of(
                      context,
                    ).pop(own.toValue(number)),
                    null => null,
                  },
                  child: Text(l.mindmapApply),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
