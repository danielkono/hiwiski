import 'package:flutter/material.dart';

import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/theme/mindmap_colors.dart';
import '../../../../core/ui/color_tokens.dart';
import '../../../../core/ui/history_field_label.dart';
import '../../../../domain/sync/conflict_values.dart';
import '../../../../domain/sync/sync_items.dart';
import '../../../../domain/wiki/mindmap.dart';
import 'mindmap_keys.dart';

/// An element's or a connection's conflict, decided on the map — no sheet over it.
///
/// The map shows what the others wrote; an element's own version stands beside it,
/// dashed ([MindmapScene.mine]), so a position or a size is seen, not read as numbers.
/// What cannot be seen there — a text, a colour, a link's target — the bar names,
/// both versions. "Take mine" sends this device's version once more, "Keep theirs"
/// lets it go; the rest of the map is not touched.
class MindmapConflictBar extends StatelessWidget {
  const MindmapConflictBar({
    super.key,
    required this.conflicts,
    required this.onMap,
    required this.targetLabel,
    required this.onMine,
    required this.onTheirs,
    required this.onClose,
    this.bottom = false,
  });

  final List<SyncConflict> conflicts;

  /// Whether this device's version stands on the map: an element's does; a
  /// connection's is read here.
  final bool onMap;

  /// A link element's address by its target's title and number — `null` when the
  /// target is not on this device.
  final String? Function(String address) targetLabel;
  final VoidCallback onMine;
  final VoidCallback onTheirs;

  /// Closed undecided: the conflict stays, marked on the map.
  final VoidCallback onClose;

  /// At the screen's foot: it keeps clear of the home indicator.
  final bool bottom;

