import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../components/member_avatar/view/member_avatar.dart';
import '../../../../core/api/hiwiski_failure.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/shell/breakpoints.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/failure_text.dart';
import '../../../../core/ui/page_header.dart';
import '../../../../components/rich_text/view/image_files.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../view/account_keys.dart';
import '../my_account_view_model.dart';
import 'change_password_sheet.dart';

/// "My account" — what a member changes about themselves: the picture, the name the
/// family sees, the password. The username stays: it is in mentions and log lines.
class MyAccountScreen extends ConsumerStatefulWidget {
  const MyAccountScreen({super.key});

  @override
  ConsumerState<MyAccountScreen> createState() => _MyAccountScreenState();
}

class _MyAccountScreenState extends ConsumerState<MyAccountScreen> {
  late final _name = TextEditingController(
    text: ref.read(myAccountViewModelProvider).member?.displayName ?? '',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Runs a change, shows a failure in place — and lets the member list catch up, so
  /// chips and comments show the new name and picture.
  Future<void> _run(AsyncCallback change, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await change();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on HiwiskiFailure catch (failure) {
      if (mounted) setState(() => _error = failureText(context, failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPicture() async {
    final l = L.of(context);
    final file = (await pickImageFiles(single: true)).firstOrNull;
    if (file == null || !mounted) return;
    await _run(
      () => ref
          .read(myAccountViewModelProvider.notifier)
          .setPicture(file.bytes, file.filename),
      l.myAccountPictureSaved,
    );
  }

  Future<void> _saveName() async {
    final l = L.of(context);
    final name = _name.text.trim();
    // Enter goes past the button's conditions: not while saving, not unchanged.
    final current = ref.read(myAccountViewModelProvider).member?.displayName;
    if (_busy || name == (current ?? '')) return;
    if (name.isEmpty) {
      setState(() => _error = l.validationRequired);
      return;
    }
    await _run(
      () => ref.read(myAccountViewModelProvider.notifier).setName(name),
      l.myAccountNameSaved,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final state = ref.watch(myAccountViewModelProvider);
    final member = state.member;
    final padding = Breakpoint.of(context).pagePadding;

    return HiwiskiPage(
      header: PageHeader(
        title: l.myAccountTitle,
        onBack: () => const AccountRoute().go(context),
      ),
      body: Column(
        crossAxisAlignment: .stretch,
        children: [
          if (_busy)
            const LinearProgressIndicator(
              minHeight: HiwiskiMetrics.progressStripHeight,
            ),
          Expanded(
            child: ListView(
              padding: padding,
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: HiwiskiMetrics.listMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        if (member != null)
                          Row(
                            children: [
                              MemberAvatar.of(
                                member,
                                radius: HiwiskiMetrics.avatarProfile,
                              ),
                              const SizedBox(width: HiwiskiMetrics.space16),
                              Expanded(
                                child: Wrap(
                                  spacing: HiwiskiMetrics.space8,
                                  runSpacing: HiwiskiMetrics.space8,
                                  children: [
                                    FilledButton.tonalIcon(
                                      key: AccountKeys.avatarPick,
                                      icon: const Icon(
                                        HiwiskiSymbols.addPhotoAlternate,
                                        size: HiwiskiMetrics.icon18,
                                      ),
                                      label: Text(
                                        member.avatarImageId == null
                                            ? l.myAccountPictureSet
                                            : l.myAccountPictureChange,
                                      ),
                                      onPressed: _busy ? null : _pickPicture,
                                    ),
                                    if (member.avatarImageId != null)
                                      TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _run(
                                                () => ref
                                                    .read(
                                                      myAccountViewModelProvider
                                                          .notifier,
                                                    )
                                                    .removePicture(),
                                                l.myAccountPictureRemoved,
                                              ),
                                        child: Text(l.myAccountPictureRemove),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: HiwiskiMetrics.space24),
                        Text(
                          l.myAccountName,
                          style: context.tokens.text.sectionLabel,
                        ),
                        const SizedBox(height: HiwiskiMetrics.space8),
                        Row(
                          crossAxisAlignment: .start,
                          children: [
                            Expanded(
                              child: TextField(
                                key: AccountKeys.displayName,
                                controller: _name,
                                decoration: InputDecoration(
                                  labelText: l.myAccountDisplayName,
                                  helperText: member == null || state.local
                                      ? null
                                      : l.myAccountUsername(member.username),
                                ),
                                onSubmitted: (_) => _saveName(),
                              ),
                            ),
                            const SizedBox(width: HiwiskiMetrics.space8),
                            Padding(
                              padding: const .only(top: HiwiskiMetrics.space8),
                              // Follows the field: unchanged, there is nothing
                              // to save.
                              child: ListenableBuilder(
                                listenable: _name,
                                builder: (context, _) => FilledButton(
                                  onPressed:
                                      _busy ||
                                          _name.text.trim() ==
                                              (member?.displayName ?? '')
                                      ? null
                                      : _saveName,
                                  child: Text(l.actionSave),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_error case final message?)
                          Padding(
                            padding: const .only(top: HiwiskiMetrics.space8),
                            child: Text(
                              message,
                              style: context.texts.bodySmall?.copyWith(
                                color: context.scheme.error,
                              ),
                            ),
                          ),
                        // A password exists only on a server.
                        if (!state.local) ...[
                          const SizedBox(height: HiwiskiMetrics.space24),
                          Text(
                            l.myAccountSecurity,
                            style: context.tokens.text.sectionLabel,
                          ),
                          const SizedBox(height: HiwiskiMetrics.space8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              icon: const Icon(
                                HiwiskiSymbols.lock,
                                size: HiwiskiMetrics.icon18,
                              ),
                              label: Text(l.accountChangePassword),
                              onPressed: () => showChangePasswordSheet(context),
                            ),
                          ),
                        ],
                        const SizedBox(height: HiwiskiMetrics.space32),
                      ],
                    ),
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
