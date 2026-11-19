import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';
import '../theme/hiwiski_tokens.dart';
import 'shell_view_model.dart';

/// **While a backup is restored the app is read-only** — every screen, the areas and
/// whatever lies above them (an open list, a page, a sheet). Everything stays visible
/// under a banner that says why, but takes no taps until the restore is done: a
/// change made now would be written into the state about to be replaced. The server
/// refuses every change meanwhile anyway.
///
/// Around the whole app, not inside the shell: a list opened from the overview lies
/// above the shell, and there a box was still ticked while the restore ran.
class RestoreGuard extends ConsumerWidget {
  const RestoreGuard({required this.child, super.key});

  final Widget child;

  static const _dimmed = 0.6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restoring = ref.watch(
      shellViewModelProvider.select((shell) => shell.restoring),
    );
    final guarded = AbsorbPointer(
      absorbing: restoring,
      child: AnimatedOpacity(
        opacity: restoring ? _dimmed : 1,
        duration: kThemeAnimationDuration,
        child: child,
      ),
    );
    if (!restoring) return guarded;
    final l = L.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Material(
          color: scheme.secondaryContainer,
          child: SafeArea(
            bottom: false,
            child: Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: .stretch,
                children: [
                  const LinearProgressIndicator(),
                  Padding(
                    padding: const .symmetric(
                      horizontal: HiwiskiMetrics.space16,
                      vertical: HiwiskiMetrics.space12,
                    ),
                    child: Row(
                      spacing: HiwiskiMetrics.space12,
                      children: [
                        Icon(
                          HiwiskiSymbols.backup,
                          color: scheme.onSecondaryContainer,
                        ),
                        Expanded(
                          child: Text(
                            l.restoreRunningBanner,
                            style: context.texts.bodyMedium?.copyWith(
                              color: scheme.onSecondaryContainer,
                            ),
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
        // The banner took the status bar's room.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: guarded,
          ),
        ),
      ],
    );
  }
}
