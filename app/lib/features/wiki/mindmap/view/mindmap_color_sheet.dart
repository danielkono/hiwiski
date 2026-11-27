import 'package:flutter/material.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_theme.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/theme/mindmap_colors.dart';
import '../../../../core/ui/color_tokens.dart';
import '../../../../core/ui/hiwiski_sheet.dart';
import '../../../../core/ui/hsv_color_picker.dart';
import '../../../../domain/wiki/mindmap.dart';
import 'mindmap_keys.dart';

/// The colour an element or a connection takes: the design's colours, the own ones
/// already on this map, or a new one of the family's own — with how it reads in the
/// light and in the dark theme. `null` when cancelled; a record with `null` for the
/// theme's own colour.
///
/// With [text], the colour of an element's text: [text] says what it stands on — the
/// element's surface in its colour, or the canvas.
Future<({String? color})?> showMindmapColorSheet(
  BuildContext context, {
  required String? current,
  required List<String> recent,
  MindmapTextGround? text,
}) {
  final l = L.of(context);
  final picker = _Picker(MindmapColor.parse(current));
  return showHiwiskiSheet<({String? color})>(
    context: context,
    title: text == null ? l.mindmapColor : l.mindmapTextColor,
    owns: [picker],
    builder: (context) =>
        _ColorChoice(picker: picker, recent: recent, text: text),
    actions: (context) => [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l.actionCancel),
      ),
      FilledButton(
        key: MindmapKeys.save,
        onPressed: () =>
            Navigator.of(context).pop((color: picker.color?.stored)),
        child: Text(l.actionSave),
      ),
    ],
  );
}

/// What an element's text stands on: its surface, in the element's colour (as
/// stored), or — a snippet of plain text — the canvas.
typedef MindmapTextGround = ({bool surface, String? fill});

/// What is chosen in the sheet, while it is open.
class _Picker extends ChangeNotifier {
  _Picker(this._color);

  MindmapColor? _color;

  /// Where the own colour stands in the picker — kept as hue, saturation and
  /// brightness: a colour of no saturation keeps its hue while it is dragged back.
  HSVColor? _picked;

  MindmapColor? get color => _color;

  HSVColor? get picked => _picked;

  void choose(MindmapColor? color) {
    _color = color;
    _picked = null;
    notifyListeners();
  }

  void pick(HSVColor color) {
    _picked = color;
    _color = MindmapPaint.ownOf(color.toColor());
    notifyListeners();
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.picker,
    required this.recent,
    required this.text,
  });

  final _Picker picker;
  final List<String> recent;
  final MindmapTextGround? text;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return ListenableBuilder(
      listenable: picker,
      builder: (context, _) {
        final chosen = picker.color;
        return Column(
          crossAxisAlignment: .stretch,
          mainAxisSize: .min,
          children: [
            Wrap(
              spacing: HiwiskiMetrics.space4,
              runSpacing: HiwiskiMetrics.space4,
              children: [
                _Swatch(
                  color: null,
                  label: l.mindmapColorNone,
                  selected: chosen == null,
                  onTap: () => picker.choose(null),
                ),
                for (final token in calendarColorTokens)
                  _Swatch(
                    color: TokenColor(token),
                    label: colorLabel(l, token),
                    selected: chosen == TokenColor(token),
                    onTap: () => picker.choose(TokenColor(token)),
                  ),
              ],
            ),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: HiwiskiMetrics.space16),
              Text(l.mindmapColorRecent, style: context.texts.labelLarge),
              const SizedBox(height: HiwiskiMetrics.space4),
              Wrap(
                spacing: HiwiskiMetrics.space4,
                runSpacing: HiwiskiMetrics.space4,
                children: [
                  for (final stored in recent)
                    if (MindmapColor.parse(stored) case final OwnColor color)
                      _Swatch(
                        color: color,
                        label: stored,
                        selected: chosen == color,
                        onTap: () => picker.choose(color),
                      ),
                ],
              ),
            ],
            const SizedBox(height: HiwiskiMetrics.space16),
            Text(l.mindmapColorOwn, style: context.texts.labelLarge),
            const SizedBox(height: HiwiskiMetrics.space4),
            HsvColorPicker(
              // From the colour chosen, a token too: made see-through, it becomes
              // an own colour of the same hue.
              color:
                  picker.picked ??
                  HSVColor.fromColor(switch (chosen) {
                    final MindmapColor chosen => MindmapPaint.swatchOf(
                      context,
                      chosen,
                    ),
                    null => context.scheme.primary,
                  }),
              onChanged: picker.pick,
              opacity: true,
            ),
            if (chosen != null) ...[
              const SizedBox(height: HiwiskiMetrics.space12),
              _BothThemes(stored: chosen.stored, text: text),
            ],
          ],
        );
      },
    );
  }
}

