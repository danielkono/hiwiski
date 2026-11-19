import 'package:flutter/material.dart';
import 'package:flutter_riverpod/experimental/mutation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/generated/export.dart' hide Mutation;
import '../../../../core/api/hiwiski_failure.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/auth_scaffold.dart';
import '../../../../core/ui/failure_text.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../core/ui/hiwiski_mark.dart';
import '../../../../domain/common/server_address.dart';
import '../../../../core/ui/cleartext_warning.dart';
import '../../view/session_keys.dart';
import '../server_address_view_model.dart';

/// **Before everything else**.
///
/// In the browser prefilled with the origin, otherwise empty with an example. After
/// connecting, the family name and server version as confirmation — without them
/// nobody knows whether they reached the right server.
class ServerAddressScreen extends ConsumerStatefulWidget {
  const ServerAddressScreen({super.key});

  @override
  ConsumerState<ServerAddressScreen> createState() =>
      _ServerAddressScreenState();
}

class _ServerAddressScreenState extends ConsumerState<ServerAddressScreen> {
  final _controller = TextEditingController();

  /// What was typed is no address at all — caught before any request.
  bool _malformed = false;

  @override
  void initState() {
    super.initState();
    // In the browser this is already the page's origin — or the HIWISKI_SERVER build
    // override (webServerAddress): whoever opens the web app has reached the server.
    // A copy of that check here read only the origin and ignored the override.
    final known = ref
        .read(serverAddressViewModelProvider)
        .session
        .serverAddress;
    if (known != null) {
      _controller.text = ServerAddress.parse(known)?.display ?? known;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _connect() {
    final address = ServerAddress.parse(_controller.text);
    setState(() => _malformed = address == null);
    if (address == null) return;
    // The mutation's state holds the outcome; build shows it.
    connectMutation
        .run(
          ref,
          (tsx) =>
              tsx.get(serverAddressViewModelProvider.notifier).connect(address),
        )
        .ignore();
  }

  /// "Use without a server": a name, and the app starts on this device alone.
  Future<void> _startLocal() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _LocalNameDialog(),
    );
    if (name == null || !mounted) return;
    await ref.read(serverAddressViewModelProvider.notifier).startLocal(name);
    // The address stays reachable without a server — for connecting later — so the
    // router does not move on by itself.
    if (mounted) const HomeRoute().go(context);
  }

  Future<void> _backToLocal() async {
    await ref.read(serverAddressViewModelProvider.notifier).backToLocal();
    if (mounted) const HomeRoute().go(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final state = ref.watch(serverAddressViewModelProvider);
    final connecting = ref.watch(connectMutation);
    final connected = switch (connecting) {
      MutationSuccess(:final value) => value,
      _ => null,
    };
    final error = switch (connecting) {
      _ when _malformed => l.serverUnreachable,
      MutationError(:final error) => switch (HiwiskiFailure.from(error)) {
        final failure when failure.isNetwork => l.serverUnreachable,
        final failure => failureText(context, failure),
      },
      _ => null,
    };

    return AuthScaffold(
      loading: connecting.isPending,
      onBack: state.fromLocal ? _backToLocal : null,
      notice: switch (error) {
        null => null,
        final error => NoticeBar.error(context, text: error),
      },
      children: [
        const HiwiskiMark(),
        const SizedBox(height: HiwiskiMetrics.space14),
        Text(l.serverTitle, style: context.texts.headlineLarge),
        const SizedBox(height: HiwiskiMetrics.space6),
        Text(
          state.fromLocal ? l.localConnectLead : l.serverLead,
          style: context.texts.bodyMedium?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space24),
        TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: .url,
          autocorrect: false,
          textInputAction: .go,
          onSubmitted: (_) => _connect(),
          decoration: InputDecoration(
            labelText: l.serverField,
            hintText: l.serverHint,
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space20),
        FilledButton(
          onPressed: connecting.isPending ? null : _connect,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(
              HiwiskiMetrics.buttonHeightLarge,
            ),
          ),
          child: Text(l.serverConnect),
        ),
        if (connected != null) ...[
          const SizedBox(height: HiwiskiMetrics.space20),
          _ConnectedCard(handshake: connected),
          const SizedBox(height: HiwiskiMetrics.space20),
          // After connecting, things move on — into the wizard if the instance is
          // new, otherwise to sign-in. Without this button you were stuck here: the
          // server address is reachable while signed out too, and the router does not redirect.
          FilledButton.tonal(
            onPressed: () =>
                ref.read(serverAddressViewModelProvider).session.stage ==
                    .setupRequired
                ? const SetupRoute().go(context)
                : const LoginRoute().go(context),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(
                HiwiskiMetrics.buttonHeightLarge,
              ),
            ),
            child: Text(l.actionContinue),
          ),
        ],
        // The other way in: no server at all — only in the apps, and only before
        // anything else.
        if (state.offerLocal && connected == null) ...[
          const SizedBox(height: HiwiskiMetrics.space28),
          Text(
            l.localStartLead,
            textAlign: .center,
            style: context.texts.bodyMedium?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: HiwiskiMetrics.space8),
          Center(
            child: OutlinedButton.icon(
              key: SessionKeys.startLocal,
              onPressed: connecting.isPending ? null : _startLocal,
              icon: const Icon(HiwiskiSymbols.smartphone),
              label: Text(l.localStart),
            ),
          ),
        ],
      ],
    );
  }
}

/// The name of the member the app makes when it starts without a server.
class _LocalNameDialog extends StatefulWidget {
  const _LocalNameDialog();

  @override
  State<_LocalNameDialog> createState() => _LocalNameDialogState();
}

class _LocalNameDialogState extends State<_LocalNameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return AlertDialog(
      title: Text(l.localNameTitle),
      content: TextField(
        key: SessionKeys.localName,
        controller: _name,
        autofocus: true,
        textCapitalization: .words,
        textInputAction: .done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(labelText: l.localNameField),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        ListenableBuilder(
          listenable: _name,
          builder: (context, _) => FilledButton(
            key: SessionKeys.localStartConfirm,
            onPressed: _name.text.trim().isEmpty ? null : _submit,
            child: Text(l.localStartAction),
          ),
        ),
      ],
    );
  }
}

class _ConnectedCard extends StatelessWidget {
  const _ConnectedCard({required this.handshake});

  final Handshake handshake;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Container(
          padding: const .all(HiwiskiMetrics.space14),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
          ),
          child: Row(
            spacing: HiwiskiMetrics.space12,
            children: [
              Icon(
                HiwiskiSymbols.checkCircle,
                fill: 1,
                color: scheme.onSecondaryContainer,
              ),
              Expanded(
                child: Text(
                  l.serverConnected(
                    handshake.familyName ?? l.appName,
                    handshake.serverVersion,
                  ),
                  style: context.texts.bodyMedium?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Plain-language warning: one sentence on what it means, and that it is acceptable
        // on a home network. Not hidden behind a dismiss.
        if (handshake.cleartext) ...[
          const SizedBox(height: HiwiskiMetrics.space12),
          const CleartextWarning(),
        ],
      ],
    );
  }
}
