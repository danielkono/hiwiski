import 'package:flutter/material.dart';

import '../theme/hiwiski_metrics.dart';

/// Gives a small control the tap area a finger reliably hits, the way Material's
/// `MaterialTapTargetSize.padded` does for its own: what is drawn keeps its size, the
/// room around it up to 48 × 48 takes the tap as well, and a screen reader finds one
/// element of that size with the control's label and action.
///
/// For the pills, chips and text actions built from an `InkWell` — Flutter pads only
/// its own controls. `test/a11y/` measures it on every screen.
class TapTarget extends StatelessWidget {
  const TapTarget({
    super.key,
    required this.onTap,
    required this.child,
    this.alignment = Alignment.center,
  });

  /// The same as the control's own: a tap next to it counts as a tap on it.
  final VoidCallback? onTap;
  final Widget child;

  /// Where in the target the control is drawn — at its lower edge where the room
  /// for the target is above the control (a link in a header's item line).
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: GestureDetector(
      behavior: .opaque,
      onTap: onTap,
      excludeFromSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: HiwiskiMetrics.minTapTarget,
          minHeight: HiwiskiMetrics.minTapTarget,
        ),
        child: Align(
          alignment: alignment,
          widthFactor: 1,
          heightFactor: 1,
          child: child,
        ),
      ),
    ),
  );
}
