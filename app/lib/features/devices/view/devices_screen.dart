import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/generated/export.dart';
import '../../../core/api/hiwiski_failure.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/shell/breakpoints.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/failure_text.dart';
import '../../../core/ui/page_header.dart';
import '../../../core/ui/hiwiski_page.dart';
import '../devices_view_model.dart';

/// My devices.
///
/// Every device shows its sync state. Without `lastSyncSeq` and `pendingCount` from
/// the device itself it would not exist — that is why every device reports both with
/// every pull.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = PageHeader(
      title: L.of(context).devicesTitle,
      onBack: () => const AccountRoute().go(context),
    );
    return ref
        .watch(devicesViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(
            header: header,
            error: error,
            onRetry: () => ref.read(devicesViewModelProvider.notifier).retry(),
          ),
          data: (list) => HiwiskiPage(
            header: header,
            body: _DeviceList(list: list),
          ),
        );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.list});

  final List<Device> list;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final padding = Breakpoint.of(context).pagePadding;
    return ListView(
      padding: padding,
      children: [
        for (final device in list) _DeviceCard(device: device),
        const SizedBox(height: HiwiskiMetrics.space16),
        Text(
          l.devicesNote,
          style: context.texts.bodySmall?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space32),
      ],
    );
  }
}

class _DeviceCard extends ConsumerWidget {
  const _DeviceCard({required this.device});

  final Device device;

  /// What a tablet's name gives away.
  static const _tabletHints = ['tablet', 'ipad'];

  IconData get _icon => switch (device.platform) {
    .ios || .android
        when _tabletHints.any(device.name.toLowerCase().contains) =>
      HiwiskiSymbols.tablet,
    .ios || .android => HiwiskiSymbols.smartphone,
    .macos || .windows || .linux => HiwiskiSymbols.laptopMac,
    _ => HiwiskiSymbols.desktopWindows,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final scheme = context.scheme;

    return Padding(
      padding: const .only(bottom: HiwiskiMetrics.space12),
      child: Card(
        child: Padding(
          padding: const .all(HiwiskiMetrics.space14),
          child: Row(
            children: [
              Container(
                width: HiwiskiMetrics.tileSize,
                height: HiwiskiMetrics.tileSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: const .all(
                    .circular(HiwiskiMetrics.radiusMenu),
                  ),
                ),
                child: Icon(_icon, color: scheme.onSurface),
              ),
              const SizedBox(width: HiwiskiMetrics.space14),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            device.name,
                            overflow: .ellipsis,
                            style: context.texts.bodyLarge?.copyWith(
                              fontWeight: .w600,
                            ),
                          ),
                        ),
                        if (device.current) ...[
                          const SizedBox(width: HiwiskiMetrics.space8),
                          Container(
                            padding: const .symmetric(
                              horizontal: HiwiskiMetrics.space8,
                              vertical: HiwiskiMetrics.space2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer,
                              borderRadius: const .all(
                                .circular(HiwiskiMetrics.radiusChip),
                              ),
                            ),
                            child: Text(
                              l.devicesThisDevice,
                              style: context.texts.labelSmall?.copyWith(
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      l.devicesSignedInSince(
                        DateFormat.yMMMd(
                          Localizations.localeOf(context).toString(),
                        ).format(device.createdAt),
                      ),
                      style: context.texts.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    _SyncState(device: device),
                  ],
                ),
              ),
              // The own device has no "Sign out" -- the account has the button with a
              // confirmation at the bottom instead.
              if (!device.current)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  onPressed: () => _revoke(context, ref),
                  child: Text(l.devicesRevoke),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Asks first, naming the device and what would be lost: one tap revoked a
  /// partner's phone, and with it the changes still waiting on it.
  Future<void> _revoke(BuildContext context, WidgetRef ref) async {
    final l = L.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.devicesRevokeConfirm(device.name)),
        content: Text(l.devicesRevokeLoss(device.pendingCount ?? 0)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.devicesRevoke),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;
    try {
      await ref.read(devicesViewModelProvider.notifier).revoke(device);
    } on HiwiskiFailure catch (failure) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(failureText(context, failure))),
      );
    }
  }
}

/// "Synced · just now" / "3 changes waiting · offline for 12 days".
class _SyncState extends StatelessWidget {
  const _SyncState({required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;
    final lastSeen = device.lastSeenAt;
    final pending = device.pendingCount ?? 0;

    // "Offline for …" only once it has been a day: a phone seen ten minutes ago with
    // parked changes read "offline for 0 days", in red. Below a day the changes show
    // with the usual "synced … ago".
    if (pending > 0 &&
        lastSeen != null &&
        clock.now().difference(lastSeen).inDays >= 1) {
      return Text(
        l.devicesPending(pending, clock.now().difference(lastSeen).inDays),
        style: context.texts.bodySmall?.copyWith(color: scheme.error),
      );
    }
    if (lastSeen == null) {
      return const SizedBox.shrink();
    }
    final difference = clock.now().difference(lastSeen);
    if (difference.inMinutes < 2) {
      return Text(
        pending > 0
            ? '${l.devicesWaiting(pending)} · ${l.devicesSyncedJustNow}'
            : l.devicesSyncedJustNow,
        style: context.texts.bodySmall?.copyWith(color: scheme.primary),
      );
    }
    final synced = l.devicesSyncedAgo(_ago(context, difference));
    return Text(
      pending > 0 ? '${l.devicesWaiting(pending)} · $synced' : synced,
      style: context.texts.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
    );
  }

  static String _ago(BuildContext context, Duration difference) {
    final l = L.of(context);
    if (difference.inHours < 1) return l.unitMinutes(difference.inMinutes);
    if (difference.inDays < 1) return l.unitHours(difference.inHours);
    return l.unitDays(difference.inDays);
  }
}
