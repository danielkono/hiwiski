import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../legal_view_model.dart';

/// Legal notice and privacy policy, small and at the bottom of a screen seen before
/// signing in — whoever comes to a public instance without an account reaches them
/// there. Nothing when the instance names neither.
class LegalFooter extends ConsumerWidget {
  const LegalFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final links = ref.watch(legalViewModelProvider);
    if (links.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const .only(top: HiwiskiMetrics.space16),
      child: Wrap(
        alignment: .center,
        spacing: HiwiskiMetrics.space8,
        children: [
          if (links.notice case final notice?)
            TextButton(
              onPressed: () => openLegalPage(notice),
              child: Text(l.legalNotice),
            ),
          if (links.privacy case final privacy?)
            TextButton(
              onPressed: () => openLegalPage(privacy),
              child: Text(l.legalPrivacy),
            ),
        ],
      ),
    );
  }
}

/// In the browser, not in a view inside the app.
void openLegalPage(Uri url) {
  // A device without a browser has nothing to open it with, and the link has
  // nothing better to offer.
  launchUrl(url, mode: .externalApplication).ignore();
}
