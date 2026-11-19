import 'package:flutter/material.dart';

import '../theme/hiwiski_metrics.dart';

/// A field that opens a picker — outlined like a text field, icon in front, label on the
/// border.
///
/// Built on `InputDecorator` so that border, label and spacing come from the same
/// `inputDecorationTheme` as the typed field next to it — two fields that should look
/// alike read from the same place.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.onOpen,
    this.value,
    this.child,
    this.errorText,
  }) : // The parameters, not constants: the rule misreads the initializer list.
       // ignore: many_lints/avoid_constant_conditions
       assert(value != null || child != null),
       // ignore: many_lints/avoid_constant_conditions
       assert(onTap != null || onOpen != null);

  final IconData icon;
  final String label;
  final String? value;

  /// Instead of a text — say, a calendar's dot and name.
  final Widget? child;
  final VoidCallback? onTap;

  /// Instead of [onTap], for a picker that anchors itself to the field: it gets the
  /// field's own context, whose box is where the picker belongs.
  final Future<void> Function(BuildContext field)? onOpen;

  /// Shown below in `error`, the field outlined red — like a text field that failed.
  final String? errorText;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () {
      final open = onOpen;
      if (open == null) {
        onTap?.call();
        return;
      }
      // The picker reports through its own setState; nothing here waits for it.
      open(context).ignore();
    },
    borderRadius: const .all(.circular(HiwiskiMetrics.radiusField)),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: .always,
        prefixIcon: Icon(icon, size: HiwiskiMetrics.icon20),
        errorText: errorText,
      ),
      child: child ?? Text(value ?? '', maxLines: 1, overflow: .ellipsis),
    ),
  );
}
