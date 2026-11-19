import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/generated/export.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/group_icon.dart';
import '../../../core/ui/info_action.dart';
import '../../../core/ui/info_section.dart';
import '../../member_avatar/view/member_avatar.dart';
import '../assignees_view_model.dart';
import 'assignees.dart';

/// The **Assigned** section of the info bar: avatars with names, "Assign"
/// below.
class AssigneesSection extends ConsumerWidget {
  const AssigneesSection({super.key, required this.assignees, this.onChanged});

  final List<String> assignees;

  /// `null` if the reader may not change it — then "Assign" is missing.
  final ValueChanged<Set<String>>? onChanged;

  /// The assignees are the item's — shown also while the family is still coming or
  /// could not be had (offline): then they are "someone not loaded here", never
  /// "nobody".
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(assigneesViewModelProvider)
      .when(
        skipLoadingOnReload: true,
        loading: () => _AssigneesBody(
          onChanged: onChanged,
          assignees: assignees,
          state: null,
        ),
        error: (_, _) => _AssigneesBody(
          onChanged: onChanged,
          assignees: assignees,
          state: null,
        ),
        data: (state) => _AssigneesBody(
          onChanged: onChanged,
          assignees: assignees,
          state: state,
        ),
      );
}

class _AssigneesBody extends StatelessWidget {
  const _AssigneesBody({
    required this.onChanged,
    required this.assignees,
    required this.state,
  });

  final ValueChanged<Set<String>>? onChanged;
  final List<String> assignees;
  final AssigneesState? state;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final members = state?.members ?? const <Member>[];
    final groups = state?.groups ?? const <Group>[];

    return InfoSection(
      label: l.calAssigned,
      emptyLabel: l.assignNobody,
      action: onChanged == null
          ? null
          : InfoAction(
              icon: HiwiskiSymbols.personAdd,
              label: l.assignAction,
              onTap: () async {
                final next = await showAssigneePicker(
                  context,
                  assignees.toSet(),
                );
                if (next != null) onChanged?.call(next);
              },
            ),
      children: [
        for (final id in assignees)
          if (members.where((member) => member.id == id).firstOrNull
              case final member?)
            _Line(
              leading: MemberAvatar.of(
                member,
                radius: HiwiskiMetrics.avatarSmall,
              ),
              name: member.displayName,
            )
          else if (groups.where((group) => group.id == id).firstOrNull
              case final group?)
            _Line(
              leading: Icon(
                groupIcon(group),
                size: HiwiskiMetrics.icon20,
                color: context.scheme.onSurfaceVariant,
              ),
              name: group.name,
            )
          // Not resolved — members not loaded, or someone gone: still someone. Left
          // out, a task with assignees said "Nobody assigned".
          else
            _Line(
              leading: Icon(
                HiwiskiSymbols.person,
                size: HiwiskiMetrics.icon20,
                color: context.scheme.onSurfaceVariant,
              ),
              name: l.assignUnknown,
            ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.leading, required this.name});

  final Widget leading;
  final String name;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .symmetric(vertical: HiwiskiMetrics.space2),
    child: Row(
      spacing: HiwiskiMetrics.space10,
      children: [
        SizedBox(
          width: 2 * HiwiskiMetrics.avatarSmall,
          child: Center(child: leading),
        ),
        Expanded(child: Text(name, style: context.texts.bodyMedium)),
      ],
    ),
  );
}
