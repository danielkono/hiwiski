import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/generated/export.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/loading_strip.dart';
import '../../../core/ui/notice_bar.dart';
import '../../../core/ui/hiwiski_sheet.dart';
import '../../member_avatar/view/member_avatar.dart';
import '../assignees_view_model.dart';
import '../../../core/ui/tap_target.dart';

/// The assignment chips from the design: avatar 26 and name in a pill,
/// selected on `sec`, outlined otherwise.
///
/// **Assigning shares automatically** — that is why the sentence the
/// caller passes in sits below them.
class AssigneeChips extends ConsumerWidget {
  const AssigneeChips({
    super.key,
    required this.selected,
    required this.onToggle,
    this.hint,
  });

  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final String? hint;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(assigneesViewModelProvider)
      .when(
        skipLoadingOnReload: true,
        loading: () => const LoadingStrip(loading: true),
        // Not loaded — offline, say: the picker said so with nothing, and looked as
        // if there were nobody to assign.
        error: (error, _) => NoticeBar.failure(context, error: error),
        data: (state) => _AssigneePicker(
          hint: hint,
          onToggle: onToggle,
          selected: selected,
          members: state.members,
        ),
      );
}

class _AssigneePicker extends StatelessWidget {
  const _AssigneePicker({
    required this.hint,
    required this.onToggle,
    required this.selected,
    required this.members,
  });

  final String? hint;
  final ValueChanged<String> onToggle;
  final Set<String> selected;
  final List<Member> members;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;
    if (members.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: .start,
      children: [
        Text(l.calAssigned, style: context.tokens.text.sectionLabel),
        const SizedBox(height: HiwiskiMetrics.space8),
        Wrap(
          spacing: HiwiskiMetrics.space8,
          runSpacing: HiwiskiMetrics.space8,
          children: [
            for (final member in members)
              _Pill(
                member: member,
                on: selected.contains(member.id),
                onTap: () => onToggle(member.id),
                scheme: scheme,
              ),
          ],
        ),
        if (hint case final hint?) ...[
          const SizedBox(height: HiwiskiMetrics.space6),
          Text(
            hint,
            style: context.texts.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.member,
    required this.on,
    required this.onTap,
    required this.scheme,
  });

  final Member member;
  final bool on;
  final VoidCallback onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => TapTarget(
    onTap: onTap,
    child: Semantics(
      selected: on,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusPill)),
        child: Container(
          padding: const .fromLTRB(
            HiwiskiMetrics.space4,
            HiwiskiMetrics.space4,
            HiwiskiMetrics.space12,
            HiwiskiMetrics.space4,
          ),
          decoration: BoxDecoration(
            color: on ? scheme.secondaryContainer : null,
            borderRadius: const .all(.circular(HiwiskiMetrics.radiusPill)),
            border: .fromBorderSide(
              BorderSide(
                color: on ? scheme.secondaryContainer : scheme.outline,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: .min,
            spacing: HiwiskiMetrics.space6,
            children: [
              MemberAvatar.of(member, radius: HiwiskiMetrics.avatarSmall),
              Text(
                member.displayName,
                style: context.texts.bodyMedium?.copyWith(
                  fontWeight: .w500,
                  color: on ? scheme.onSecondaryContainer : null,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The assignment sheet: the same chips, "Done" below.
Future<Set<String>?> showAssigneePicker(
  BuildContext context,
  Set<String> current,
) {
  final chosen = {...current};
  return showHiwiskiSheet<Set<String>>(
    context: context,
    title: L.of(context).assignAction,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AssigneeChips(
        selected: chosen,
        onToggle: (id) => setState(
          () => chosen.contains(id) ? chosen.remove(id) : chosen.add(id),
        ),
      ),
    ),
    actions: (context) => [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(L.of(context).actionCancel),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(chosen),
        child: Text(L.of(context).actionDone),
      ),
    ],
  );
}
