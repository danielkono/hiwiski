import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/experimental/mutation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/api/generated/export.dart' hide Mutation;
import '../../../core/api/hiwiski_failure.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/failure_text.dart';
import '../../../core/ui/hiwiski_sheet.dart';
import '../family_view_model.dart';
import 'group_names.dart';

/// "New member" — **sheet on the phone, dialog on the desktop, one component**.
///
/// Two states: form and result. The result carries the QR code with the
/// deep link `hiwiski://invite?host=…&code=…` and the code in mono — it gets
/// copied down by hand.
///
/// [groupIds] are ticked up front — "invite a new person and add them right away"
/// from a group.
Future<void> showInviteSheet(
  BuildContext context, {
  Set<String> groupIds = const {},
}) {
  return showHiwiskiSheet<void>(
    context: context,
    title: L.of(context).inviteCreateTitle,
    builder: (context) => _InviteBody(groupIds: groupIds),
  );
}

class _InviteBody extends ConsumerStatefulWidget {
  const _InviteBody({required this.groupIds});

  final Set<String> groupIds;

  @override
  ConsumerState<_InviteBody> createState() => _InviteBodyState();
}

class _InviteBodyState extends ConsumerState<_InviteBody> {
  final _displayName = TextEditingController();
  InvitationValidity _validity = .hours24;
  late final _groupIds = <String>{...widget.groupIds};

  @override
  void dispose() {
    _displayName.dispose();
    super.dispose();
  }

  void _create() =>
      // The mutation's state holds the outcome; build shows it.
      inviteMutation
          .run(
            ref,
            (tsx) => tsx
                .get(familyViewModelProvider.notifier)
                .invite(
                  CreateInvitationRequest(
                    displayName: _displayName.text.trim().isEmpty
                        ? null
                        : _displayName.text.trim(),
                    groupIds: _groupIds.toList(),
                    validity: _validity,
                  ),
                ),
          )
          .ignore();

  @override
  Widget build(BuildContext context) {
    final inviting = ref.watch(inviteMutation);
    if (inviting case MutationSuccess(value: final created)) {
      return _InviteResult(invitation: created, validity: _validity);
    }
    final error = switch (inviting) {
      MutationError(:final error) => failureText(
        context,
        HiwiskiFailure.from(error),
      ),
      _ => null,
    };
    final l = L.of(context);
    final groups =
        ref.watch(familyViewModelProvider).value?.groups ?? const <Group>[];

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        if (error != null) ...[
          Text(error, style: TextStyle(color: context.scheme.error)),
          const SizedBox(height: HiwiskiMetrics.space12),
        ],
        TextField(
          controller: _displayName,
          decoration: InputDecoration(labelText: l.inviteCreateName),
        ),
        const SizedBox(height: HiwiskiMetrics.space20),
        Text(l.familyGroups, style: context.tokens.text.sectionLabel),
        const SizedBox(height: HiwiskiMetrics.space8),
        Wrap(
          spacing: HiwiskiMetrics.space8,
          runSpacing: HiwiskiMetrics.space8,
          children: [
            for (final group in groups)
              FilterChip(
                label: Text(group.name),
                selected: _groupIds.contains(group.id),
                onSelected: (selected) => setState(
                  () => selected
                      ? _groupIds.add(group.id)
                      : _groupIds.remove(group.id),
                ),
              ),
          ],
        ),
        const SizedBox(height: HiwiskiMetrics.space20),
        Text(l.inviteCreateValidity, style: context.tokens.text.sectionLabel),
        const SizedBox(height: HiwiskiMetrics.space8),
        Wrap(
          spacing: HiwiskiMetrics.space6,
          runSpacing: HiwiskiMetrics.space6,
          children: [
            for (final (value, label) in [
              (InvitationValidity.hour1, l.inviteValidity1Hour),
              (InvitationValidity.hours24, l.inviteValidity24Hours),
              (InvitationValidity.days7, l.inviteValidity7Days),
            ])
              FilterChip(
                label: Text(label),
                selected: _validity == value,
                onSelected: (_) => setState(() => _validity = value),
              ),
          ],
        ),
        SheetActions(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.actionCancel),
            ),
            FilledButton.icon(
              onPressed: inviting.isPending ? null : _create,
              icon: const Icon(
                HiwiskiSymbols.qrCode2,
                size: HiwiskiMetrics.icon18,
              ),
              label: Text(l.inviteCreateSubmit),
            ),
          ],
        ),
      ],
    );
  }
}

/// The invitation once created: its QR code, the code, and what it says.
class _InviteResult extends ConsumerWidget {
  const _InviteResult({required this.invitation, required this.validity});

  final Invitation invitation;
  final InvitationValidity validity;

  /// Only the answer to the creation carries the code and its link: the server keeps
  /// just a hash of it, so this sheet is the one time it is shown.
  String get _code => invitation.code ?? '';

