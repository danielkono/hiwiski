import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/experimental/mutation.dart';

import '../../../../components/legal/view/legal_footer.dart';
import '../../../../components/member_avatar/view/member_avatar.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/shell/breakpoints.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/theme/theme_modes.dart';
import '../../../../core/api/hiwiski_failure.dart';
import '../../../../core/ui/failure_text.dart';
import '../../../../core/ui/page_header.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../../../domain/common/server_address.dart';
import '../../view/account_keys.dart';
import '../../view/account_row.dart';
import '../../view/account_section_label.dart';
import '../account_view_model.dart';
import 'storage_section.dart';

/// The account.
///
/// **"Sign out" sits at the very bottom, in `error`, with a confirmation.** In an earlier version it
/// sat exactly where the account icon was in the lists — tapping the same spot twice
/// meant signed out. No destructive button in the spot where a harmless one used to be.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = PageHeader(title: L.of(context).accountTitle);
    return ref
        .watch(accountViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(header: header, error: error),
          data: (state) => _AccountPage(header: header, state: state),
        );
  }

  /// Without a server, the way to one: what goes along, and what stays behind, said
  /// before — then the server address.
  static Future<void> _confirmConnect(BuildContext context) async {
    final l = L.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.localConnectTitle),
        content: Text(l.localConnectBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            key: AccountKeys.localConnectConfirm,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.actionContinue),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && context.mounted) {
      const ServerAddressRoute().go(context);
    }
  }

  /// Without a server nothing is kept anywhere else: deleting is for good, and it
  /// says so.
  static Future<void> _confirmDiscard(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l = L.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DangerDialog(
        title: l.localDeleteTitle,
        body: l.localDeleteBody,
        action: l.localDelete,
        confirmKey: AccountKeys.localDeleteConfirm,
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;
    await ref.read(accountViewModelProvider.notifier).discardLocal();
  }

  static Future<void> _confirmResetDemo(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l = L.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DangerDialog(
        title: l.demoResetTitle,
        body: l.demoResetBody,
        action: l.demoReset,
        confirmKey: AccountKeys.demoResetConfirm,
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;
    const HomeRoute().go(context);
    await ref.read(accountViewModelProvider.notifier).resetDemo();
  }

  static Future<void> _confirmSignOut(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final choice = await showDialog<_SignOutChoice>(
      context: context,
      builder: (context) => const _SignOutDialog(),
    );
    if (choice == null || !context.mounted) return;
    // To start first: the router remembers where someone was sent away from to
    // sign in — whoever signs out deliberately starts on start next time. The
    // screen goes with the next frame; the mutation keeps the ViewModel until the
    // sign-out is through.
    const HomeRoute().go(context);
    await signOutMutation.run(
      ref,
      (tsx) => tsx
          .get(accountViewModelProvider.notifier)
          .signOut(synced: choice == .synced),
    );
  }
}

/// How the sign-out was confirmed.
enum _SignOutChoice {
  /// Nothing waited: the sign-out's own last sync has nothing to send.
  signOut,

  /// "Sign out anyway": the dialog tried once more itself, in view.
  synced,
}

/// "Sign out": **first the last sync, then the question** — so it names what is
/// really lost, not what was waiting before the sync. Changes that still could not be
/// synced (offline) must be given up explicitly: the button only works once the
/// member has ticked that they understand.
class _SignOutDialog extends ConsumerStatefulWidget {
  const _SignOutDialog();

  @override
  ConsumerState<_SignOutDialog> createState() => _SignOutDialogState();
}

class _SignOutDialogState extends ConsumerState<_SignOutDialog> {
  bool _acknowledged = false;

  /// "Sign out anyway" was tapped, and the last try runs.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    // After the first frame, not inside it: starting the mutation changes its state,
    // and Riverpod refuses that while the tree is being built — in a debug build the
    // dialog showed a server error at once instead of the sync.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  Future<int> _run() => syncBeforeSignOutMutation.run(
    ref,
    (tsx) => tsx.get(accountViewModelProvider.notifier).syncBeforeSignOut(),
  );

  void _sync() {
    _acknowledged = false;
    // Shown from the mutation's state below; a failure is shown there too.
    _run().ignore();
  }

  /// "Sign out anyway": one more try at the changes still waiting — **in the
  /// dialog, in view.** The sign-out used to make it after the dialog had closed:
  /// offline, the start screen stood there signed in for a connection timeout, and
  /// nothing said why.
  Future<void> _leave() async {
    setState(() => _leaving = true);
    try {
      await _run();
    } on Object catch (error) {
      // Lost all the same: the member has confirmed it.
      debugPrint('hiwiski: last try before sign-out failed: $error');
    }
    if (mounted) Navigator.of(context).pop(_SignOutChoice.synced);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;
    final sync = ref.watch(syncBeforeSignOutMutation);
    final lost = switch (sync) {
      MutationSuccess(:final value) => value,
      _ => null,
    };
    final ready = switch (lost) {
      null => false,
      0 => true,
      _ => _acknowledged,
    };

    return AlertDialog(
      title: Text(l.accountSignOutConfirm),
      content: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          Text(l.accountSignOutBody),
          const SizedBox(height: HiwiskiMetrics.space16),
          switch (sync) {
            _ when _leaving => _Progress(l.accountSignOutRetrying),
            MutationError(:final error) => Text(
              failureText(context, HiwiskiFailure.from(error)),
              style: TextStyle(color: scheme.error),
            ),
            MutationSuccess() when lost == 0 => Row(
              spacing: HiwiskiMetrics.space8,
              children: [
                Icon(HiwiskiSymbols.checkCircle, color: scheme.primary),
                Expanded(child: Text(l.accountSignOutSynced)),
              ],
            ),
            MutationSuccess() => Column(
              crossAxisAlignment: .start,
              children: [
                // What signing out loses is stated beforehand — not afterwards.
                Text(
                  l.accountSignOutLost(lost ?? 0),
                  style: TextStyle(color: scheme.error),
                ),
                CheckboxListTile(
                  key: AccountKeys.signOutAcknowledge,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: .leading,
                  value: _acknowledged,
                  onChanged: (value) =>
                      setState(() => _acknowledged = value ?? false),
                  title: Text(l.accountSignOutAcknowledge),
                ),
              ],
            ),
            _ => _Progress(l.accountSignOutSyncing),
          },
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        if (!_leaving && ((lost ?? 0) > 0 || sync is MutationError<int>))
          TextButton(
            onPressed: () => setState(_sync),
            child: Text(l.actionRetry),
          ),
        FilledButton(
          key: AccountKeys.signOutConfirm,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: switch (lost) {
            _ when !ready || _leaving => null,
            0 => () => Navigator.of(context).pop(_SignOutChoice.signOut),
            _ => _leave,
          },
          child: Text(
            (lost ?? 0) > 0 || _leaving
                ? l.accountSignOutAnyway
                : l.accountSignOut,
          ),
        ),
      ],
    );
  }
}

