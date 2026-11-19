import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/generated/export.dart';
import '../../../core/api/hiwiski_failure.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/ui/failure_text.dart';
import '../family_view_model.dart';
import 'invite_sheet.dart';

enum _MemberAction { resetPassword, signOutDevices, disable, enable }

/// The administrator's actions on a member: reset the
/// password, sign out every device, disable or enable again.
///
/// The last two exist for a phone that was lost or stolen, or a member who left: a
/// password reset alone held only until the member chose a new password.
class MemberActions extends ConsumerWidget {
  const MemberActions({required this.member, super.key});

  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final disabled = member.disabled ?? false;
    return PopupMenuButton<_MemberAction>(
      icon: const Icon(HiwiskiSymbols.moreVert),
      tooltip: l.familyMemberActions(member.displayName),
      onSelected: (action) => _run(context, ref, action),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _MemberAction.resetPassword,
          child: Text(l.familyResetPassword),
        ),
        if (!disabled)
          PopupMenuItem(
            value: _MemberAction.signOutDevices,
            child: Text(l.familySignOutDevices),
          ),
        PopupMenuItem(
          value: disabled ? _MemberAction.enable : _MemberAction.disable,
          child: Text(disabled ? l.familyEnable : l.familyDisable),
        ),
      ],
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    _MemberAction action,
  ) async {
    final l = L.of(context);
    final name = member.displayName;
    switch (action) {
      case .resetPassword:
        await showPasswordResetSheet(context, member);
      case .signOutDevices:
        await _confirmed(
          context,
          title: l.familySignOutDevicesConfirm(name),
          body: l.familySignOutDevicesBody(name),
          action: l.familySignOutDevices,
          run: () =>
              ref.read(familyViewModelProvider.notifier).signOutDevices(member),
          done: l.familySignedOutDevices(name),
        );
      case .disable:
        await _confirmed(
          context,
          title: l.familyDisableConfirm(name),
          body: l.familyDisableBody(name),
          action: l.familyDisable,
          run: () => ref
              .read(familyViewModelProvider.notifier)
              .setDisabled(member, disabled: true),
        );
      case .enable:
        try {
          await ref
              .read(familyViewModelProvider.notifier)
              .setDisabled(member, disabled: false);
        } on HiwiskiFailure catch (failure) {
          if (!context.mounted) return;
          _show(context, failureText(context, failure));
        }
    }
  }

  /// Asks first, naming what happens; then runs it and says how it ended.
  Future<void> _confirmed(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
    required AsyncCallback run,
    String? done,
  }) async {
    final l = L.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;
    try {
      await run();
      if (done != null && context.mounted) _show(context, done);
    } on HiwiskiFailure catch (failure) {
      if (!context.mounted) return;
      _show(context, failureText(context, failure));
    }
  }

  void _show(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
