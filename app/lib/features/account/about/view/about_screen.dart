import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/common/app_names.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/shell/breakpoints.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../../../core/ui/page_header.dart';
import '../../../../domain/legal/legal_links.dart';
import '../../view/account_keys.dart';
import '../../view/account_row.dart';
import '../../view/account_section_label.dart';
import '../about_view_model.dart';

/// Account → About: the app's version and the server's,
/// its license, and the licenses of everything it is built from.
///
/// For every member, not only the administrator: whoever reports a problem needs the
/// version, and the licenses of the packages have to reach everyone who has the app.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = PageHeader(
      title: L.of(context).aboutTitle,
      onBack: () => const AccountRoute().go(context),
    );
    return ref
        .watch(aboutViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(header: header, error: error),
          data: (state) => _AboutPage(header: header, state: state),
        );
  }
}

class _AboutPage extends StatelessWidget {
  const _AboutPage({required this.header, required this.state});

  final PageHeader header;
  final AboutState state;

  static const _copyright = '© ${ProjectInfo.author}';

  /// "2026.1.1 (42)" — the build number tells two TestFlight builds of one version
  /// apart.
  String _appVersion(L l) => switch ((state.appVersion, state.appBuild)) {
    ('', _) => l.aboutDevelopmentBuild,
    (final version, '') => version,
    (final version, final build) => '$version ($build)',
  };

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final padding = Breakpoint.of(context).pagePadding;
    final appVersion = _appVersion(l);

    return HiwiskiPage(
      header: header,
      body: ListView(
        padding: padding,
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: HiwiskiMetrics.listMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: .stretch,
                children: [
                  AccountSectionLabel(l.aboutVersion),
                  AccountRow(
                    icon: HiwiskiSymbols.smartphone,
                    label: l.aboutApp,
                    value: appVersion,
                  ),
                  AccountRow(
                    icon: HiwiskiSymbols.dns,
                    label: l.serverLabel,
                    value: state.serverVersion ?? '—',
                  ),
                  const SizedBox(height: HiwiskiMetrics.space16),
                  AccountSectionLabel(l.aboutLicense),
                  AccountRow(
                    icon: HiwiskiSymbols.description,
                    label: ProjectInfo.license,
                    subtitle: '${l.aboutLicenseTerms}\n$_copyright',
                    leavesApp: true,
                    onTap: () => _open(ProjectInfo.licenseUrl),
                  ),
                  if (ProjectInfo.sourcePublic)
                    AccountRow(
                      icon: HiwiskiSymbols.code,
                      label: l.aboutSourceCode,
                      leavesApp: true,
                      onTap: () => _open(ProjectInfo.sourceUrl),
                    ),
                  AccountRow(
                    key: AccountKeys.appPrivacy,
                    icon: HiwiskiSymbols.policy,
                    label: l.aboutAppPrivacy,
                    subtitle: l.aboutAppPrivacyHint,
                    leavesApp: true,
                    onTap: () => _open(
                      LegalLinks.appPrivacy(
                        Localizations.localeOf(context).languageCode,
                      ),
                    ),
                  ),
                  // Flutter's own page: every package's license, collected at
                  // build time, plus the fonts and the native libraries
                  // (registered in main.dart).
                  AccountRow(
                    key: AccountKeys.packageLicenses,
                    icon: HiwiskiSymbols.menuBook,
                    label: l.aboutPackageLicenses,
                    subtitle: l.aboutPackageLicensesHint,
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: l.appName,
                      applicationVersion: appVersion,
                      applicationLegalese:
                          '$_copyright · ${ProjectInfo.license}',
                    ),
                  ),
                  const SizedBox(height: HiwiskiMetrics.space32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// In the browser, not in a view inside the app.
  static void _open(Uri url) {
    // A device without a browser has nothing to open it with, and the row has
    // nothing better to offer.
    launchUrl(url, mode: .externalApplication).ignore();
  }
}
