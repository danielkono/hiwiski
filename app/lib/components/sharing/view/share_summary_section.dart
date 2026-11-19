import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/generated/export.dart';
import '../../../core/api/hiwiski_failure.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/failure_text.dart';
import '../../../core/ui/info_action.dart';
import '../../../core/ui/info_section.dart';
import '../../../domain/common/item_ref.dart';
import '../sharing_view_model.dart';
import 'share_sheet.dart';
import 'subject_name.dart';

/// The **Sharing** section of the info bar.
///
/// Owner, automatically assigned, inherited, own — each row with icon, name and
/// level; below it "Add", which opens the same sheet as everywhere else. The rows
/// come from the same call as the sheet; offline, the section says so instead of
/// showing an empty list.
class ShareSummarySection extends ConsumerWidget {
  const ShareSummarySection({super.key, required this.item});

  final ItemRef item;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      !ref.watch(sharingAvailableViewModelProvider)
      ? const SizedBox.shrink()
      : ref
            .watch(sharingViewModelProvider(item))
            .when(
              skipLoadingOnReload: true,
              loading: () =>
                  _ShareSummaryBody(item: item, state: null, error: null),
              error: (error, _) =>
                  _ShareSummaryBody(item: item, state: null, error: error),
              data: (state) =>
                  _ShareSummaryBody(item: item, state: state, error: null),
            );
}

/// The section — also while the sheet is still coming, and when it failed: then
/// its empty line says why.
class _ShareSummaryBody extends StatelessWidget {
  const _ShareSummaryBody({
    required this.item,
    required this.state,
    required this.error,
  });

  final ItemRef item;
  final SharingState? state;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final members = state?.directory.members ?? const <Member>[];
    final groups = state?.directory.groups ?? const <Group>[];
    final value = state?.sheet;

    String nameOf(ShareEntry entry) =>
        subjectName(entry.subjectType, entry.subjectId, members, groups);

    IconData iconOf(ShareEntry entry) => switch (entry.source) {
      .assigned => HiwiskiSymbols.assignmentInd,
      _ when entry.subjectType == .group => HiwiskiSymbols.familyRestroom,
      _ => HiwiskiSymbols.person,
    };

    String modeOf(ShareEntry entry) => switch (entry.source) {
      .owner => l.shareOwner,
      .assigned => l.shareAssigned,
      .inherited =>
        '${shareLevelLabel(l, entry.level)} · '
            '${l.shareInherited(value?.inheritedFromName ?? value?.inheritedFromType ?? '')}',
      _ => shareLevelLabel(l, entry.level),
    };

    final order = [
      ShareSource.owner,
      ShareSource.assigned,
      ShareSource.inherited,
      ShareSource.direct,
    ];
    final entries = [...?value?.entries]
      ..sort(
        (a, b) => order.indexOf(a.source).compareTo(order.indexOf(b.source)),
      );

    // **One row per person or group.** Whoever owns a task and is also assigned to it
    // appeared twice; now the row names both: "Owner · assigned". The first entry in
    // the order above decides the icon.
    final rows = <(ShareSubjectType, String), List<ShareEntry>>{};
    for (final entry in entries) {
      rows
          .putIfAbsent((entry.subjectType, entry.subjectId), () => [])
          .add(entry);
    }

    return InfoSection(
      label: l.shareTitle,
      // "Offline" only when it is: a new item the server does not know yet, or a
      // refusal, said "offline" too while the device was online.
      emptyLabel: switch (error) {
        null => ' ',
        final error when HiwiskiFailure.from(error).isNetwork =>
          l.historyOffline,
        // Created here, not on the server yet: nothing to say until it is.
        final error when HiwiskiFailure.from(error).status == 404 => ' ',
        final error => failureText(context, HiwiskiFailure.from(error)),
      },
      action: value?.mayEdit ?? false
          ? InfoAction(
              icon: HiwiskiSymbols.personAdd,
              label: l.actionAdd,
              onTap: () => showShareSheet(context, item: item),
            )
          : null,
      children: [
        for (final row in rows.values)
          if (row case [final first, ...])
            Padding(
              padding: const .symmetric(vertical: HiwiskiMetrics.space2),
              child: Row(
                children: [
                  Icon(
                    iconOf(first),
                    size: HiwiskiMetrics.icon18,
                    color: context.scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: HiwiskiMetrics.space8),
                  Expanded(
                    child: Text(
                      nameOf(first),
                      style: context.texts.bodyMedium,
                      overflow: .ellipsis,
                    ),
                  ),
                  const SizedBox(width: HiwiskiMetrics.space6),
                  Flexible(
                    child: Text(
                      row.map(modeOf).join(' · '),
                      textAlign: .end,
                      style: context.texts.bodySmall?.copyWith(
                        color: context.scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
