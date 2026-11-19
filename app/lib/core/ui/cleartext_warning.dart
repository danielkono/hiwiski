import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';
import '../theme/hiwiski_tokens.dart';

/// The plain-language warning. It sits on the server screen, at sign-in **and** on
/// "Redeem invitation" — the app says plainly what currently applies instead of
/// showing a lock that is not one. On the redeem screen most of
/// all: the new password goes out there.
class CleartextWarning extends StatelessWidget {
  const CleartextWarning({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;
    return Container(
      padding: const .all(HiwiskiMetrics.space14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
      ),
      child: Row(
        crossAxisAlignment: .start,
        children: [
          Icon(
            HiwiskiSymbols.lockOpen,
            size: HiwiskiMetrics.icon20,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: HiwiskiMetrics.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: HiwiskiMetrics.space4,
              children: [
                Text(
                  l.serverCleartextTitle,
                  style: context.texts.titleSmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
                Text(
                  l.serverCleartextBody,
                  style: context.texts.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
