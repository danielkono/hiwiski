import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/generated/export.dart';
import '../../../core/api/hiwiski_failure.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/failure_text.dart';
import '../../../core/ui/loading_strip.dart';
import '../../../core/ui/notice_bar.dart';
import '../../../core/ui/hiwiski_sheet.dart';
import '../../../domain/access/access_rules.dart';
import '../../../domain/common/item_ref.dart';
import '../../member_avatar/view/member_avatar.dart';
import '../sharing_view_model.dart';
import 'share_subject_picker.dart';
import 'subject_name.dart';

/// The share sheet — **the same on every item**.
///
/// The order is fixed: owner, automatically assigned, inherited, own,
/// "Add person or group". Whoever may not change the share still sees the sheet —
/// read-only. Knowing who sees something is not a privilege.
Future<void> showShareSheet(BuildContext context, {required ItemRef item}) {
  return showHiwiskiSheet<void>(
    context: context,
    title: L.of(context).shareTitle,
    builder: (context) => _ShareBody(item: item),
  );
}

class _ShareBody extends ConsumerWidget {
  const _ShareBody({required this.item});

  final ItemRef item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(sharingViewModelProvider(item))
        .when(
          skipLoadingOnReload: true,
          loading: () => const Padding(
            padding: .symmetric(vertical: HiwiskiMetrics.space24),
            child: LoadingStrip(loading: true),
          ),
          error: (error, _) => NoticeBar.failure(
            context,
            error: error,
            onRetry: () =>
                ref.read(sharingViewModelProvider(item).notifier).retry(),
          ),
          data: (state) => _Entries(
            sheet: state.sheet,
            target: item,
            directory: state.directory,
          ),
        );
  }
}

class _Entries extends ConsumerWidget {
  const _Entries({
    required this.sheet,
    required this.target,
    required this.directory,
  });

  final ShareSheet sheet;
  final ItemRef target;
  final ShareDraftState directory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final members = directory.members;
    final groups = directory.groups;

    final own = sheet.entries
        .where((entry) => entry.source == .direct)
        .toList();
    final inherited = sheet.entries
        .where((entry) => entry.source == .inherited)
        .toList();
    final assigned = sheet.entries
        .where((entry) => entry.source == .assigned)
        .toList();
    final owner = sheet.entries.where((entry) => entry.source == .owner);

