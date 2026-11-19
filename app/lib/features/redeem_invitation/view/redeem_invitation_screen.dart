import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/generated/export.dart';
import '../../../core/api/hiwiski_failure.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/cleartext_warning.dart';
import '../../../core/ui/auth_scaffold.dart';
import '../../../core/ui/failure_text.dart';
import '../../../core/ui/notice_bar.dart';
import '../../../core/ui/password_field.dart';
import '../redeem_invitation_view_model.dart';
import 'redeem_invitation_keys.dart';

final _notCodeCharacter = RegExp(r'[^A-Za-z0-9]');

/// What may be typed into the code: its characters and the dash it is printed with.
final _typedCodeCharacter = RegExp('[A-Za-z0-9-]');

/// Join a family.
///
/// The **preview card** is not decoration: without it nobody knows what they are
/// joining.
class RedeemInvitationScreen extends ConsumerStatefulWidget {
  const RedeemInvitationScreen({super.key, this.initialCode});

  /// From the deep link `hiwiski://invite?host=…&code=…`.
  final String? initialCode;

  @override
  ConsumerState<RedeemInvitationScreen> createState() =>
      _RedeemInvitationScreenState();
}

class _RedeemInvitationScreenState
    extends ConsumerState<RedeemInvitationScreen> {
  final _code = TextEditingController();
  final _displayName = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordRepeat = TextEditingController();

  /// The code the preview is for — set as soon as the code is valid: seven
  /// characters. A preview is only ever for this code: it used to stay up while the
  /// code changed — one character typed over, or an eighth — and an answer for an
  /// older code was shown for a newer one, while Join redeemed whatever stood in the
  /// field.
  String? _lookedUp;
  bool _busy = false;
  String? _error;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    if (widget.initialCode case final code?) {
      _code.text = code;
      _lookedUp = _validCode;
    }
    _code.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    _code
      ..removeListener(_onCodeChanged)
      ..dispose();
    _displayName.dispose();
    _username.dispose();
    _password.dispose();
    _passwordRepeat.dispose();
    super.dispose();
  }

  String get _normalized =>
      _code.text.replaceAll(_notCodeCharacter, '').toUpperCase();

  /// **As soon as the code is valid**, the preview appears — without anyone having to
  /// press a button. Seven characters are the signal.
  String? get _validCode => _normalized.length == 7 ? _normalized : null;

  void _onCodeChanged() {
    final code = _validCode;
    if (code == _lookedUp) return;
    setState(() {
      _lookedUp = code;
      _error = null;
    });
  }

  Future<void> _join() async {
    // Enter twice redeemed twice: the second found the code used up and showed an
    // error although joining had worked.
    if (_busy) return;
    // Only the code that was previewed — the family the person saw is the one they
    // join.
    final code = _lookedUp;
    if (code == null ||
        ref.read(invitationPreviewViewModelProvider(code)).value == null) {
      return;
    }
    final l = L.of(context);
    if (_password.text.length < 8) {
      setState(() => _passwordError = l.passwordTooShort);
      return;
    }
    if (_password.text != _passwordRepeat.text) {
      setState(() => _passwordError = l.passwordMismatch);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _passwordError = null;
    });
    try {
      await ref
          .read(redeemInvitationViewModelProvider.notifier)
          .join(
            code,
            (device) => RedeemInvitationRequest(
              displayName: _displayName.text.trim(),
              username: _username.text.trim(),
              password: _password.text,
              device: device,
            ),
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
    final lookedUp = _lookedUp;
    final (lookingUp, previewError, preview) = switch (lookedUp) {
      null => (false, null, null),
      final code =>
        ref
            .watch(invitationPreviewViewModelProvider(code))
            .when(
              skipLoadingOnReload: true,
              loading: () => (true, null, null),
              error: (error, _) => (
                false,
                failureText(context, HiwiskiFailure.from(error)),
                null,
              ),
              data: (preview) => (false, null, preview),
            ),
    };
    if (lookedUp != null) {
      ref.listen(invitationPreviewViewModelProvider(lookedUp), (_, next) {
        if (next.value?.displayName case final name?
            when _displayName.text.isEmpty) {
          _displayName.text = name;
        }
      });
    }

    final state = ref.watch(redeemInvitationViewModelProvider);
    final cleartext = state.cleartext;

    return AuthScaffold(
      loading: _busy || lookingUp,
      title: l.inviteRedeemTitle,
      onBack: () => const LoginRoute().go(context),
      notice: switch (_error ?? previewError) {
        null => null,
        final error => NoticeBar.error(context, text: error),
      },
      children: [
        // Where the code, the name and the password go: the same address the
        // question before switching shows (R11).
        if (state.serverDisplay case final host?) ...[
          Text(
            l.inviteRedeemServer(host),
            key: RedeemInvitationKeys.server,
            textAlign: .center,
            style: context.texts.bodySmall?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: HiwiskiMetrics.space16),
        ],
        // No QR frame here: the phone's own camera reads the invitation's QR code and
        // opens its link, which brings server and code along (lib/app/invite_links.dart).
        // The label as wide as it is, the lines share the rest: as a third of the row,
        // "Einladungscode" broke in the middle of the word on a narrow phone. At most
        // the row less a stub of each line, so that very large text wraps between its
        // words instead of running out of the row.
        LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Expanded(child: Divider(color: context.scheme.outlineVariant)),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth - 2 * HiwiskiMetrics.space24,
                ),
                child: Padding(
                  padding: const .symmetric(horizontal: HiwiskiMetrics.space12),
                  child: Text(
                    l.inviteCodeLabel,
                    textAlign: .center,
                    style: context.texts.bodySmall?.copyWith(
                      color: context.scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              Expanded(child: Divider(color: context.scheme.outlineVariant)),
            ],
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space16),
        // Seven boxes in mono. Underneath sits an ordinary
        // text field — keyboard, paste and screen readers work as everywhere else.
        ListenableBuilder(
          listenable: _code,
          builder: (context, _) =>
              _CodeBoxes(controller: _code, normalized: _normalized),
        ),
        if (preview != null) ...[
          const SizedBox(height: HiwiskiMetrics.space20),
          _PreviewCard(preview: preview),
          // Before the password is typed: it goes out with the redemption.
          if (cleartext) ...[
            const SizedBox(height: HiwiskiMetrics.space12),
            const CleartextWarning(),
          ],
          const SizedBox(height: HiwiskiMetrics.space24),
          TextField(
            controller: _displayName,
            textInputAction: .next,
            decoration: InputDecoration(labelText: l.inviteYourName),
          ),
          const SizedBox(height: HiwiskiMetrics.space20),
          TextField(
            controller: _username,
            autocorrect: false,
            textInputAction: .next,
            decoration: InputDecoration(labelText: l.setupUsername),
          ),
          const SizedBox(height: HiwiskiMetrics.space20),
          PasswordField(
            controller: _password,
            label: l.setupPassword,
            textInputAction: .next,
          ),
          const SizedBox(height: HiwiskiMetrics.space20),
          PasswordField(
            controller: _passwordRepeat,
            label: l.setupPasswordRepeat,
            errorText: _passwordError,
            onSubmitted: _join,
          ),
          const SizedBox(height: HiwiskiMetrics.space24),
          FilledButton(
            onPressed: _busy ? null : _join,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(
                HiwiskiMetrics.buttonHeightLarge,
              ),
            ),
            child: Text(l.inviteJoin),
          ),
        ],
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});

  final InvitationPreview preview;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;
    final groups = preview.groupNames ?? const <String>[];

    return Container(
      padding: const .all(HiwiskiMetrics.space16),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
      ),
      child: Row(
        crossAxisAlignment: .start,
        spacing: HiwiskiMetrics.space12,
        children: [
          Icon(
            HiwiskiSymbols.familyRestroom,
            color: scheme.onSecondaryContainer,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text(
                  preview.familyName,
                  style: context.texts.titleSmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: HiwiskiMetrics.space4),
                Text(
                  l.inviteInvitedBy(preview.invitedBy),
                  style: context.texts.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                if (groups.isNotEmpty)
                  Text(
                    l.inviteGroups(groups.join(', ')),
                    style: context.texts.bodySmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The boxes for the code: seven characters in mono, 40×52, over an invisible
/// text field.
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({required this.controller, required this.normalized});

  final TextEditingController controller;
  final String normalized;

  static const _length = 7;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          mainAxisAlignment: .center,
          children: [
            for (var i = 0; i < _length; i++)
              Container(
                width: HiwiskiMetrics.codeCellSize.width,
                height: HiwiskiMetrics.codeCellSize.height,
                margin: const .symmetric(horizontal: HiwiskiMetrics.space2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: .fromBorderSide(
                    BorderSide(
                      color: i == normalized.length
                          ? scheme.primary
                          : scheme.outline,
                      width: i == normalized.length
                          ? HiwiskiMetrics.strokeBold
                          : HiwiskiMetrics.hairline,
                    ),
                  ),
                  borderRadius: const .all(
                    .circular(HiwiskiMetrics.radiusChip),
                  ),
                ),
                child: Text(
                  i < normalized.length ? normalized[i] : '',
                  style: context.tokens.text.inviteCode.copyWith(
                    letterSpacing: 0,
                  ),
                ),
              ),
          ],
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              showCursor: false,
              textCapitalization: .characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(_typedCodeCharacter),
                LengthLimitingTextInputFormatter(8),
              ],
              decoration: const InputDecoration(border: .none),
            ),
          ),
        ),
      ],
    );
  }
}
