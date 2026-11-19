import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/hiwiski_failure.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/auth_scaffold.dart';
import '../../../../core/ui/failure_text.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../core/ui/password_field.dart';
import '../../../../core/ui/hiwiski_mark.dart';
import '../password_change_view_model.dart';

/// **Not a screen you open, but one you get stuck on**.
///
/// If the administrator reset the password, sign-in leads here and
/// nowhere else: no cancel, no back, no navigation. The server enforces the
/// same — otherwise a second device would be enough.
class PasswordChangeScreen extends ConsumerStatefulWidget {
  const PasswordChangeScreen({super.key});

  @override
  ConsumerState<PasswordChangeScreen> createState() =>
      _PasswordChangeScreenState();
}

class _PasswordChangeScreenState extends ConsumerState<PasswordChangeScreen> {
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
    // Enter is not the disabled button: a second one sent a second request.
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
          .read(passwordChangeViewModelProvider.notifier)
          .change(_current.text, _next.text);
    } on HiwiskiFailure catch (failure) {
      if (mounted) setState(() => _error = failureText(context, failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    // No back, not even via the system gesture.
    return PopScope(
      canPop: false,
      child: AuthScaffold(
        loading: _busy,
        notice: switch (_error) {
          null => null,
          final error => NoticeBar.error(context, text: error),
        },
        children: [
          const HiwiskiMark(),
          const SizedBox(height: HiwiskiMetrics.space14),
          Text(l.passwordChangeTitle, style: context.texts.headlineLarge),
          const SizedBox(height: HiwiskiMetrics.space6),
          Text(
            l.passwordChangeLead,
            style: context.texts.bodyMedium?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: HiwiskiMetrics.space24),
          PasswordField(
            controller: _current,
            label: l.passwordCurrent,
            autofocus: true,
            textInputAction: .next,
          ),
          const SizedBox(height: HiwiskiMetrics.space20),
          PasswordField(
            controller: _next,
            label: l.passwordNew,
            textInputAction: .next,
          ),
          const SizedBox(height: HiwiskiMetrics.space20),
          PasswordField(
            controller: _repeat,
            label: l.passwordRepeat,
            errorText: _repeatError,
            onSubmitted: _submit,
          ),
          const SizedBox(height: HiwiskiMetrics.space24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(
                HiwiskiMetrics.buttonHeightLarge,
              ),
            ),
            child: Text(l.passwordApply),
          ),
        ],
      ),
    );
  }
}