/// A sync under way in the sign-out dialog, and what it is for.
class _Progress extends StatelessWidget {
  const _Progress(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    spacing: HiwiskiMetrics.space12,
    children: [
      const SizedBox.square(
        dimension: HiwiskiMetrics.icon20,
        child: CircularProgressIndicator(
          strokeWidth: HiwiskiMetrics.strokeBold,
        ),
      ),
      Expanded(child: Text(text)),
    ],
  );
}

class _AccountPage extends ConsumerWidget {
  const _AccountPage({required this.header, required this.state});

  final PageHeader header;
  final AccountState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final member = state.member;
    final padding = Breakpoint.of(context).pagePadding;
    final scheme = context.scheme;
    final myGroups = state.myGroups;
    String? count(int? value) => value?.toString();
    // The operator's legal pages, for an instance open to the public: two taps away,
    // the avatar and the row.
    final legal = state.legal;

    final server = state.serverAddress;
    final serverLabel = server == null
        ? null
        : (ServerAddress.parse(server)?.display ?? server);

    return HiwiskiPage(
      header: header,
      body: ListView(
        children: [
          Padding(
            padding: padding,
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: HiwiskiMetrics.listMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    if (member != null)
                      // Header card on `sf2`, radius 20: avatar 52, name,
                      // "@anna · Administrator · Eltern, Alle".
                      // A tap on one's own card leads to "My account".
                      Material(
                        color: scheme.surfaceContainer,
                        borderRadius: const .all(
                          .circular(HiwiskiMetrics.radiusWidget),
                        ),
                        clipBehavior: .antiAlias,
                        child: InkWell(
                          onTap: () => const MyAccountRoute().go(context),
                          child: Padding(
                            padding: const .all(HiwiskiMetrics.space16),
                            child: Row(
                              spacing: HiwiskiMetrics.space14,
                              children: [
                                MemberAvatar.of(
                                  member,
                                  radius: HiwiskiMetrics.avatarXLarge,
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: .start,
                                    children: [
                                      Text(
                                        member.displayName,
                                        style: context.tokens.text.accountName,
                                      ),
                                      Text(
                                        [
                                          if (state.local)
                                            l.accountLocal
                                          else ...[
                                            '@${member.username}',
                                            if (member.isAdmin) l.accountAdmin,
                                          ],
                                          if (myGroups.isNotEmpty)
                                            myGroups.join(', '),
                                        ].join(' · '),
                                        style: context.texts.bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: HiwiskiMetrics.space16),
                    AccountSectionLabel(l.accountAppearance),
                    _ThemeSwitch(
                      current: state.theme.mode,
                      onChanged: (mode) => ref
                          .read(accountViewModelProvider.notifier)
                          .setTheme(mode.preference),
                    ),
                    AccountRow(
                      key: AccountKeys.customize,
                      icon: HiwiskiSymbols.tune,
                      label: l.customizeTitle,
                      onTap: () => const CustomizeRoute().go(context),
                    ),
                    if (state.homeWidgets)
                      AccountRow(
                        key: AccountKeys.homeWidgets,
                        icon: HiwiskiSymbols.widgets,
                        label: l.homeWidgetsTitle,
                        onTap: () => const HomeWidgetsRoute().go(context),
                      ),
                    const SizedBox(height: HiwiskiMetrics.space16),
                    AccountSectionLabel(l.accountStorage),
                    StorageSection(state: state),
                    const SizedBox(height: HiwiskiMetrics.space16),
                    AccountSectionLabel(l.accountAdministration),
                    // Picture, name, password — what one changes about oneself.
                    AccountRow(
                      icon: HiwiskiSymbols.person,
                      label: l.myAccountTitle,
                      onTap: () => const MyAccountRoute().go(context),
                    ),
                    // The family, its devices, the dashboard's address and the
                    // server's settings exist only on a server.
                    if (!state.local)
                      AccountRow(
                        icon: HiwiskiSymbols.group,
                        label: l.familyTitle,
                        value: count(state.members),
                        onTap: () => const FamilyRoute().go(context),
                      ),
                    AccountRow(
                      icon: HiwiskiSymbols.sell,
                      label: l.tagsTitle,
                      value: count(state.tags),
                      onTap: () => const TagsRoute().go(context),
                    ),
                    // Calendars are managed like tags and categories, so they are
                    // found beside them — not only behind the cog in the calendar.
                    AccountRow(
                      icon: HiwiskiSymbols.calendarMonth,
                      label: l.calManage,
                      onTap: () => const ManageCalendarsRoute().go(context),
                    ),
                    // The family's, not the member's: the same for everyone.
                    AccountRow(
                      icon: HiwiskiSymbols.category,
                      label: l.aisles,
                      value: count(state.aisles),
                      onTap: () => const CategoriesRoute().go(context),
                    ),
                    if (!state.local) ...[
                      AccountRow(
                        icon: HiwiskiSymbols.devices,
                        label: l.devicesTitle,
                        value: count(state.devices),
                        onTap: () => const DevicesRoute().go(context),
                      ),
                      // The dashboard is set up **in the app** and shown **in the
                      // browser** — that is why it lives here and not as a
                      // section.
                      AccountRow(
                        icon: HiwiskiSymbols.dashboard,
                        label: l.boardDashboard,
                        onTap: () => const DashboardRoute().go(context),
                      ),
                    ],
                    // Next to the trash, the opposite promise: kept, not deleted.
                    // Counted from the mirror — it works offline.
                    AccountRow(
                      icon: HiwiskiSymbols.inventory2,
                      label: l.archiveTitle,
                      value: count(state.archived),
                      onTap: () => const ArchiveRoute().go(context),
                    ),
                    AccountRow(
                      icon: HiwiskiSymbols.deleteOutline,
                      label: l.trashTitle,
                      value: count(state.trash),
                      onTap: () => const TrashRoute().go(context),
                    ),
                    // One row for the server: the administrator reaches its settings
                    // through it, everyone else only reads where it is. Only the
                    // administrator may touch the server, and a button that only
                    // produces an error message is not shown.
                    if (state.local)
                      const SizedBox.shrink()
                    else if (state.isAdmin)
                      AccountRow(
                        icon: HiwiskiSymbols.settings,
                        label: l.settingsTitle,
                        value: serverLabel,
                        onTap: () => const SettingsRoute().go(context),
                      )
                    else
                      AccountRow(
                        icon: HiwiskiSymbols.dns,
                        label: l.serverLabel,
                        value: serverLabel,
                      ),
                    AccountRow(
                      key: AccountKeys.about,
                      icon: HiwiskiSymbols.info,
                      label: l.aboutTitle,
                      onTap: () => const AboutRoute().go(context),
                    ),
                    if (!legal.isEmpty) ...[
                      const SizedBox(height: HiwiskiMetrics.space16),
                      AccountSectionLabel(l.legalTitle),
                      if (legal.notice case final notice?)
                        AccountRow(
                          key: AccountKeys.legalNotice,
                          icon: HiwiskiSymbols.gavel,
                          label: l.legalNotice,
                          leavesApp: true,
                          onTap: () => openLegalPage(notice),
                        ),
                      if (legal.privacy case final privacy?)
                        AccountRow(
                          key: AccountKeys.legalPrivacy,
                          icon: HiwiskiSymbols.policy,
                          label: l.legalPrivacy,
                          leavesApp: true,
                          onTap: () => openLegalPage(privacy),
                        ),
                    ],
                    if (state.local && !state.demo) ...[
                      const SizedBox(height: HiwiskiMetrics.space16),
                      AccountSectionLabel(l.accountWithoutServer),
                      AccountRow(
                        key: AccountKeys.localConnect,
                        icon: HiwiskiSymbols.cloudUpload,
                        label: l.localConnect,
                        onTap: () => AccountScreen._confirmConnect(context),
                      ),
                    ],
                    const SizedBox(height: HiwiskiMetrics.space8),
                    // At the very bottom, in `error`, with a confirmation:
                    // signing out — or, without a server, deleting everything, and in
                    // the demo starting over.
                    switch ((state.local, state.demo)) {
                      (true, true) => _DangerRow(
                        key: AccountKeys.demoReset,
                        icon: HiwiskiSymbols.restartAlt,
                        label: l.demoReset,
                        onTap: () =>
                            AccountScreen._confirmResetDemo(context, ref),
                      ),
                      (true, false) => _DangerRow(
                        key: AccountKeys.localDelete,
                        icon: HiwiskiSymbols.deleteForever,
                        label: l.localDelete,
                        onTap: () =>
                            AccountScreen._confirmDiscard(context, ref),
                      ),
                      _ => _DangerRow(
                        icon: HiwiskiSymbols.logout,
                        label: l.accountSignOut,
                        onTap: () =>
                            AccountScreen._confirmSignOut(context, ref),
                      ),
                    },
                    const SizedBox(height: HiwiskiMetrics.space32),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The last row of the account, in `error`: what cannot be undone.
class _DangerRow extends StatelessWidget {
  const _DangerRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: HiwiskiMetrics.listRowHeight,
        ),
        child: Padding(
          padding: const .symmetric(horizontal: HiwiskiMetrics.space4),
          child: Row(
            spacing: HiwiskiMetrics.space10,
            children: [
              Icon(icon, color: scheme.error),
              // Wraps at large text: "Delete everything" is longer than "Sign out".
              Flexible(
                child: Text(
                  label,
                  style: context.texts.bodyLarge?.copyWith(
                    color: scheme.error,
                    fontWeight: .w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A question before something that cannot be undone, its button in `error`.
class _DangerDialog extends StatelessWidget {
  const _DangerDialog({
    required this.title,
    required this.body,
    required this.action,
    required this.confirmKey,
  });

  final String title;
  final String body;
  final String action;
  final Key confirmKey;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;
    return AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          key: confirmKey,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    );
  }
}

/// Light / dark / system as a segmented button.
///
/// **System** is not in the design and is added anyway: an app without this
/// setting stands out on every phone.
class _ThemeSwitch extends StatelessWidget {
  const _ThemeSwitch({required this.current, required this.onChanged});

  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return SegmentedButton<ThemeMode>(
      segments: [
        ButtonSegment(
          value: ThemeMode.light,
          icon: const Icon(HiwiskiSymbols.lightMode),
          label: Text(l.accountThemeLight),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          icon: const Icon(HiwiskiSymbols.darkMode),
          label: Text(l.accountThemeDark),
        ),
        ButtonSegment(
          value: ThemeMode.system,
          icon: const Icon(HiwiskiSymbols.contrast),
          label: Text(l.accountThemeSystem),
        ),
      ],
      selected: {current},
      showSelectedIcon: false,
      onSelectionChanged: (selection) =>
          onChanged(selection.firstOrNull ?? current),
    );
  }
}
