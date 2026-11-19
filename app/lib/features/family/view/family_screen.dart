import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../components/member_avatar/view/member_avatar.dart';
import '../../../core/api/generated/export.dart';
import '../../../core/api/hiwiski_failure.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/shell/breakpoints.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/failure_text.dart';
import '../../../core/ui/group_icon.dart';
import '../../../core/ui/page_header.dart';
import '../../../core/ui/hiwiski_page.dart';
import '../family_view_model.dart';
import 'family_keys.dart';
import 'group_names.dart';
import 'group_sheet.dart';
import 'invite_sheet.dart';
import 'member_actions.dart';

/// Family: groups as a card grid, the members below.
///
/// **Permissions are visible**: "New member" and "New group" only appear for the
/// administrator. A button that only produces an error message is not shown.
class FamilyScreen extends ConsumerWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = PageHeader(
      title: L.of(context).familyTitle,
      onBack: () => const AccountRoute().go(context),
    );
    return ref
        .watch(familyViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(
            header: header,
            error: error,
            onRetry: () => ref.read(familyViewModelProvider.notifier).retry(),
          ),
          data: (state) => _FamilyPage(state: state),
        );
  }
}

class _FamilyPage extends StatelessWidget {
  const _FamilyPage({required this.state});

  final FamilyState state;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final padding = Breakpoint.of(context).pagePadding;
    final isAdmin = state.isAdmin;

    return HiwiskiPage(
      header: PageHeader(
        title: l.familyTitle,
        onBack: () => const AccountRoute().go(context),
        detail:
            '${l.familyMemberCount(state.members.length)} · '
            '${l.familyGroupCount(state.groups.length)}',
      ),
      body: ListView(
        padding: padding,
        children: [
          _Heading(
            l.familyGroups,
            action: isAdmin
                ? OutlinedButton.icon(
                    icon: const Icon(
                      HiwiskiSymbols.groupAdd,
                      size: HiwiskiMetrics.icon18,
                    ),
                    label: Text(l.familyNewGroup),
                    onPressed: () => showGroupSheet(context),
                  )
                : null,
          ),
          _GroupGrid(groups: state.groups, editable: isAdmin),
          const SizedBox(height: HiwiskiMetrics.space20),
          _Heading(
            l.familyMembers,
            action: isAdmin
                ? OutlinedButton.icon(
                    icon: const Icon(
                      HiwiskiSymbols.personAdd,
                      size: HiwiskiMetrics.icon18,
                    ),
                    label: Text(l.familyNewMember),
                    onPressed: () => showInviteSheet(context),
                  )
                : null,
          ),
          Container(
            decoration: BoxDecoration(
              color: context.scheme.surfaceContainerLow,
              border: .fromBorderSide(
                BorderSide(color: context.scheme.outlineVariant),
              ),
              borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
            ),
            clipBehavior: .antiAlias,
            child: Column(
              children: [
                for (final (i, row) in [
                  for (final member in state.members)
                    _MemberRow(member: member) as Widget,
                  for (final invitation in state.invitations)
                    _InvitationRow(invitation: invitation),
                ].indexed) ...[
                  if (i > 0)
                    Divider(
                      height: HiwiskiMetrics.hairline,
                      color: context.tokens.divider,
                    ),
                  row,
                ],
              ],
            ),
          ),
          const SizedBox(height: HiwiskiMetrics.space32),
        ],
      ),
    );
  }
}

/// A card grid means: equally wide columns, as many as fit at the given minimum
/// width, at least one.
class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .only(bottom: HiwiskiMetrics.space12),
    child: Row(
      children: [
        Expanded(child: Text(text, style: context.tokens.text.sectionLabel)),
        ?action,
      ],
    ),
  );
}

class _GroupGrid extends StatelessWidget {
  const _GroupGrid({required this.groups, required this.editable});

