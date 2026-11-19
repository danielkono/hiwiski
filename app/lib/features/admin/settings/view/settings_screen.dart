import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/generated/export.dart' hide Mutation;
import '../../../../core/api/hiwiski_failure.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/shell/breakpoints.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/failure_text.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../core/ui/page_header.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../../../core/ui/hiwiski_sheet.dart';
import '../settings_view_model.dart';
import 'backup_section.dart';

/// Settings — **administrator only**.
///
/// Family, numbers, retention, backup, log, about. Every row states its consequence:
/// numbers already issued stay valid, and the log retention also sets how far back the
/// history reaches.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _familyName = TextEditingController();
  final _timezone = TextEditingController();
  // The server's defaults, as the labels of the fields.
  static const _defaultTodoPrefix = 'TD';
  static const _defaultEventPrefix = 'EVT';
  static const _defaultWikiPrefix = 'WIKI';
  static const _defaultRecipePrefix = 'REC';
  static const _defaultListPrefix = 'LST';

  final _prefixTodo = TextEditingController();
  final _prefixEvent = TextEditingController();
  final _prefixWiki = TextEditingController();
  final _prefixRecipe = TextEditingController();
  final _prefixList = TextEditingController();
  final _trashDays = TextEditingController();
  final _logDays = TextEditingController();

  /// The settings the form was last filled from. A new answer — after a save or a
  /// backup restore — fills it again; until then what is typed stays.
  InstanceSettings? _filledFrom;
  bool _busy = false;
  String? _error;

  /// Set by a save with a day value that is no whole number of days. It used to go
  /// out as nothing: the server kept the old value, and "Saved" was shown anyway.
  String? _trashDaysError;
  String? _logDaysError;

  @override
  void dispose() {
    _familyName.dispose();
    _timezone.dispose();
    _prefixTodo.dispose();
    _prefixEvent.dispose();
    _prefixWiki.dispose();
    _prefixRecipe.dispose();
    _prefixList.dispose();
    _trashDays.dispose();
    _logDays.dispose();
    super.dispose();
  }

  void _fill(InstanceSettings settings) {
    if (identical(settings, _filledFrom)) return;
    _filledFrom = settings;
    _familyName.text = settings.familyName ?? '';
    _timezone.text = settings.timezone ?? '';
    _prefixTodo.text = settings.keyPrefixTodo ?? '';
    _prefixEvent.text = settings.keyPrefixEvent ?? '';
    _prefixWiki.text = settings.keyPrefixWikiPage ?? '';
    _prefixRecipe.text = settings.keyPrefixRecipe ?? '';
    _prefixList.text = settings.keyPrefixTodoList ?? '';
    _trashDays.text = '${settings.trashRetentionDays ?? 30}';
    _logDays.text = '${settings.logRetentionDays ?? 90}';
  }

  static int? _days(String text) => switch (int.tryParse(text.trim())) {
    final days? when days >= 1 => days,
    _ => null,
  };

  Future<void> _save() async {
    final trashDays = _days(_trashDays.text);
    final logDays = _days(_logDays.text);
    final invalid = L.of(context).validationDays;
    setState(() {
      _trashDaysError = trashDays == null ? invalid : null;
      _logDaysError = logDays == null ? invalid : null;
    });
    if (trashDays == null || logDays == null) return;
    final timezone = _timezone.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final saved = L.of(context).settingsSaved;
    try {
      await ref
          .read(settingsViewModelProvider.notifier)
          .save(
            InstanceSettings(
              familyName: _familyName.text.trim(),
              // An empty zone is left as it is: sent, the server refused it, and
              // no setting at all could be saved until a valid one was typed.
              timezone: timezone.isEmpty ? null : timezone,
              keyPrefixTodo: _prefixTodo.text.trim(),
              keyPrefixEvent: _prefixEvent.text.trim(),
              keyPrefixWikiPage: _prefixWiki.text.trim(),
              keyPrefixRecipe: _prefixRecipe.text.trim(),
              keyPrefixTodoList: _prefixList.text.trim(),
              trashRetentionDays: trashDays,
              logRetentionDays: logDays,
            ),
          );
      messenger.showSnackBar(SnackBar(content: Text(saved)));
    } on HiwiskiFailure catch (failure) {
      if (mounted) setState(() => _error = failureText(context, failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final header = PageHeader(
      title: L.of(context).settingsTitle,
      onBack: () => const AccountRoute().go(context),
    );
    return ref
        .watch(settingsViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          // A failed load used to leave the form empty without a word — and a
          // save from there sent empty values.
          error: (error, _) => HiwiskiPage.error(
            header: header,
            error: error,
            onRetry: () => ref.read(settingsViewModelProvider.notifier).retry(),
          ),
          data: (state) {
            final l = L.of(context);
            final padding = Breakpoint.of(context).pagePadding;
            _fill(state.settings);

            return HiwiskiPage(
              // A save under way — a command running, not the state still coming.
              loading: _busy,
              header: header,
              body: ListView(
                padding: padding,
                children: [
                  if (_error case final error?) ...[
                    NoticeBar.error(context, text: error),
                    const SizedBox(height: HiwiskiMetrics.space16),
                  ],
                  Text(
                    l.settingsFamily,
                    style: context.tokens.text.sectionLabel,
                  ),
                  const SizedBox(height: HiwiskiMetrics.space8),
                  TextField(
                    controller: _familyName,
                    decoration: InputDecoration(labelText: l.setupFamilyName),
                  ),
                  const SizedBox(height: HiwiskiMetrics.space12),
                  TextField(
                    controller: _timezone,
                    decoration: InputDecoration(labelText: l.setupTimezone),
                  ),

                  const SizedBox(height: HiwiskiMetrics.space24),
                  Text(
                    l.settingsNumbers,
                    style: context.tokens.text.sectionLabel,
                  ),
                  const SizedBox(height: HiwiskiMetrics.space4),
                  Text(
                    l.settingsNumbersNote,
                    style: context.texts.bodySmall?.copyWith(
                      color: context.scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: HiwiskiMetrics.space12),
                  Row(
                    spacing: HiwiskiMetrics.space12,
                    children: [
                      Expanded(
                        child: _PrefixField(_prefixTodo, _defaultTodoPrefix),
                      ),
                      Expanded(
                        child: _PrefixField(_prefixEvent, _defaultEventPrefix),
                      ),
                      Expanded(
                        child: _PrefixField(_prefixWiki, _defaultWikiPrefix),
                      ),
                      Expanded(
                        child: _PrefixField(
                          _prefixRecipe,
                          _defaultRecipePrefix,
                        ),
                      ),
                      Expanded(
                        child: _PrefixField(_prefixList, _defaultListPrefix),
                      ),
                    ],
                  ),

                  const SizedBox(height: HiwiskiMetrics.space24),
                  Text(
                    l.settingsRetention,
                    style: context.tokens.text.sectionLabel,
                  ),
                  const SizedBox(height: HiwiskiMetrics.space12),
                  TextField(
                    controller: _trashDays,
                    keyboardType: .number,
                    decoration: InputDecoration(
                      labelText: l.settingsTrashDays,
                      errorText: _trashDaysError,
                    ),
                  ),
                  const SizedBox(height: HiwiskiMetrics.space12),
                  TextField(
                    controller: _logDays,
                    keyboardType: .number,
                    decoration: InputDecoration(
                      labelText: l.settingsLogDays,
                      errorText: _logDaysError,
                    ),
                  ),
                  const SizedBox(height: HiwiskiMetrics.space4),
                  Text(
                    l.settingsLogNote,
                    style: context.texts.bodySmall?.copyWith(
                      color: context.scheme.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: HiwiskiMetrics.space20),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(
                        HiwiskiMetrics.buttonHeight,
                      ),
                    ),
                    child: Text(l.actionSave),
                  ),

                  const SizedBox(height: HiwiskiMetrics.space32),
                  const BackupSection(),

                  const SizedBox(height: HiwiskiMetrics.space24),
                  Text(l.settingsLog, style: context.tokens.text.sectionLabel),
                  const SizedBox(height: HiwiskiMetrics.space8),
                  OutlinedButton.icon(
                    icon: const Icon(HiwiskiSymbols.description),
                    label: Text(l.settingsLogShow),
                    onPressed: _busy ? null : () => _showLog(context),
                  ),
                  const SizedBox(height: HiwiskiMetrics.space32),
                ],
              ),
            );
          },
        );
  }

  Future<void> _showLog(BuildContext context) => showHiwiskiSheet<void>(
    context: context,
    title: L.of(context).settingsLog,
    builder: (context) => const _Log(),
  );
}

/// The server's log lines — fetched when the sheet opens, with "Retry" when that
/// fails.
class _Log extends ConsumerWidget {
  const _Log();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(settingsLogViewModelProvider)
      .when(
        skipLoadingOnReload: true,
        error: (error, _) => NoticeBar.failure(
          context,
          error: error,
          onRetry: () =>
              ref.read(settingsLogViewModelProvider.notifier).retry(),
        ),
        loading: () => const LinearProgressIndicator(),
        data: (log) => SelectableText(
          log.lines.join('\n'),
          style: context.tokens.text.monoSmall,
        ),
      );
}

/// The prefix of one kind of number ("TD", "EVT") — the server's default as label.
class _PrefixField extends StatelessWidget {
  const _PrefixField(this.controller, this.hint);

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    textCapitalization: .characters,
    decoration: InputDecoration(labelText: hint),
  );
}
