import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/history_field_label.dart';
import '../../../core/ui/hiwiski_sheet.dart';
import '../../../domain/common/word_diff.dart';
import '../../../domain/sync/conflict_values.dart';
import '../../../domain/sync/sync_items.dart';
import '../sync_banner_view_model.dart';

/// **A conflict, resolved by looking at it** — what it was, what the server has now,
/// and one's own version, each change against the starting point highlighted.
///
/// The banner used to show "old → new" in half a line, and for a page's text only a
/// link into the version history. Whoever has to choose needs to see what each side
/// changed.
Future<void> showConflictSheet(BuildContext context, SyncConflict conflict) {
  final l = L.of(context);
  return showHiwiskiSheet<void>(
    context: context,
    title: l.conflictTitle(historyFieldLabel(l, conflict.field)),
    builder: (context) => _ConflictBody(conflict: conflict),
  );
}

class _ConflictBody extends ConsumerWidget {
  const _ConflictBody({required this.conflict});

  final SyncConflict conflict;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    // The columns a card's column id is looked up in: the board's now, and those any
    // side of a board's own conflict carries.
    final board = [
      ...?ref.watch(syncBannerViewModelProvider).value?.boards[conflict.id],
    ];

    /// The stored value as a person reads it: names, not ids.
    String text(String? json) => switch (readConflictValue(
      conflict.field,
      json,
      board: board,
    )) {
      TextValue(:final text) => text,
      ColumnsValue(:final columns) => [
        for (final column in columns)
          column.done ? l.conflictDoneColumn(column.name) : column.name,
      ].join(' · '),
      ColumnValue(:final name) => name ?? l.conflictColumnGone,
      StatusValue(:final done) => done ? l.conflictTicked : l.conflictUnticked,
    };

    final base = conflict.base == null ? null : text(conflict.base);
    final theirs = text(conflict.theirs);
    final mine = text(conflict.mine);

    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: [
        _Version(
          label: l.conflictBefore,
          child: base == null
              ? Text(
                  l.conflictBeforeUnknown,
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                )
              : _Plain(text: base),
        ),
        _Version(
          label: l.conflictTheirs,
          child: _Diff(before: base ?? mine, after: theirs),
        ),
        _Version(
          label: l.conflictMine,
          child: _Diff(before: base ?? theirs, after: mine),
        ),
        SheetActions(
          children: [
            TextButton(
              onPressed: () async {
                await ref
                    .read(syncBannerViewModelProvider.notifier)
                    .dismissConflict(conflict);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: Text(l.conflictKeepTheirs),
            ),
            FilledButton(
              onPressed: () async {
                await ref
                    .read(syncBannerViewModelProvider.notifier)
                    .takeMine(conflict);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: Text(l.stateConflictTake),
            ),
          ],
        ),
      ],
    );
  }
}

class _Version extends StatelessWidget {
  const _Version({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .only(bottom: HiwiskiMetrics.space16),
    child: Column(
      crossAxisAlignment: .stretch,
      spacing: HiwiskiMetrics.space6,
      children: [
        Text(label, style: context.tokens.text.sectionLabel),
        Container(
          padding: const .all(HiwiskiMetrics.space12),
          decoration: BoxDecoration(
            color: context.scheme.surfaceContainer,
            borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
          ),
          child: child,
        ),
      ],
    ),
  );
}

class _Plain extends StatelessWidget {
  const _Plain({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => SelectableText(
    text.isEmpty ? '—' : text,
    style: context.texts.bodyMedium,
  );
}

/// [after], with what changed against [before] marked: added on a tint, removed struck
/// through.
class _Diff extends StatelessWidget {
  const _Diff({required this.before, required this.after});

  final String before;
  final String after;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final style = context.texts.bodyMedium;
    if (after.isEmpty && before.isEmpty) return const _Plain(text: '');
    return SelectableText.rich(
      TextSpan(
        style: style,
        children: [
          for (final segment in diffWords(before, after))
            TextSpan(
              text: segment.text,
              style: switch (segment.kind) {
                .same => null,
                .added => TextStyle(
                  backgroundColor: scheme.tertiaryContainer,
                  color: scheme.onTertiaryContainer,
                ),
                .removed => TextStyle(
                  color: scheme.error,
                  decoration: .lineThrough,
                ),
              },
            ),
        ],
      ),
    );
  }
}