  String get _deepLink => invitation.deepLink ?? '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final scheme = context.scheme;
    final groups =
        ref.watch(familyViewModelProvider).value?.groups ?? const <Group>[];

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(l.inviteResultLead, style: context.texts.bodyMedium),
        const SizedBox(height: HiwiskiMetrics.space20),
        Center(
          child: Container(
            padding: const .all(HiwiskiMetrics.space12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
            ),
            child: QrImageView(
              // The QR carries the deep link, not just the code: a scan should open the app
              // and bring the code along. The `hiwiski://` scheme has to be registered in
              // every platform project -- exactly that was missing in an earlier version.
              data: _deepLink,
              size: HiwiskiMetrics.qrCode,
              backgroundColor: scheme.surfaceContainerLowest,
              eyeStyle: QrEyeStyle(eyeShape: .square, color: scheme.onSurface),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: .square,
                color: scheme.onSurface,
              ),
            ),
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space16),
        Center(
          child: SelectableText(_code, style: context.tokens.text.inviteCode),
        ),
        const SizedBox(height: HiwiskiMetrics.space16),
        // The summary: For / Groups / Valid.
        _SummaryLine(label: l.inviteFor, value: invitation.displayName ?? '—'),
        _SummaryLine(
          label: l.familyGroups,
          value: _groupNames(groups, invitation.groupIds ?? const []),
        ),
        _SummaryLine(
          label: l.inviteValid,
          value: switch (validity) {
            .hour1 => l.inviteValidity1Hour,
            .days7 => l.inviteValidity7Days,
            _ => l.inviteValidity24Hours,
          },
        ),
        SheetActions(
          children: [
            TextButton.icon(
              icon: const Icon(
                HiwiskiSymbols.contentCopy,
                size: HiwiskiMetrics.icon18,
              ),
              label: Text(l.inviteCopyCode),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _code));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(l.actionCopied)));
              },
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.actionDone),
            ),
          ],
        ),
      ],
    );
  }
}

String _groupNames(List<Group> groups, List<String> ids) {
  final names = groupNamesOf(groups, ids);
  return names.isEmpty ? '—' : names.join(', ');
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .symmetric(vertical: HiwiskiMetrics.space4),
    child: Row(
      crossAxisAlignment: .start,
      children: [
        SizedBox(
          width: HiwiskiMetrics.labelColumnWidth,
          child: Text(
            label,
            style: context.texts.bodyMedium?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value, style: context.texts.bodyMedium)),
      ],
    ),
  );
}

/// "Reset password" — a sheet generates a temporary password, shows it
/// **once**, large in mono with "Copy", and says that the user has to choose their own
/// at the next sign-in. After that it cannot be retrieved again.
Future<void> showPasswordResetSheet(BuildContext context, Member member) {
  return showHiwiskiSheet<void>(
    context: context,
    title: L.of(context).familyResetPassword,
    builder: (context) => _PasswordResetBody(member: member),
  );
}

class _PasswordResetBody extends ConsumerWidget {
  const _PasswordResetBody({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void reset() =>
        // The mutation's state holds the outcome; build shows it.
        resetPasswordMutation
            .run(
              ref,
              (tsx) => tsx
                  .get(familyViewModelProvider.notifier)
                  .resetPassword(member),
            )
            .ignore();

    final l = L.of(context);
    final resetting = ref.watch(resetPasswordMutation);
    final temporary = switch (resetting) {
      MutationSuccess(:final value) => value.temporaryPassword,
      _ => null,
    };

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        if (resetting case MutationError(:final error)) ...[
          Text(
            failureText(context, HiwiskiFailure.from(error)),
            style: TextStyle(color: context.scheme.error),
          ),
          const SizedBox(height: HiwiskiMetrics.space12),
        ],
        Text(
          l.familyResetPasswordLead(member.displayName),
          style: context.texts.bodyMedium,
        ),
        const SizedBox(height: HiwiskiMetrics.space20),
        if (temporary == null)
          FilledButton(
            onPressed: resetting.isPending ? null : reset,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(HiwiskiMetrics.buttonHeight),
            ),
            child: Text(l.familyResetPassword),
          )
        else ...[
          Center(
            child: SelectableText(
              temporary,
              style: context.tokens.text.inviteCode,
            ),
          ),
          const SizedBox(height: HiwiskiMetrics.space16),
          OutlinedButton.icon(
            icon: const Icon(HiwiskiSymbols.contentCopy),
            label: Text(l.actionCopy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: temporary));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(l.actionCopied)));
            },
          ),
          const SizedBox(height: HiwiskiMetrics.space12),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(HiwiskiMetrics.buttonHeight),
            ),
            child: Text(l.actionDone),
          ),
        ],
      ],
    );
  }
}
