import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';

/// **"Edit"** in the header of every item — one button in the same place, instead of a
/// `more_vert` menu that was different on every screen.
class EditButton extends StatelessWidget {
  const EditButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
    onPressed: onPressed,
    icon: const Icon(HiwiskiSymbols.edit, size: HiwiskiMetrics.icon18),
    label: Text(L.of(context).actionEdit),
  );
}
