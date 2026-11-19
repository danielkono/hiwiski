import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/hiwiski_symbols.dart';
import '../ui/hiwiski_page.dart';
import '../ui/page_header.dart';
import '../ui/states.dart';
import 'routes.dart';

/// An address the app has no screen for — a typo, an old link (on the web the
/// address bar takes anything). It says so and leads to the start, instead of
/// Flutter's own error page.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return HiwiskiPage(
      header: PageHeader(title: l.notFoundTitle),
      body: EmptyState(
        icon: HiwiskiSymbols.searchOff,
        message: l.notFound,
        actionLabel: l.notFoundHome,
        onAction: () => const HomeRoute().go(context),
      ),
    );
  }
}
