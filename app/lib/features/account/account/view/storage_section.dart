import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../account_view_model.dart';

/// **Storage** in the account: space used, split into data and images, with
/// "Free up storage" below. That only throws away cached images — they come back
/// the next time they are viewed. Pending changes stay, and it says so.
class StorageSection extends ConsumerWidget {
  const StorageSection({super.key, required this.state});

  final AccountState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final muted = context.scheme.onSurfaceVariant;
    final storage = state.storage;
    final pending = state.pending;
    final locale = Localizations.localeOf(context).toString();

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        if (state.demo)
          // The demo keeps nothing at all: it says so, and there is
          // nothing to free up.
          Text(
            l.storageDemo,
            style: context.texts.bodyMedium?.copyWith(color: muted),
          )
        else if (kIsWeb)
          // In the browser nothing is on disk: the database lives only in the tab's
          // memory. That is stated instead of "0 MB".
          Text(
            l.storageWeb,
            style: context.texts.bodyMedium?.copyWith(color: muted),
          )
        else ...[
          _StorageLine(l.storageData, switch (storage?.data) {
            null => '—',
            final data => _format(l, data, locale),
          }),
          _StorageLine(
            l.storageImages,
            storage == null ? '—' : _format(l, storage.images, locale),
          ),
        ],
        if (pending > 0)
          Padding(
            padding: const .only(top: HiwiskiMetrics.space4),
            child: Text(
              kIsWeb ? l.storagePendingWeb(pending) : l.storagePending(pending),
              style: context.texts.bodySmall?.copyWith(color: muted),
            ),
          ),
        if (!state.demo) ...[
          const SizedBox(height: HiwiskiMetrics.space8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () async {
                await ref.read(accountViewModelProvider.notifier).freeStorage();
              },
              child: Text(l.storageFree),
            ),
          ),
        ],
      ],
    );
  }

  // One decimal below ten, none above — in the locale's own notation.
  static const _oneDecimal = '0.0';
  static const _noDecimal = '0';

  static String _format(L l, int bytes, String locale) {
    final mb = bytes / (1024 * 1024);
    return l.unitMegabytes(
      NumberFormat(mb < 10 ? _oneDecimal : _noDecimal, locale).format(mb),
    );
  }
}

/// "Database · 12 MB".
class _StorageLine extends StatelessWidget {
  const _StorageLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .symmetric(vertical: HiwiskiMetrics.space4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: context.texts.bodyLarge)),
        Text(
          value,
          style: context.texts.bodyMedium?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
