import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/generated/export.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/loading_strip.dart';
import '../../../core/ui/notice_bar.dart';
import '../../../core/ui/hiwiski_sheet.dart';
import '../../../domain/access/access_rules.dart';
import '../../member_avatar/view/member_avatar.dart';
import '../sharing_view_model.dart';
import 'share_sheet.dart';
import 'share_subject_picker.dart';
import 'subject_name.dart';

/// The share of an item **that does not exist yet** — in the "New list",
/// "New event" and "New calendar" sheets.
///
/// The same rows and the same level menu as in the share sheet, only as a draft:
/// the shares are set once the server knows the item
/// (`PendingShares`).
class ShareDraftSection extends ConsumerWidget {
  const ShareDraftSection({
    super.key,
    required this.itemType,
    required this.shares,
    required this.onChanged,
  });

  /// The type of the item to be — it decides whether *check off* is on offer.
  final String itemType;
  final List<WriteShare> shares;
  final ValueChanged<List<WriteShare>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      !ref.watch(sharingAvailableViewModelProvider)
      ? const SizedBox.shrink()
      : ref
            .watch(shareDraftViewModelProvider)
            .when(
              skipLoadingOnReload: true,
              loading: () => const LoadingStrip(loading: true),
              error: (error, _) => NoticeBar.failure(context, error: error),
              data: (directory) => _ShareDraftBody(
                onChanged: onChanged,
                shares: shares,
                itemType: itemType,
                directory: directory,
              ),
            );
}

class _ShareDraftBody extends StatelessWidget {
  const _ShareDraftBody({
    required this.onChanged,
    required this.shares,
    required this.itemType,
    required this.directory,
  });

  final ValueChanged<List<WriteShare>> onChanged;
  final List<WriteShare> shares;
  final String itemType;
  final ShareDraftState directory;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;
    final me = directory.me;
    final members = directory.members;
    final groups = directory.groups;

    // Groups at the top, people below.
    final sorted = [...shares]
      ..sort(
        (a, b) => switch ((a.subjectType, b.subjectType)) {
          (final x, final y) when x == y => 0,
          (ShareSubjectType.group, _) => -1,
          _ => 1,
        },
      );

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(l.shareTitle, style: context.tokens.text.sectionLabel),
        const SizedBox(height: HiwiskiMetrics.space4),
        if (me != null)
          _ShareRow(
            leading: MemberAvatar.of(me),
            name: l.youSuffix(me.displayName),
            trailing: Text(
              l.shareOwner,
              style: context.texts.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final share in sorted)
          _ShareRow(
            leading: share.subjectType == .group
                ? CircleAvatar(
                    radius: HiwiskiMetrics.avatarMedium,
                    backgroundColor: scheme.secondaryContainer,
                    child: Icon(
                      HiwiskiSymbols.group,
                      color: scheme.onSecondaryContainer,
                      size: HiwiskiMetrics.icon20,
                    ),
                  )
                : switch (members
                      .where((m) => m.id == share.subjectId)
                      .firstOrNull) {
                    final member? => MemberAvatar.of(member),
                    null => const CircleAvatar(
                      radius: HiwiskiMetrics.avatarMedium,
                    ),
                  },
            name: subjectName(
              share.subjectType,
              share.subjectId,
              members,
              groups,
            ),
            trailing: ShareLevelMenu(
              level: share.level,
              offerCheck: checkApplies(itemType),
              onChanged: (level) => onChanged([
                for (final other in shares)
                  other.subjectId == share.subjectId
                      ? other.copyWith(level: level)
                      : other,
              ]),
              onRemove: () => onChanged([
                for (final other in shares)
                  if (other.subjectId != share.subjectId) other,
              ]),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(
              HiwiskiSymbols.personAdd,
              size: HiwiskiMetrics.icon18,
            ),
            label: Text(l.shareAddSubject),
            onPressed: () async {
              final taken = {
                ...shares.map((share) => share.subjectId),
                ?me?.id,
              };
              final choice = await showHiwiskiSheet<WriteShare>(
                context: context,
                title: l.shareAddSubject,
                builder: (context) => ShareSubjectPicker(
                  members: [
                    for (final m in members)
                      if (!taken.contains(m.id)) m,
                  ],
                  groups: [
                    for (final g in groups)
                      if (!taken.contains(g.id)) g,
                  ],
                ),
              );
              if (choice != null) onChanged([...shares, choice]);
            },
          ),
        ),
      ],
    );
  }
}

/// One row of the draft: avatar, name, and what to do with it.
class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.leading,
    required this.name,
    required this.trailing,
  });

  final Widget leading;
  final String name;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: HiwiskiMetrics.minTapTarget),
    child: Row(
      children: [
        leading,
        const SizedBox(width: HiwiskiMetrics.space12),
        Expanded(child: Text(name, style: context.texts.bodyLarge)),
        trailing,
      ],
    ),
  );
}
