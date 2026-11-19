import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/hiwiski_failure.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/ui/failure_text.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../core/ui/password_field.dart';
import '../../../../core/ui/hiwiski_sheet.dart';
import '../my_account_view_model.dart';

/// "Change password" in the account — the voluntary change.
///
/// The forced one after a reset is a screen of its own that nobody gets out of
/// (`PasswordChangeScreen`); this one is a sheet that can be closed. Same fields, same
/// rules: the current password, then the new one twice, at least eight characters.
Future<void> showChangePasswordSheet(BuildContext context) async {
  final changed = await showHiwiskiSheet<bool>(
    context: context,
    title: L.of(context).accountChangePassword,
    builder: (context) => const _ChangePasswordBody(),
  );
  if ((changed ?? false) && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L.of(context).accountPasswordChanged)),
    );
  }
}

class _ChangePasswordBody extends ConsumerStatefulWidget {
  const _ChangePasswordBody();

  @override
  ConsumerState<_ChangePasswordBody> createState() =>
      _ChangePasswordBodyState();
}

class _ChangePasswordBodyState extends ConsumerState<_ChangePasswordBody> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _repeatError;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Enter in the last field skipped the disabled button: a second one sent the old
    // password again, which had just changed.
    if (_busy) return;
    final l = L.of(context);
    if (_next.text.length < 8) {
      setState(() => _repeatError = l.passwordTooShort);
      return;
    }
    if (_next.text != _repeat.text) {
      setState(() => _repeatError = l.passwordMismatch);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _repeatError = null;
    });
    try {
      await ref
          .read(myAccountViewModelProvider.notifier)
          .changePassword(_current.text, _next.text);
      if (mounted) Navigator.of(context).pop(true);
    } on HiwiskiFailure catch (failure) {
      if (mounted) setState(() => _error = failureText(context, failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: [
        if (_error case final error?) ...[
          NoticeBar.error(context, text: error),
          const SizedBox(height: HiwiskiMetrics.space16),
        ],
        PasswordField(
          controller: _current,
          label: l.passwordCurrent,
          autofocus: true,
          textInputAction: .next,
        ),
        const SizedBox(height: HiwiskiMetrics.space16),
        PasswordField(
          controller: _next,
          label: l.passwordNew,
          textInputAction: .next,
        ),
        const SizedBox(height: HiwiskiMetrics.space16),
        PasswordField(
          controller: _repeat,
          label: l.passwordRepeat,
          errorText: _repeatError,
          onSubmitted: _submit,
        ),
        SheetActions(
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: Text(l.actionCancel),
            ),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(l.passwordApply),
            ),
          ],
        ),
      ],
    );
  }
}
