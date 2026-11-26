import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/common/wire.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/history_field_label.dart';
import '../../../core/ui/hiwiski_sheet.dart';
import '../../../domain/common/word_diff.dart';
import '../../../domain/sync/conflict_values.dart';
import '../../../domain/sync/sync_items.dart';
import '../../../domain/wiki/pinboard.dart';
import '../sync_banner_view_model.dart';

/// **A conflict, resolved by looking at it** — what it was, what the server has now,
/// and one's own version, each change against the starting point highlighted.
///
/// The banner used to show "old → new" in half a line, and for a page's text only a
/// link into the version history. Whoever has to choose needs to see what each side
/// changed.
///
/// [onPinboard] decides a pinboard's conflict where it is shown already — the map
/// open under the banner — and says whether it did.
Future<void> showConflictSheet(
  BuildContext context,
  SyncConflict conflict, {
  PinboardConflictHandler? onPinboard,
}) {
  final l = L.of(context);
  return showHiwiskiSheet<void>(
    context: context,
    title: l.conflictTitle(historyFieldLabel(l, conflict.field)),
    builder: (context) =>
        _ConflictBody(conflict: conflict, onPinboard: onPinboard),
  );
}

/// Shows an element's conflict on its map — `false` when that map is not the one
/// open here.
typedef PinboardConflictHandler = bool Function(String pageId, String entityId);

class _ConflictBody extends ConsumerWidget {
  const _ConflictBody({required this.conflict, required this.onPinboard});

  final SyncConflict conflict;
  final PinboardConflictHandler? onPinboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final state = ref.watch(syncBannerViewModelProvider).value;
    // The columns a card's column id is looked up in: the board's now, and those any
    // side of a board's own conflict carries.
    final board = [...?state?.boards[conflict.id]];
    final index = state?.index;

    /// The stored value as a person reads it: names, not ids.
    String text(SyncConflict of, String? json) => switch (readConflictValue(
      of.field,
      json,
      board: board,
    )) {
      // A link element's target by its title and number, a member element's by
      // their name — not by its address.
      TextValue(:final text)
          when of.field == WireFields.target &&
              of.entityType == EntityTypes.pinboardNode &&
              index != null =>
        targetLabelOf(text, index) ??
            state?.members[memberIdOf(text)] ??
            l.pinboardLinkGone,
      TextValue(:final text) => text,
      ColumnsValue(:final columns) => [
        for (final column in columns)
          column.done ? l.conflictDoneColumn(column.name) : column.name,
      ].join(' · '),
      ColumnValue(:final name) => name ?? l.conflictColumnGone,
      StatusValue(:final done) => done ? l.conflictTicked : l.conflictUnticked,
    };

    // An element's position or size: both of its values, as one — a size width by
    // height, whichever of its two conflicts was found first.
    final group = inReadingOrder([conflict, ...?state?.partners[conflict.id]]);
    final size = pinboardConflictGroup(conflict.field) == WireFields.width;
    String side(String? Function(SyncConflict conflict) of) =>
        [for (final each in group) text(each, of(each))]
            .join(size ? _by : _and);

    final pinboard = state?.pinboards[conflict.id];
    final base = conflict.base == null ? null : side((each) => each.base);
    final theirs = side((each) => each.theirs);
    final mine = side((each) => each.mine);

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
        // An element of a pinboard is decided on its map, where it can be seen among
        // the others.
        if (pinboard != null)
          Align(
            alignment: .centerLeft,
            child: TextButton.icon(
              icon: const Icon(HiwiskiSymbols.hub),
              label: Text(l.pinboardConflictShow),
              onPressed: () {
                // Looked up now: the sheet is gone in a moment.
                final router = GoRouter.maybeOf(context);
                // Every sheet over the page goes — this one and the list it may
                // have been opened from: the map is where it is decided now.
                Navigator.of(context).popUntil((route) => route is! PopupRoute);
                if (onPinboard?.call(pinboard, conflict.entityId) ?? false) {
                  return;
                }
                // The pushed route answers nothing here.
                router
                    ?.push<void>(
                      PinboardRoute(
                        pageId: pinboard,
                        node: conflict.entityId,
                      ).location,
                    )
                    .ignore();
              },
            ),
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

/// Between the two values of a position, and of a size.
const _and = ', ';
const _by = ' × ';

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
