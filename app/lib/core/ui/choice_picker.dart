import 'package:flutter/material.dart';

import '../shell/breakpoints.dart';
import '../theme/hiwiski_metrics.dart';

/// One entry of [pickChoice].
@immutable
class const Choice<T>({
  required final T value,
  required final String label,

  /// In front of the label — say, a calendar's colour dot.
  final Widget? leading,
});

/// Picks one of a few [choices] for a field.
///
/// **A phone gets a sheet from the bottom, a large screen a list right under the field**
/// — the way a suggestion list drops out of a text field. A sheet pulled up over a wide
/// window is not how a desktop or the web picks from a short list, and it throws the
/// eye from the field to the screen's far edge.
///
/// [context] has to be the field's own: the list is anchored to its box and as wide as
/// it. Back comes `null` when the picker was dismissed, otherwise the chosen value in a
/// record — a choice may itself be `null` (a reminder "as the calendar").
Future<({T value})?> pickChoice<T>(
  BuildContext context, {
  required List<Choice<T>> choices,
  T? current,
}) async {
  final compact = Breakpoint.of(context).isCompact;
  final index = compact
      ? await _pickInSheet(context, choices, current)
      : await _pickBelowField(context, choices, current);
  return index == null ? null : (value: choices[index].value);
}

Future<int?> _pickInSheet<T>(
  BuildContext context,
  List<Choice<T>> choices,
  T? current,
) => showModalBottomSheet<int>(
  context: context,
  // Over the whole screen, not in the areas' navigator inside the shell: there the
  // shade stopped short of the status bar and the tab bar, which stayed bright.
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: .min,
        children: [
          for (final (index, choice) in choices.indexed)
            ListTile(
              leading: choice.leading,
              title: Text(choice.label),
              selected: choice.value == current,
              onTap: () => Navigator.of(context).pop(index),
            ),
        ],
      ),
    ),
  ),
);

Future<int?> _pickBelowField<T>(
  BuildContext context,
  List<Choice<T>> choices,
  T? current,
) {
  final field = context.findRenderObject();
  final overlay = Navigator.of(
    context,
    rootNavigator: true,
  ).overlay?.context.findRenderObject();
  if (field is! RenderBox || overlay is! RenderBox) {
    return _pickInSheet(context, choices, current);
  }
  final origin = field.localToGlobal(Offset.zero, ancestor: overlay);
  final theme = Theme.of(context);
  return showMenu<int>(
    context: context,
    useRootNavigator: true,
    // A zero-height rectangle on the field's lower edge: the menu opens below it.
    position: RelativeRect.fromRect(
      Rect.fromLTWH(
        origin.dx,
        origin.dy + field.size.height,
        field.size.width,
        0,
      ),
      Offset.zero & overlay.size,
    ),
    constraints: BoxConstraints.tightFor(width: field.size.width),
    items: [
      for (final (index, choice) in choices.indexed)
        PopupMenuItem<int>(
          value: index,
          child: DefaultTextStyle.merge(
            style: choice.value == current
                ? TextStyle(color: theme.colorScheme.primary)
                : null,
            child: Row(
              children: [
                if (choice.leading case final leading?) ...[
                  leading,
                  const SizedBox(width: HiwiskiMetrics.space12),
                ],
                Expanded(child: Text(choice.label)),
              ],
            ),
          ),
        ),
    ],
  );
}
