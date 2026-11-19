import 'package:flutter/material.dart';

import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_tokens.dart';

/// The label above a group of rows on the account's pages.
class AccountSectionLabel extends StatelessWidget {
  const AccountSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .only(
      left: HiwiskiMetrics.space4,
      right: HiwiskiMetrics.space4,
      bottom: HiwiskiMetrics.space8,
    ),
    child: Text(text, style: context.tokens.text.sectionLabel),
  );
}