  final List<Group> groups;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / HiwiskiMetrics.gridMinGroup)
            .floor()
            .clamp(1, 6);
        const gap = HiwiskiMetrics.space12;
        final width = ((constraints.maxWidth - (columns - 1) * gap) / columns)
            .floorToDouble();
        // Columns of equal width, each card as high as its text: a fixed aspect
        // ratio cut the member count off on a tablet and with larger text.
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final group in groups)
              SizedBox(
                width: width,
                child: _GroupCard(group: group, editable: editable),
              ),
          ],
        );
      },
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.editable});

  final Group group;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.outlineVariant),
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
      ),
      clipBehavior: .antiAlias,
      child: InkWell(
        onTap: editable ? () => showGroupSheet(context, group: group) : null,
        child: Padding(
          padding: const .all(HiwiskiMetrics.space14),
          child: Row(
            spacing: HiwiskiMetrics.space12,
            children: [
              Container(
                width: HiwiskiMetrics.tileSize,
                height: HiwiskiMetrics.tileSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: const .all(
                    .circular(HiwiskiMetrics.radiusMenu),
                  ),
                ),
                child: Icon(
                  groupIcon(group),
                  color: scheme.onSecondaryContainer,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  mainAxisSize: .min,
                  children: [
                    Text(
                      group.name,
                      overflow: .ellipsis,
                      style: context.texts.titleSmall,
                    ),
                    Text(
                      l.familyMemberCount(group.memberIds.length),
                      style: context.texts.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberRow extends ConsumerWidget {
  const _MemberRow({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final state = ref.watch(familyViewModelProvider).value;
    final isAdmin = state?.isAdmin ?? false;
    final groups = state?.groups ?? const <Group>[];
    final names = groupNamesOf(groups, member.groupIds ?? const []);

    return Padding(
      padding: const .symmetric(
        horizontal: HiwiskiMetrics.space16,
        vertical: HiwiskiMetrics.space8,
      ),
      child: Row(
        children: [
          MemberAvatar.of(member, radius: HiwiskiMetrics.avatarLarge),
          const SizedBox(width: HiwiskiMetrics.space14),
          Expanded(
            child: Wrap(
              crossAxisAlignment: .center,
              spacing: HiwiskiMetrics.space14,
              runSpacing: HiwiskiMetrics.space6,
              children: [
                Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      member.displayName,
                      style: context.texts.bodyLarge?.copyWith(
                        fontWeight: .w600,
                      ),
                    ),
                    Text(
                      '@${member.username}',
                      style: context.tokens.text.monoSmall,
                    ),
                    if (member.disabled ?? false)
                      Text(
                        l.familyDisabled,
                        style: context.texts.labelMedium?.copyWith(
                          color: context.scheme.error,
                        ),
                      ),
                  ],
                ),
                // Groups as chips on `sf3`.
                for (final name in names)
                  Container(
                    padding: const .symmetric(
                      horizontal: HiwiskiMetrics.space10,
                      vertical: HiwiskiMetrics.space4,
                    ),
                    decoration: BoxDecoration(
                      color: context.scheme.surfaceContainerHigh,
                      borderRadius: const .all(
                        .circular(HiwiskiMetrics.radiusChip),
                      ),
                    ),
                    child: Text(name, style: context.texts.labelMedium),
                  ),
              ],
            ),
          ),
          if (isAdmin && !member.isAdmin) MemberActions(member: member),
        ],
      ),
    );
  }
}

/// People who were invited but have not joined yet are listed with the time left and a
/// placeholder avatar -- without the code: the server keeps only its
/// hash, and it was shown once, when the invitation was created.
///
/// One handed to the wrong person, or no longer needed, is withdrawn here: otherwise
/// its code would open a family account for whoever has it until it runs out.
class _InvitationRow extends ConsumerWidget {
  const _InvitationRow({required this.invitation});

  final Invitation invitation;

  Future<void> _revoke(BuildContext context, WidgetRef ref) async {
    final l = L.of(context);
    final scheme = context.scheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.familyRevokeConfirm),
        content: Text(l.familyRevokeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            key: FamilyKeys.revokeConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.familyRevoke),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;
    try {
      await ref
          .read(familyViewModelProvider.notifier)
          .revokeInvitation(invitation);
    } on HiwiskiFailure catch (failure) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failureText(context, failure))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final scheme = context.scheme;
    // Rounded up, and minutes in the last hour: truncated, a fresh one-hour code said
    // "0 h" and a seven-day one "6 days". One that ran out while the list was loaded
    // said "-2 h"; it now says it has expired.
    final minutes = invitation.expiresAt.difference(clock.now()).inMinutes;
    final subtitle = minutes <= 0
        ? l.familyInviteExpired
        : l.familyInvited(switch (minutes) {
            < Duration.minutesPerHour => l.unitMinutes(minutes),
            < Duration.minutesPerDay => l.unitHours(
              (minutes / Duration.minutesPerHour).ceil(),
            ),
            _ => l.unitDays((minutes / Duration.minutesPerDay).ceil()),
          });

    return ListTile(
      contentPadding: const .symmetric(
        horizontal: HiwiskiMetrics.space16,
        vertical: HiwiskiMetrics.space4,
      ),
      leading: CircleAvatar(
        radius: HiwiskiMetrics.avatarLarge,
        backgroundColor: scheme.surfaceContainerHigh,
        child: Icon(HiwiskiSymbols.moreHoriz, color: scheme.onSurfaceVariant),
      ),
      title: Text(invitation.displayName ?? l.familyNewMember),
      subtitle: Text(
        subtitle,
        style: context.tokens.text.monoSmall.copyWith(color: scheme.primary),
      ),
      trailing: IconButton(
        key: FamilyKeys.revoke(invitation.id),
        icon: const Icon(HiwiskiSymbols.close),
        tooltip: switch (invitation.displayName) {
          final name? => l.familyRevokeTooltipFor(name),
          null => l.familyRevokeTooltip,
        },
        onPressed: () => _revoke(context, ref),
      ),
    );
  }
}
