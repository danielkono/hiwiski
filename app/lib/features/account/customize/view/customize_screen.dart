import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/shell/breakpoints.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/page_header.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../view/account_keys.dart';
import '../customize_view_model.dart';

/// "Customize" — how the app behaves on this device. Nothing here is synced: another
/// device of the same member may want it differently. That includes what an automatic
/// sign-out leaves on this device.
class CustomizeScreen extends ConsumerWidget {
  const CustomizeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final padding = Breakpoint.of(context).pagePadding;
    final state = ref.watch(customizeViewModelProvider);
    return HiwiskiPage(
      header: PageHeader(
        title: l.customizeTitle,
        onBack: () => const AccountRoute().go(context),
      ),
      body: ListView(
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
                  SwitchListTile(
                    key: AccountKeys.keepFilters,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.customizeKeepFilters),
                    subtitle: Text(l.customizeKeepFiltersHint),
                    value: state.keepFilters,
                    onChanged: (value) => ref
                        .read(customizeViewModelProvider.notifier)
                        .setKeepFilters(value),
                  ),
                  SwitchListTile(
                    key: AccountKeys.keepAreas,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.customizeKeepAreas),
                    subtitle: Text(l.customizeKeepAreasHint),
                    value: state.keepAreas,
                    onChanged: (value) => ref
                        .read(customizeViewModelProvider.notifier)
                        .setKeepAreas(value),
                  ),
                  SwitchListTile(
                    key: AccountKeys.doneLast,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.customizeDoneLast),
                    subtitle: Text(l.customizeDoneLastHint),
                    value: state.doneLast,
                    onChanged: (value) => ref
                        .read(customizeViewModelProvider.notifier)
                        .setDoneLast(value),
                  ),
                  // How texts open for writing; the editor's bar switches either way.
                  SwitchListTile(
                    key: AccountKeys.formattedEditor,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.customizeFormattedEditor),
                    subtitle: Text(l.customizeFormattedEditorHint),
                    value: state.formattedEditor,
                    onChanged: (value) => ref
                        .read(customizeViewModelProvider.notifier)
                        .setFormattedEditor(value),
                  ),
                  SwitchListTile(
                    key: AccountKeys.pullHint,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.customizePullHint),
                    subtitle: Text(l.customizePullHintHint),
                    value: state.pullHint,
                    onChanged: (value) => ref
                        .read(customizeViewModelProvider.notifier)
                        .setPullHint(value),
                  ),
                  const SizedBox(height: HiwiskiMetrics.space24),
                  // How long a deletion can be taken back — the note with "Undo"
                  // shows that long, and the deletion waits for it.
                  Text(
                    l.customizeUndo,
                    style: context.tokens.text.sectionLabel,
                  ),
                  const SizedBox(height: HiwiskiMetrics.space8),
                  Text(
                    l.customizeUndoHint,
                    style: context.texts.bodyMedium?.copyWith(
                      color: context.scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: HiwiskiMetrics.space8),
                  SegmentedButton<int>(
                    key: AccountKeys.undoSeconds,
                    showSelectedIcon: false,
                    segments: [
                      for (final seconds in undoChoices)
                        ButtonSegment(
                          value: seconds,
                          label: Text(l.customizeUndoSeconds(seconds)),
                        ),
                    ],
                    selected: {state.undoSeconds},
                    onSelectionChanged: (value) => ref
                        .read(customizeViewModelProvider.notifier)
                        .setUndoSeconds(value.firstOrNull ?? state.undoSeconds),
                  ),
                  // When the device signs itself out, and what is lost then — said
                  // here, before it happens.
                  if (state.signsOut) ...[
                    const SizedBox(height: HiwiskiMetrics.space24),
                    Text(
                      l.customizeAutoSignOut,
                      style: context.tokens.text.sectionLabel,
                    ),
                    const SizedBox(height: HiwiskiMetrics.space8),
                    Text(
                      l.customizeAutoSignOutHint,
                      style: context.texts.bodyMedium?.copyWith(
                        color: context.scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: HiwiskiMetrics.space8),
                    RadioGroup<bool>(
                      groupValue: state.wipeOnAccessLost,
                      onChanged: (value) => ref
                          .read(customizeViewModelProvider.notifier)
                          .setWipeOnAccessLost(value ?? false),
                      child: Column(
                        children: [
                          RadioListTile<bool>(
                            key: AccountKeys.accessLostLock,
                            contentPadding: EdgeInsets.zero,
                            value: false,
                            title: Text(l.customizeAccessLostLock),
                            subtitle: Text(l.customizeAccessLostLockHint),
                          ),
                          RadioListTile<bool>(
                            key: AccountKeys.accessLostWipe,
                            contentPadding: EdgeInsets.zero,
                            value: true,
                            title: Text(l.customizeAccessLostWipe),
                            subtitle: Text(l.customizeAccessLostWipeHint),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
