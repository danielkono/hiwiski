import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/generated/export.dart' hide Mutation;
import '../../../core/api/hiwiski_failure.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/failure_text.dart';
import '../../../core/ui/group_icon.dart';
import '../../../core/ui/hiwiski_sheet.dart';
import '../family_view_model.dart';
import 'invite_sheet.dart';

/// "New group" or editing a group: name, icon, members — and
/// "Invite a new person and add them right away".
///
/// **No role field any more**: groups are only recipients of a
/// share.
Future<void> showGroupSheet(BuildContext context, {Group? group}) {
  final l = L.of(context);
  return showHiwiskiSheet<void>(
    context: context,
    title: group == null ? l.familyNewGroup : group.name,
    builder: (context) => _GroupBody(group: group),
  );
}

class _GroupBody extends ConsumerStatefulWidget {
  const _GroupBody({this.group});

  final Group? group;

  @override
  ConsumerState<_GroupBody> createState() => _GroupBodyState();
}

class _GroupBodyState extends ConsumerState<_GroupBody> {
  late final _name = TextEditingController(text: widget.group?.name ?? '');

  /// `null` until picked: then the name's guess is shown, and none is stored.
  late String? _picked = widget.group?.iconToken;
  String get _icon => _picked ?? guessedIconToken(_name.text);
  late final Set<String> _members = {...?widget.group?.memberIds};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// [thenInvite]: "invite a new person and add them right away" — the group is
  /// saved first, so the invitation can carry it. It used to close the sheet and open
  /// a blank invitation: a new group was never created, the edits were lost, and the
  /// invitee joined no group.
  Future<void> _save({bool thenInvite = false}) async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = WriteGroupRequest(
      name: name,
      iconToken: _picked,
      memberIds: _members.toList(),
    );
    final navigator = Navigator.of(context);
    try {
      final saved = await saveGroupMutation.run(
        ref,
        (tsx) => tsx
            .get(familyViewModelProvider.notifier)
            .saveGroup(body, id: widget.group?.id),
      );
      if (!mounted) return;
      navigator.pop();
      if (thenInvite && navigator.context.mounted) {
        await showInviteSheet(navigator.context, groupIds: {saved.id});
      }
    } on HiwiskiFailure catch (failure) {
      if (mounted) setState(() => _error = failureText(context, failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks first, and runs alone: one mis-tap on the red "Delete" removed a group that
  /// shares point to — there is no trash for groups — and a save running meanwhile
  /// raced it.
  Future<void> _delete() async {
    final l = L.of(context);
    final group = widget.group;
    if (group == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.groupDeleteConfirm(group.name)),
        content: Text(l.groupDeleteNote),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.actionDelete),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(familyViewModelProvider.notifier).deleteGroup(group.id);
      if (mounted) Navigator.of(context).pop();
    } on HiwiskiFailure catch (failure) {
      if (mounted) setState(() => _error = failureText(context, failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;
    final members =
        ref.watch(familyViewModelProvider).value?.members ?? const <Member>[];

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        if (_error case final error?) ...[
          Text(error, style: TextStyle(color: scheme.error)),
          const SizedBox(height: HiwiskiMetrics.space12),
        ],
        TextField(
          controller: _name,
          autofocus: widget.group == null,
          decoration: InputDecoration(labelText: l.groupName),
        ),
        const SizedBox(height: HiwiskiMetrics.space16),
        Text(l.groupIcon, style: context.tokens.text.sectionLabel),
        const SizedBox(height: HiwiskiMetrics.space8),
        // Until an icon is picked, the one shown follows the name.
        ListenableBuilder(
          listenable: _name,
          builder: (context, _) => Wrap(
            spacing: HiwiskiMetrics.space8,
            children: [
              for (final entry in groupIconTokens.entries)
                IconButton.filledTonal(
                  isSelected: _icon == entry.key,
                  tooltip: groupIconLabel(l, entry.key),
                  icon: Icon(entry.value),
                  onPressed: () => setState(() => _picked = entry.key),
                  style: IconButton.styleFrom(
                    backgroundColor: _icon == entry.key
                        ? scheme.secondaryContainer
                        : scheme.surfaceContainerHigh,
                    foregroundColor: _icon == entry.key
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space16),
        Text(l.familyMembers, style: context.tokens.text.sectionLabel),
        for (final member in members)
          InkWell(
            onTap: () => setState(
              () => _members.contains(member.id)
                  ? _members.remove(member.id)
                  : _members.add(member.id),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: HiwiskiMetrics.minTapTarget,
              ),
              child: Row(
                spacing: HiwiskiMetrics.space12,
                children: [
                  Icon(
                    _members.contains(member.id)
                        ? HiwiskiSymbols.checkBox
                        : HiwiskiSymbols.checkBoxOutlineBlank,
                    fill: _members.contains(member.id) ? 1 : 0,
                    color: _members.contains(member.id)
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Text(
                      member.displayName,
                      style: context.texts.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(
              HiwiskiSymbols.qrCode2,
              size: HiwiskiMetrics.icon18,
            ),
            label: Text(l.groupInviteNew),
            onPressed: _busy ? null : () => _save(thenInvite: true),
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space8),
        Text(
          l.groupNote,
          style: context.texts.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        SheetActions(
          children: [
            if (widget.group != null)
              TextButton(
                onPressed: _busy ? null : _delete,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                child: Text(l.actionDelete),
              ),
            const Spacer(),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: Text(l.actionCancel),
            ),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(widget.group == null ? l.tagCreate : l.actionSave),
            ),
          ],
        ),
      ],
    );
  }
}
