import 'package:flutter/widgets.dart';

/// Where nothing beside the panel has a title — nothing chosen: [child] with the
/// button in its top left corner, at [inset] from the edge.
class PanelReopenCorner extends StatelessWidget {
  const PanelReopenCorner({
    super.key,
    required this.button,
    required this.inset,
    required this.child,
  });

  final Widget? button;
  final double inset;
  final Widget child;

  @override
  Widget build(BuildContext context) => switch (button) {
    null => child,
    final button => Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(top: 0, left: inset, child: button),
      ],
    ),
  };
}
