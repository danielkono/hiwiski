import 'package:flutter/material.dart';

import '../../../../core/common/sync_limits.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../domain/common/text_length.dart';

/// Below the page's text while it is written: a warning as the text nears the
/// server's limit, and beyond it that the text is kept on this device but does not
/// sync until it is shorter.
class TextLengthNotice extends StatelessWidget {
  const TextLengthNotice({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller,
    builder: (context, value, _) {
      final l = L.of(context);
      final count = value.text.length;
      return switch (textLengthOf(value.text)) {
        .fits => const SizedBox.shrink(),
        .nearLimit => Padding(
          padding: const .only(top: HiwiskiMetrics.space8),
          child: NoticeBar(
            icon: HiwiskiSymbols.errorOutline,
            text: l.wikiTextNearLimit(count, SyncLimits.textChars),
          ),
        ),
        .overLimit => Padding(
          padding: const .only(top: HiwiskiMetrics.space8),
          child: NoticeBar.error(
            context,
            text: l.wikiTextOverLimit(count, SyncLimits.textChars),
          ),
        ),
      };
    },
  );
}