  /// The fields seen on the map rather than read.
  static const _seen = {
    WireFields.x,
    WireFields.width,
    WireFields.layer,
    WireFields.points,
    WireFields.strokeWidth,
    WireFields.rotation,
  };

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final firsts = [
      for (final group in groupConflicts(conflicts)) ?group.firstOrNull,
    ];
    bool isSeen(SyncConflict conflict) =>
        onMap && _seen.contains(mindmapConflictGroup(conflict.field));
    final seen = [
      for (final conflict in firsts)
        if (isSeen(conflict)) historyFieldLabel(l, conflict.field),
    ];
    final read = [
      for (final conflict in firsts)
        if (!isSeen(conflict)) conflict,
    ];
    return Material(
      color: context.scheme.surfaceContainerHigh,
      elevation: HiwiskiMetrics.elevationMenu,
      child: SafeArea(
        top: false,
        bottom: bottom,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * _maxShare,
          ),
          child: SingleChildScrollView(
            padding: const .fromLTRB(
              HiwiskiMetrics.space16,
              HiwiskiMetrics.space4,
              HiwiskiMetrics.space8,
              HiwiskiMetrics.space8,
            ),
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                Row(
                  children: [
                    Icon(HiwiskiSymbols.merge, color: context.scheme.tertiary),
                    const SizedBox(width: HiwiskiMetrics.space8),
                    Expanded(
                      child: Text(
                        l.mindmapConflictElement,
                        style: context.texts.titleSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: l.actionClose,
                      icon: const Icon(HiwiskiSymbols.close),
                      onPressed: onClose,
                    ),
                  ],
                ),
                Padding(
                  padding: const .only(right: HiwiskiMetrics.space8),
                  child: Text(
                    onMap ? l.mindmapConflictHintMap : l.mindmapConflictHint,
                    style: context.texts.bodySmall,
                  ),
                ),
                if (seen.isNotEmpty)
                  Padding(
                    padding: const .only(top: HiwiskiMetrics.space8),
                    child: Text(
                      l.mindmapConflictOnMap(seen.join(_list)),
                      style: context.texts.labelLarge,
                    ),
                  ),
                for (final conflict in read) ...[
                  const SizedBox(height: HiwiskiMetrics.space8),
                  Text(
                    historyFieldLabel(l, conflict.field),
                    style: context.texts.labelLarge,
                  ),
                  _Version(
                    label: l.conflictTheirs,
                    child: _Value(
                      field: conflict.field,
                      json: conflict.theirs,
                      targetLabel: targetLabel,
                    ),
                  ),
                  _Version(
                    label: l.conflictMine,
                    child: _Value(
                      field: conflict.field,
                      json: conflict.mine,
                      targetLabel: targetLabel,
                    ),
                  ),
                ],
                const SizedBox(height: HiwiskiMetrics.space8),
                Wrap(
                  alignment: .end,
                  spacing: HiwiskiMetrics.space8,
                  runSpacing: HiwiskiMetrics.space8,
                  children: [
                    TextButton(
                      key: MindmapKeys.keepTheirs,
                      onPressed: onTheirs,
                      child: Text(l.mindmapConflictKeepAll),
                    ),
                    FilledButton(
                      key: MindmapKeys.takeMine,
                      onPressed: onMine,
                      child: Text(l.mindmapConflictTakeAll),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Never more than this share of the screen: the two versions above stay in view.
  static const _maxShare = 0.45;
  static const _list = ', ';
}

class _Version extends StatelessWidget {
  const _Version({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .symmetric(vertical: HiwiskiMetrics.space2),
    child: Row(
      crossAxisAlignment: .start,
      children: [
        SizedBox(
          width: HiwiskiMetrics.labelColumnWidth * 2,
          child: Text(
            label,
            style: context.texts.bodySmall?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

/// A stored value as a person reads it: a colour as a swatch with its name, a shape
/// or a size by its name, a link by its target, a note without its Markdown.
class _Value extends StatelessWidget {
  const _Value({
    required this.field,
    required this.json,
    required this.targetLabel,
  });

  final String field;
  final String? json;
  final String? Function(String address) targetLabel;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final raw = switch (readConflictValue(field, json)) {
      TextValue(:final text) => text,
      _ => json ?? '',
    };
    final stored = raw.isEmpty ? null : raw;
    if (field == WireFields.color || field == WireFields.textColor) {
      final color = MindmapColor.parse(stored);
      return Row(
        children: [
          Container(
            width: HiwiskiMetrics.icon16,
            height: HiwiskiMetrics.icon16,
            decoration: ShapeDecoration(
              shape: CircleBorder(
                side: BorderSide(color: context.scheme.outlineVariant),
              ),
              color: color == null
                  ? context.scheme.surfaceContainerHigh
                  : MindmapPaint.swatchOf(context, color),
            ),
          ),
          const SizedBox(width: HiwiskiMetrics.space8),
          Expanded(
            child: Text(switch (color) {
              TokenColor(:final token) => colorLabel(l, token),
              OwnColor(:final stored) => stored,
              null => l.mindmapColorNone,
            }),
          ),
        ],
      );
    }
    final text = switch (field) {
      WireFields.target when stored != null =>
        targetLabel(stored) ?? l.mindmapLinkGone,
      WireFields.shape => switch (stored) {
        MindmapShapes.rectangle => l.mindmapShapeRectangle,
        MindmapShapes.pill => l.mindmapShapePill,
        MindmapShapes.ellipse => l.mindmapShapeEllipse,
        MindmapShapes.diamond => l.mindmapShapeDiamond,
        _ => l.mindmapShapeRounded,
      },
      WireFields.textSize => switch (stored) {
        MindmapTextSizes.small => l.mindmapTextSmall,
        MindmapTextSizes.large => l.mindmapTextLarge,
        MindmapTextSizes.xLarge => l.mindmapTextXLarge,
        _ => l.mindmapTextMedium,
      },
      WireFields.linkView => switch (stored) {
        MindmapLinkViews.content => l.mindmapLinkContent,
        _ => l.mindmapLinkTitle,
      },
      WireFields.text => plainOfMarkdown(raw),
      _ => raw,
    };
    return Text(
      text.isEmpty ? _nothing : text,
      maxLines: _lines,
      overflow: .ellipsis,
    );
  }

  static const _lines = 3;
  static const _nothing = '—';
}
