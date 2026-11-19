import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';
import '../theme/hiwiski_tokens.dart';
import 'removable_row.dart';

/// The delete symbol on a task, a card or a comment: **held, it deletes** — a tap
/// alone only says so, in a small hint at the symbol. A held press is quicker than the long press that picks a
/// shopping row or a card up, so holding the symbol never starts a drag instead. The
/// row around it has to be a [RemovableRow].
///
/// **A click says so too.** The hint answers a tap only by touch; a mouse click went
/// through to the row and opened the task.
class DeleteHoldButton extends StatelessWidget {
  const DeleteHoldButton({super.key, this.holdKey, this.size});

  /// The key of the part that is held — for the tests.
  final Key? holdKey;

  /// The symbol's size; a comment's is smaller than a row's.
  final double? size;

  /// Long enough to be meant, shorter than picking a row up.
  static const hold = Duration(milliseconds: 350);

  void _delete(BuildContext context) {
    // Feedback only — a device without it deletes all the same.
    HapticFeedback.mediumImpact().ignore();
    // The removal only animates; nothing in it fails.
    RemovableRow.maybeOf(context)?.remove().ignore();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Tooltip(
      message: l.todoDeleteHint,
      triggerMode: .tap,
      // Below the hint, to reach it.
      child: Builder(
        builder: (context) => Semantics(
          button: true,
          label: l.todoDeleteHold,
          hint: l.todoDeleteHint,
          onLongPress: () => _delete(context),
          child: RawGestureDetector(
            key: holdKey,
            behavior: .opaque,
            // The Semantics above carries label and action; a node of its own here
            // would be a second, unnamed one.
            excludeFromSemantics: true,
            gestures: {
              LongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    LongPressGestureRecognizer
                  >(
                    () => LongPressGestureRecognizer(
                      duration: DeleteHoldButton.hold,
                    ),
                    (press) => press.onLongPress = () => _delete(context),
                  ),
              // Touch has the hint's own tap; with it the click is the button's, not
              // the row's.
              TapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                    () =>
                        TapGestureRecognizer(supportedDevices: const {.mouse}),
                    (tap) => tap.onTap = () => context
                        .findAncestorStateOfType<TooltipState>()
                        ?.ensureTooltipVisible(),
                  ),
            },
            child: SizedBox.square(
              dimension: HiwiskiMetrics.minTapTarget,
              child: Icon(
                HiwiskiSymbols.deleteOutline,
                size: size ?? HiwiskiMetrics.icon20,
                color: context.scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
