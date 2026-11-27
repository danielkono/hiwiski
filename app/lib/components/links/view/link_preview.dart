import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/hiwiski_sheet.dart';
import '../../../core/ui/ui_keys.dart';
import '../../../domain/links/link_index.dart';
import 'link_chip.dart';

/// **A link opens a preview, not the target**.
///
/// Jumping straight to the target lost the way back: "Back" on the target led to its
/// parent, not to where the link was. The preview — a sheet on the phone, a dialog on
/// a large screen — shows the target's title and number over the current page, and
/// below them its page as it is, without the info bar: [body], which the caller
/// builds, because `core/links` knows no features. "Open" goes to the full page,
/// "Close" stays where one was. A link inside the preview opens the next preview on
/// top.
Future<void> showLinkPreview(
  BuildContext context, {
  required LinkItem target,
  required Widget body,
  required VoidCallback onOpenFull,
}) => showHiwiskiSheet<void>(
  context: context,
  title: linkItemTypeLabel(L.of(context), target.itemType),
  // A page's content, not a form: as wide as the page shows it.
  maxWidth: HiwiskiMetrics.contentMaxWidth + 2 * HiwiskiMetrics.space20,
  builder: (context) =>
      LinkPreview(target: target, body: body, onOpenFull: onOpenFull),
);

class LinkPreview extends StatelessWidget {
  const LinkPreview({
    super.key,
    required this.target,
    required this.body,
    required this.onOpenFull,
    this.inline = false,
  });

  final LinkItem target;
  final Widget body;
  final VoidCallback onOpenFull;

  /// Shown within something else — a mind map's element — not in a sheet of its own:
  /// without the sheet's buttons — "Close" there closed what lay under the element —
  /// and a tap on the title does [onOpenFull].
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final heading = Row(
      crossAxisAlignment: .start,
      children: [
        Padding(
          padding: const .only(top: HiwiskiMetrics.space2),
          child: Icon(
            linkItemIcon(target.itemType),
            size: HiwiskiMetrics.icon22,
          ),
        ),
        const SizedBox(width: HiwiskiMetrics.space10),
        Expanded(child: Text(target.title, style: context.texts.titleLarge)),
        if (target.entityKey case final key?) ...[
          const SizedBox(width: HiwiskiMetrics.space8),
          Padding(
            padding: const .only(top: HiwiskiMetrics.space6),
            child: Text(key, style: context.tokens.text.entityKey),
          ),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        if (inline)
          Tooltip(
            message: l.linkPreviewOpen,
            child: InkWell(
              key: CoreKeys.linkPreviewOpen,
              onTap: onOpenFull,
              borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
              child: Semantics(
                button: true,
                hint: l.linkPreviewOpen,
                child: heading,
              ),
            ),
          )
        else
          heading,
        const SizedBox(height: HiwiskiMetrics.space16),
        body,
        if (!inline)
          SheetActions(
            children: [
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.actionClose),
              ),
              FilledButton(
                key: CoreKeys.linkPreviewOpen,
                onPressed: onOpenFull,
                child: Text(l.linkPreviewOpen),
              ),
            ],
          ),
      ],
    );
  }
}