    // Groups sit at the top of the list, people below.
    own.sort(
      (a, b) => switch ((a.subjectType, b.subjectType)) {
        (final x, final y) when x == y => 0,
        (ShareSubjectType.group, _) => -1,
        _ => 1,
      },
    );

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        for (final entry in owner)
          _Row(
            entry: entry,
            members: members,
            groups: groups,
            trailing: Text(
              l.shareOwner,
              style: context.texts.bodySmall?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final entry in assigned)
          _Row(
            entry: entry,
            members: members,
            groups: groups,
            // It cannot be removed on its own — it goes away with the
            // assignment.
            note: l.shareAssigned,
          ),
        for (final entry in inherited)
          _Row(
            entry: entry,
            members: members,
            groups: groups,
            note: l.shareInherited(
              sheet.inheritedFromName ?? sheet.inheritedFromType ?? '',
            ),
            dimmed: true,
          ),
        if (own.isNotEmpty) ...[
          const SizedBox(height: HiwiskiMetrics.space12),
          Text(l.shareOwnShares, style: context.tokens.text.sectionLabel),
        ],
        for (final entry in own)
          _Row(
            entry: entry,
            members: members,
            groups: groups,
            trailing: sheet.mayEdit
                ? ShareLevelMenu(
                    level: entry.level,
                    offerCheck: checkApplies(target.type),
                    onChanged: (level) => _write(context, ref, [
                      for (final other in own)
                        if (other.subjectId == entry.subjectId)
                          _toWrite(other, level)
                        else
                          _toWrite(other, other.level),
                    ]),
                    onRemove: () => _write(context, ref, [
                      for (final other in own)
                        if (other.subjectId != entry.subjectId)
                          _toWrite(other, other.level),
                    ]),
                  )
                : Text(
                    _levelLabel(l, entry.level),
                    style: context.texts.bodySmall?.copyWith(
                      color: context.scheme.onSurfaceVariant,
                    ),
                  ),
          ),
        if (own.isEmpty && inherited.isEmpty && assigned.isEmpty)
          Padding(
            padding: const .symmetric(vertical: HiwiskiMetrics.space12),
            child: Text(
              l.shareNobody,
              style: context.texts.bodyMedium?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: HiwiskiMetrics.space12),
        if (sheet.mayEdit)
          OutlinedButton.icon(
            icon: const Icon(HiwiskiSymbols.personAdd),
            label: Text(l.shareAddSubject),
            onPressed: () => _add(context, ref, own, members, groups),
          )
        else
          // A button that only produces an error message is not shown.
          // The reason is shown instead.
          Text(
            l.shareReadOnlyNote,
            style: context.texts.bodySmall?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  static WriteShare _toWrite(ShareEntry entry, AccessLevel level) => .new(
    subjectType: entry.subjectType,
    subjectId: entry.subjectId,
    level: level,
  );

  static String _levelLabel(L l, AccessLevel level) =>
      shareLevelLabel(l, level);

  /// Writes the shares and says so when it did not work.
  ///
  /// Called from menus and buttons that do not wait for it: a refusal or an unknown
  /// sheet offline used to end as an unhandled error while the menu closed as if the
  /// change had been taken, and the row quietly kept its old level.
  Future<void> _write(
    BuildContext context,
    WidgetRef ref,
    List<WriteShare> shares,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(sharingViewModelProvider(target).notifier)
          .setShares(shares);
    } on HiwiskiFailure catch (failure) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(failureText(context, failure))),
      );
    }
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    List<ShareEntry> own,
    List<Member> members,
    List<Group> groups,
  ) async {
    // The first own share replaces inheritance. It starts from what is
    // inherited, so adding Kids does not quietly take Parents' access away; and an
    // inherited subject can be picked to give it a level of its own.
    final inherited = own.isEmpty
        ? sheet.entries.where((entry) => entry.source == .inherited).toList()
        : const <ShareEntry>[];
    final already = {
      for (final entry in sheet.entries)
        if (entry.source != .inherited) entry.subjectId,
    };

    final choice = await showHiwiskiSheet<WriteShare>(
      context: context,
      title: L.of(context).shareAddSubject,
      builder: (context) => ShareSubjectPicker(
        members: [
          for (final member in members)
            if (!already.contains(member.id)) member,
        ],
        groups: [
          for (final group in groups)
            if (!already.contains(group.id)) group,
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    await _write(context, ref, [
      for (final entry in own) _toWrite(entry, entry.level),
      for (final entry in inherited)
        if (entry.subjectId != choice.subjectId) _toWrite(entry, entry.level),
      choice,
    ]);
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.members,
    required this.groups,
    this.trailing,
    this.note,
    this.dimmed = false,
  });

  final ShareEntry entry;
  final List<Member> members;
  final List<Group> groups;
  final Widget? trailing;
  final String? note;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final isGroup = entry.subjectType == .group;
    final member = members
        .where((candidate) => candidate.id == entry.subjectId)
        .firstOrNull;
    final name = subjectName(
      entry.subjectType,
      entry.subjectId,
      members,
      groups,
    );

    return Opacity(
      // Inherited ones in grey.
      opacity: dimmed ? 0.6 : 1,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: switch (member) {
          _ when isGroup => CircleAvatar(
            radius: HiwiskiMetrics.avatarMedium,
            backgroundColor: scheme.secondaryContainer,
            child: Icon(
              HiwiskiSymbols.group,
              color: scheme.onSecondaryContainer,
              size: HiwiskiMetrics.icon20,
            ),
          ),
          null => const CircleAvatar(radius: HiwiskiMetrics.avatarMedium),
          final member => MemberAvatar.of(member),
        },
        title: Text(name),
        subtitle: switch (note) {
          null => null,
          final note => Text(note),
        },
        trailing: trailing,
      ),
    );
  }
}

/// The level picker.
///
/// "A field without a control counts as not implemented": in an earlier version the share
/// dialog hard-coded `WRITE` because exactly this menu was missing.
class ShareLevelMenu extends StatelessWidget {
  /// The menu's value for "remove" — every other entry is an [AccessLevel].
  static const _remove = 'remove';

  const ShareLevelMenu({
    super.key,
    required this.level,
    required this.onChanged,
    required this.onRemove,
    this.offerCheck = true,
  });

  final AccessLevel level;

  /// Whether *check off* is on offer — only for what can be ticked ([checkApplies]).
  final bool offerCheck;
  final ValueChanged<AccessLevel> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return PopupMenuButton<Object>(
      onSelected: (value) =>
          value is AccessLevel ? onChanged(value) : onRemove(),
      itemBuilder: (context) => [
        for (final candidate in [
          AccessLevel.read,
          if (offerCheck || level == .check) AccessLevel.check,
          AccessLevel.write,
        ])
          PopupMenuItem(
            value: candidate,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(shareLevelLabel(l, candidate)),
              subtitle: Text(switch (candidate) {
                .check => l.shareLevelCheckHint,
                .write => l.shareLevelWriteHint,
                _ => l.shareLevelReadHint,
              }),
              trailing: candidate == level
                  ? const Icon(HiwiskiSymbols.check)
                  : null,
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(value: _remove, child: Text(l.shareRemove)),
      ],
      child: Row(
        mainAxisSize: .min,
        children: [
          Text(shareLevelLabel(l, level), style: context.texts.labelLarge),
          const Icon(HiwiskiSymbols.arrowDropDown),
        ],
      ),
    );
  }
}

/// "read", "check off", "write".
String shareLevelLabel(L l, AccessLevel level) => switch (level) {
  .check => l.shareLevelCheck,
  .write => l.shareLevelWrite,
  _ => l.shareLevelRead,
};
