import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/auth_scaffold.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../core/ui/hiwiski_mark.dart';
import '../../view/session_keys.dart';
import '../access_lost_view_model.dart';

/// The lock screen: this device lost its access — it
/// was signed out on another device, or its session ended. Its data is still here,
/// locked, not deleted. Signing in again as the same member opens it with nothing
/// lost; the changes not yet synced are named, since they are lost otherwise.
class AccessLostScreen extends ConsumerWidget {
  const AccessLostScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final state = ref.watch(accessLostViewModelProvider).value;
    final pending = state?.pending ?? 0;
    final name = state?.member?.displayName;

    return AuthScaffold(
      loading: ref.watch(discardDataMutation).isPending,
      children: [
        const HiwiskiMark(),
        const SizedBox(height: HiwiskiMetrics.space14),
        Text(l.accessLostTitle, style: context.texts.headlineLarge),
        const SizedBox(height: HiwiskiMetrics.space12),
        Text(
          name == null ? l.accessLostBody : l.accessLostBodyNamed(name),
          style: context.texts.bodyLarge,
        ),
        if (pending > 0) ...[
          const SizedBox(height: HiwiskiMetrics.space16),
          NoticeBar(
            icon: HiwiskiSymbols.cloudOff,
            text: l.accessLostPending(pending),
            background: context.scheme.errorContainer,
            foreground: context.scheme.onErrorContainer,
          ),
        ],
        const SizedBox(height: HiwiskiMetrics.space24),
        FilledButton(
          key: SessionKeys.signInAgain,
          onPressed: () => const LoginRoute().go(context),
          child: Text(l.accessLostSignIn),
        ),
        const SizedBox(height: HiwiskiMetrics.space8),
        TextButton(
          key: SessionKeys.discardData,
          style: TextButton.styleFrom(foregroundColor: context.scheme.error),
          onPressed: () => _confirmDiscard(context, ref, pending),
          child: Text(l.accessLostDiscard),
        ),
      ],
    );
  }

  /// Deleting asks first — and names what is lost.
  static Future<void> _confirmDiscard(
    BuildContext context,
    WidgetRef ref,
    int pending,
  ) async {
    final l = L.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.accessLostDiscardTitle),
        content: Text(
          pending > 0
              ? l.accessLostDiscardPending(pending)
              : l.accessLostDiscardBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            key: SessionKeys.discardConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: context.scheme.error,
              foregroundColor: context.scheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.accessLostDiscard),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;
    await discardDataMutation.run(
      ref,
      (tsx) => tsx.get(accessLostViewModelProvider.notifier).discard(),
    );
  }
}