/// One colour to tap; the theme's own shows as an outlined dot.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final MindmapColor? color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final shown = color;
    final fill = shown == null
        ? scheme.surfaceContainerHigh
        : MindmapPaint.swatchOf(context, shown);
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkResponse(
          key: MindmapKeys.swatch(shown?.stored ?? ''),
          onTap: onTap,
          radius: HiwiskiMetrics.minTapTarget / 2,
          child: SizedBox.square(
            dimension: HiwiskiMetrics.minTapTarget,
            child: Center(
              child: Container(
                width: HiwiskiMetrics.swatchSize,
                height: HiwiskiMetrics.swatchSize,
                decoration: ShapeDecoration(
                  shape: CircleBorder(
                    side: BorderSide(
                      color: selected ? scheme.primary : scheme.outlineVariant,
                      width: selected
                          ? HiwiskiMetrics.strokeBold
                          : HiwiskiMetrics.hairline,
                    ),
                  ),
                  color: fill,
                ),
                child: selected
                    ? Icon(
                        HiwiskiSymbols.check,
                        size: HiwiskiMetrics.icon18,
                        color: MindmapPaint.inkOn(fill, scheme),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How the colour reads on an element and as a line — or, as a text colour, as the
/// element's text — in the light and in the dark theme: the own colour keeps its hue
/// there, its tone is adapted.
class _BothThemes extends StatelessWidget {
  const _BothThemes({required this.stored, required this.text});

  final String stored;
  final MindmapTextGround? text;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Row(
      children: [
        for (final (theme, label) in [
          (HiwiskiTheme.light(), l.mindmapColorLight),
          (HiwiskiTheme.dark(), l.mindmapColorDark),
        ]) ...[
          Expanded(
            child: Theme(
              data: theme,
              child: Builder(
                builder: (context) {
                  final ground = text;
                  final paint = MindmapPaint.of(
                    context,
                    ground == null ? stored : ground.fill,
                  );
                  final background = ground == null || ground.surface
                      ? paint.fill
                      : context.scheme.surface;
                  final ink = ground == null
                      ? paint.onFill
                      : MindmapPaint.textOf(context, stored, background) ??
                            paint.onFill;
                  return Container(
                    padding: const .all(HiwiskiMetrics.space12),
                    decoration: BoxDecoration(
                      color: context.scheme.surface,
                      borderRadius: const .all(
                        .circular(HiwiskiMetrics.radiusChip),
                      ),
                      border: .fromBorderSide(
                        BorderSide(color: context.scheme.outlineVariant),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        Text(
                          label,
                          style: context.texts.labelSmall?.copyWith(
                            color: context.scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: HiwiskiMetrics.space8),
                        Container(
                          padding: const .all(HiwiskiMetrics.space8),
                          decoration: BoxDecoration(
                            color: background,
                            borderRadius: const .all(
                              .circular(HiwiskiMetrics.radiusChip),
                            ),
                          ),
                          child: Text(
                            ground == null || ground.surface
                                ? l.mindmapNote
                                : l.mindmapPlain,
                            style: context.texts.bodyMedium?.copyWith(
                              color: ink,
                            ),
                          ),
                        ),
                        // A line in the colour — not for a text colour.
                        if (ground == null) ...[
                          const SizedBox(height: HiwiskiMetrics.space8),
                          Container(
                            height: HiwiskiMetrics.strokeBold,
                            color: paint.line,
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          if (theme.brightness == .light)
            const SizedBox(width: HiwiskiMetrics.space8),
        ],
      ],
    );
  }
}
