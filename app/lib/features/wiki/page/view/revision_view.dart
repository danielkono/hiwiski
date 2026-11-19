import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/hiwiski_failure.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/failure_text.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../domain/wiki/wiki_page.dart';
import '../page_view_model.dart';

/// One version of a page, opened from its history: for reading, and "Restore this
/// version" for whoever may. **Conflict versions are marked.**
///
/// A conflict version preserves the version that lost in an editing conflict. Without
/// it the losing side's work would be gone — and that is the case where
/// someone has been writing for half an hour.
///
/// Without [canRestore] — read access only, or an archived page — the version can be
/// read but not restored: the server would refuse it anyway.
///
/// Shown on the second page of the history sheet (`HistorySection.versionView`),
/// which brings its own way back to the list.
class RevisionView extends ConsumerWidget {
  const RevisionView({
    super.key,
    required this.page,
    required this.revisionId,
    required this.canRestore,
  });

  final WikiPage page;
  final String revisionId;
  final bool canRestore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    return ref
        .watch(pageRevisionViewModelProvider(page.id, revisionId))
        .when(
          skipLoadingOnReload: true,
          // A failed load used to end in an unhandled error, and the tap did
          // nothing.
          error: (error, _) => NoticeBar.error(
            context,
            text: error is HiwiskiFailure
                ? failureText(context, error)
                : l.historyOffline,
            onRetry: () => ref
                .read(
                  pageRevisionViewModelProvider(page.id, revisionId).notifier,
                )
                .retry(),
          ),
          loading: () => const Padding(
            padding: .all(HiwiskiMetrics.space20),
            child: LinearProgressIndicator(),
          ),
          data: (revision) => Column(
            crossAxisAlignment: .stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      revision.title,
                      style: context.texts.titleMedium,
                    ),
                  ),
                  if (revision.kind == .conflict)
                    Chip(
                      label: Text(l.wikiRevisionConflict),
                      backgroundColor: context.scheme.errorContainer,
                      labelStyle: TextStyle(
                        color: context.scheme.onErrorContainer,
                      ),
                    ),
                ],
              ),
              Text(
                [
                  ref
                      .watch(pageViewModelProvider(page.id))
                      .value
                      ?.members[revision.authorId]
                      ?.displayName,
                  DateFormat.yMMMd(Localizations.localeOf(context).toString())
                      .add_Hm()
                      .format(revision.createdAt.toLocal()),
                ].whereType<String>().join(' · '),
                style: context.texts.bodySmall?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
              // Here and not in the sheet's footer: the footer came and went with
              // the version, and the sheet moved with it at every turn of the page.
              if (canRestore) ...[
                const SizedBox(height: HiwiskiMetrics.space12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton(
                    onPressed: () async {
                      await ref
                          .read(pageViewModelProvider(page.id).notifier)
                          .edit(
                            page,
                            title: revision.title,
                            content: revision.content ?? '',
                          );
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: Text(l.wikiRestoreRevision),
                  ),
                ),
              ],
              const SizedBox(height: HiwiskiMetrics.space12),
              SelectableText(
                revision.content ?? '',
                style: context.tokens.text.monoSmall,
              ),
            ],
          ),
        );
  }
}
