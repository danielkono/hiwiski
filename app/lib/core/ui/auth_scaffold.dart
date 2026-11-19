import 'package:flutter/material.dart';

import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';
import '../theme/hiwiski_tokens.dart';
import 'loading_strip.dart';

/// The scaffold of the screens before sign-in.
///
/// A centered column with a max width of 400 — full width on a phone, the same
/// arrangement on desktop. Signing in is the same process however wide the screen is;
/// so it gets no second shape.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.children,
    this.loading = false,
    this.notice,
    this.onBack,
    this.title,
  });

  final List<Widget> children;
  final bool loading;

  /// A line **above** the content, not instead of the content.
  final Widget? notice;

  final VoidCallback? onBack;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            LoadingStrip(loading: loading),
            if (onBack != null || title != null)
              Padding(
                padding: const .only(
                  left: HiwiskiMetrics.space8,
                  top: HiwiskiMetrics.space4,
                  right: HiwiskiMetrics.space16,
                ),
                child: Row(
                  children: [
                    if (onBack != null)
                      IconButton(
                        icon: const Icon(HiwiskiSymbols.arrowBack),
                        onPressed: onBack,
                        tooltip: MaterialLocalizations.of(context)
                            .backButtonTooltip,
                      ),
                    if (title case final title?)
                      Expanded(
                        child: Text(title, style: context.texts.titleMedium),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const .fromLTRB(
                  HiwiskiMetrics.space24,
                  HiwiskiMetrics.space24,
                  HiwiskiMetrics.space24,
                  HiwiskiMetrics.space32,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: HiwiskiMetrics.authMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        if (notice case final notice?) ...[
                          notice,
                          const SizedBox(height: HiwiskiMetrics.space20),
                        ],
                        ...children,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
