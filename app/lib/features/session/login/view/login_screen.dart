import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../components/legal/view/legal_footer.dart';
import '../../../../core/api/hiwiski_failure.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/auth_scaffold.dart';
import '../../../../core/ui/failure_text.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../core/ui/password_field.dart';
import '../../../../core/ui/hiwiski_mark.dart';
import '../../../../domain/common/server_address.dart';
import '../../../../core/ui/cleartext_warning.dart';
import '../../view/session_keys.dart';
import '../login_view_model.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _staySignedIn = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Locked: whoever signs in again as the same member keeps the data.
    final locked = ref.read(loginViewModelProvider).session;
    if (locked.stage == .accessLost) {
      _username.text = locked.member?.username ?? '';
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Enter is not the disabled button: a second one sent a second request.
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(loginViewModelProvider.notifier)
          .signIn(
            _username.text.trim(),
            _password.text,
            staySignedIn: _staySignedIn,
          );
    } on HiwiskiFailure catch (failure) {
      if (mounted) setState(() => _error = failureText(context, failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final state = ref.watch(loginViewModelProvider);
    final session = state.session;
    final address = session.serverAddress;

    final locked = session.stage == .accessLost;
    return AuthScaffold(
      loading: _busy,
      // Back to the lock screen — signing in is one way out of it, not the only one.
      // On the way from no server to one, back to using the app without one.
      onBack: switch ((locked, state.fromLocal)) {
        (true, _) => () => const AccessLostRoute().go(context),
        (_, true) =>
          () => ref.read(loginViewModelProvider.notifier).backToLocal(),
        _ => null,
      },
      notice: switch ((_error, locked, state.fromLocal)) {
        (final error?, _, _) => NoticeBar.error(context, text: error),
        (null, true, _) => NoticeBar(
          icon: HiwiskiSymbols.lock,
          text: switch (session.member?.displayName) {
            final name? => l.loginKeepData(name),
            null => l.loginKeepDataUnnamed,
          },
        ),
        // Said before signing in, not discovered after: the device's data goes into
        // the account.
        (null, _, true) => NoticeBar(
          icon: HiwiskiSymbols.cloudUpload,
          text: l.localMoveSignIn,
        ),
        _ => null,
      },
      children: [
        const HiwiskiMark(),
        const SizedBox(height: HiwiskiMetrics.space14),
        Text(l.loginWelcome, style: context.texts.headlineLarge),
        const SizedBox(height: HiwiskiMetrics.space24),

        // The server row as a card: whoever knows several instances has to see which
        // one they are signing in to right now.
        // Not in the browser: there the server is the page itself (local_settings.dart).
        if (!kIsWeb)
          _ServerRow(
            address: address == null
                ? l.serverHint
                : (ServerAddress.parse(address)?.display ?? address),
            onChange: () => const ServerAddressRoute().go(context),
          ),
        if (session.isCleartext) ...[
          const SizedBox(height: HiwiskiMetrics.space12),
          const CleartextWarning(),
        ],

        const SizedBox(height: HiwiskiMetrics.space24),
        TextField(
          key: SessionKeys.loginUsername,
          controller: _username,
          autofocus: true,
          autocorrect: false,
          textInputAction: .next,
          decoration: InputDecoration(labelText: l.loginUsername),
        ),
        const SizedBox(height: HiwiskiMetrics.space20),
        PasswordField(
          controller: _password,
          label: l.loginPassword,
          onSubmitted: _submit,
        ),
        const SizedBox(height: HiwiskiMetrics.space8),
        CheckboxListTile(
          value: _staySignedIn,
          onChanged: (value) => setState(() => _staySignedIn = value ?? true),
          title: Text(l.loginStaySignedIn),
          controlAffinity: .leading,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: HiwiskiMetrics.space12),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(
              HiwiskiMetrics.buttonHeightLarge,
            ),
          ),
          child: Text(l.loginSubmit),
        ),
        const SizedBox(height: HiwiskiMetrics.space28),
        Text(
          l.loginNewHere,
          textAlign: .center,
          style: context.texts.bodyMedium?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space8),
        Center(
          child: OutlinedButton.icon(
            onPressed: () => const RedeemInvitationRoute().go(context),
            icon: const Icon(HiwiskiSymbols.qrCode2),
            label: Text(l.loginRedeem),
          ),
        ),
        const LegalFooter(),
      ],
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({required this.address, required this.onChange});

  final String address;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;
    return Container(
      padding: const .symmetric(
        horizontal: HiwiskiMetrics.space14,
        vertical: HiwiskiMetrics.space12,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
      ),
      child: Row(
        children: [
          Icon(
            HiwiskiSymbols.dns,
            size: HiwiskiMetrics.icon22,
            color: scheme.primary,
          ),
          const SizedBox(width: HiwiskiMetrics.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text(
                  l.serverLabel,
                  style: context.texts.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(address, style: context.texts.bodyLarge),
              ],
            ),
          ),
          TextButton(onPressed: onChange, child: Text(l.serverChange)),
        ],
      ),
    );
  }
}
