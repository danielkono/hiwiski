import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:riverpod/experimental/mutation.dart';

import '../../../../core/api/generated/export.dart' hide Mutation;
import '../../../../core/api/hiwiski_failure.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/archive_files.dart';
import '../../../../core/ui/failure_text.dart';
import '../../../../core/ui/loading_strip.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../core/ui/password_field.dart';
import '../settings_view_model.dart';

/// "A backup that has never been restored is not a backup."
///
/// The status on top, the schedule, the list with download and restore, the backup
/// password, and where the backups go. Backing up and
/// restoring take a while and can fail: one at a time, with the buttons off while one
/// runs, and with what came of it said either way.
class BackupSection extends ConsumerWidget {
  const BackupSection({super.key});

  static const _keepChoices = 30;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final state = ref.watch(settingsViewModelProvider).value;
    final list = state?.backups;
    final settings = state?.settings;
    final restoring =
        (state?.restoring ?? false) || ref.watch(restoreMutation).isPending;
    final busy =
        restoring ||
        [
          backUpMutation,
          inspectMutation,
          uploadMutation,
          downloadMutation,
          backupPasswordMutation,
        ].any((mutation) => ref.watch(mutation).isPending);
    _listen(context, ref);

    final subdued = context.texts.bodySmall?.copyWith(
      color: context.scheme.onSurfaceVariant,
    );
    final status = list?.status;
    final backups = list?.backups ?? const <BackupInfo>[];

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(l.settingsBackup, style: context.tokens.text.sectionLabel),
        const SizedBox(height: HiwiskiMetrics.space8),
        LoadingStrip(loading: busy && !restoring),
        if (restoring) ...[
          const _RestoreRunning(),
          const SizedBox(height: HiwiskiMetrics.space16),
        ],
        if (status != null) ...[
          if (!status.passwordSet)
            NoticeBar.error(context, text: l.backupPasswordNone)
          else if (status.failure case final failure?)
            NoticeBar.error(
              context,
              text: l.settingsBackupFailed(
                backupFailureText(l, failure.reason.json),
              ),
            )
          else
            Text(_statusLine(context, status), style: subdued),
          const SizedBox(height: HiwiskiMetrics.space16),
        ],

        // The schedule. There is no "off".
        if (settings != null) ...[
          Text(l.settingsBackupSchedule, style: context.texts.titleSmall),
          const SizedBox(height: HiwiskiMetrics.space8),
          Wrap(
            spacing: HiwiskiMetrics.space12,
            runSpacing: HiwiskiMetrics.space12,
            crossAxisAlignment: .center,
            children: [
              DropdownMenu<InstanceSettingsBackupFrequency>(
                initialSelection: settings.backupFrequency ?? .daily,
                enabled: !busy,
                dropdownMenuEntries: [
                  DropdownMenuEntry(
                    value: .daily,
                    label: l.settingsBackupDaily,
                  ),
                  DropdownMenuEntry(
                    value: .weekly,
                    label: l.settingsBackupWeekly,
                  ),
                ],
                onSelected: (frequency) => _save(
                  context,
                  ref,
                  InstanceSettings(backupFrequency: frequency),
                ),
              ),
              if (settings.backupFrequency == .weekly)
                DropdownMenu<int>(
                  label: Text(l.settingsBackupWeekday),
                  initialSelection: settings.backupWeekday ?? DateTime.monday,
                  enabled: !busy,
                  dropdownMenuEntries: [
                    for (
                      var day = DateTime.monday;
                      day <= DateTime.sunday;
                      day++
                    )
                      DropdownMenuEntry(
                        value: day,
                        label: _weekdayName(context, day),
                      ),
                  ],
                  onSelected: (day) =>
                      _save(context, ref, InstanceSettings(backupWeekday: day)),
                ),
              OutlinedButton.icon(
                icon: const Icon(HiwiskiSymbols.schedule),
                label: Text(
                  '${l.settingsBackupTime} ${settings.backupTime ?? ''}',
                ),
                onPressed: busy
                    ? null
                    : () => unawaited(_pickTime(context, ref, settings)),
              ),
              DropdownMenu<int>(
                label: Text(l.settingsBackupKeep),
                initialSelection: settings.backupKeep,
                enabled: !busy,
                dropdownMenuEntries: [
                  for (var keep = 1; keep <= _keepChoices; keep++)
                    DropdownMenuEntry(value: keep, label: '$keep'),
                ],
                onSelected: (keep) => keep == null
                    ? null
                    : unawaited(_keep(context, ref, keep, backups.length)),
              ),
            ],
          ),
          const SizedBox(height: HiwiskiMetrics.space16),
        ],

        if (list != null && backups.isEmpty)
          Text(l.settingsBackupNone, style: subdued),
        for (final backup in backups)
          _BackupRow(
            backup: backup,
            onDownload: busy
                ? null
                : () => unawaited(_download(context, ref, backup)),
            onRestore: busy
                ? null
                : () => unawaited(
                    _restore(context, ref, (id: backup.id, uploaded: false)),
                  ),
          ),
        const SizedBox(height: HiwiskiMetrics.space12),
        Wrap(
          spacing: HiwiskiMetrics.space12,
          runSpacing: HiwiskiMetrics.space8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(HiwiskiSymbols.backup),
              label: Text(l.settingsBackupNow),
              onPressed: busy
                  ? null
                  : () =>
                        // The mutation's state holds the outcome; build reacts.
                        backUpMutation
                            .run(
                              ref,
                              (tsx) => tsx
                                  .get(settingsViewModelProvider.notifier)
                                  .backUp(),
                            )
                            .ignore(),
            ),
            OutlinedButton.icon(
              icon: const Icon(HiwiskiSymbols.upload),
              label: Text(l.settingsRestoreFromFile),
              onPressed: busy
                  ? null
                  : () => unawaited(_restoreFromFile(context, ref)),
            ),
          ],
        ),

        const SizedBox(height: HiwiskiMetrics.space24),
        Text(l.backupPasswordTitle, style: context.texts.titleSmall),
        const SizedBox(height: HiwiskiMetrics.space8),
        Wrap(
          spacing: HiwiskiMetrics.space12,
          runSpacing: HiwiskiMetrics.space8,
          crossAxisAlignment: .center,
          children: [
            if (status?.passwordSet ?? true)
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => unawaited(_changePassword(context, ref)),
                child: Text(l.backupPasswordChange),
              ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => unawaited(_resetPassword(context, ref)),
              child: Text(l.backupPasswordForgot),
            ),
          ],
        ),
        if (status != null) ...[
          const SizedBox(height: HiwiskiMetrics.space16),
          Text(l.settingsBackupWhere(status.directory), style: subdued),
        ],
      ],
    );
  }

  /// What came of every command, said either way.
  static void _listen(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    void say(String text) =>
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(text)));
    void sayFailure(Object error) =>
        say(failureText(context, HiwiskiFailure.from(error)));
    ref
      ..listen(backUpMutation, (_, next) {
        switch (next) {
          case MutationSuccess():
            say(l.settingsBackupDone);
          case MutationError(:final error):
            sayFailure(error);
          case MutationIdle() || MutationPending():
        }
      })
      ..listen(restoreMutation, (_, next) {
        switch (next) {
          case MutationSuccess(:final value):
            say(l.settingsRestoreDone(value.rows));
          case MutationError(:final error):
            sayFailure(error);
          case MutationIdle() || MutationPending():
        }
      })
      ..listen(backupPasswordMutation, (_, next) {
        switch (next) {
          case MutationSuccess():
            say(l.backupPasswordChanged);
          case MutationError(:final error):
            sayFailure(error);
          case MutationIdle() || MutationPending():
        }
      });
  }

  static String _statusLine(BuildContext context, BackupStatus status) {
    final l = L.of(context);
    final next = switch (status.nextDueAt) {
      final next? => l.settingsBackupNext(_when(context, next)),
      null => null,
    };
    final last = switch (status.lastBackupAt) {
      final last? => l.settingsBackupLast(_when(context, last)),
      null => l.settingsBackupNone,
    };
    return [last, ?next].join(' · ');
  }

  static String _when(BuildContext context, DateTime at) =>
      DateFormat.yMMMd(Localizations.localeOf(context).toString())
          .add_Hm()
          .format(at.toLocal());

  static String _weekdayName(BuildContext context, int day) => DateFormat.EEEE(
    Localizations.localeOf(context).toString(),
    // 2024-01-01 was a Monday.
  ).format(DateTime(_aMonday.year, _aMonday.month, _aMonday.day + day - 1));

  static final _aMonday = DateTime(2024);

  static Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    InstanceSettings change,
  ) async {
    try {
      await ref.read(settingsViewModelProvider.notifier).save(change);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(failureText(context, HiwiskiFailure.from(error))),
          ),
        );
      }
    }
  }

  static Future<void> _pickTime(
    BuildContext context,
    WidgetRef ref,
    InstanceSettings settings,
  ) async {
    final parts = (settings.backupTime ?? _defaultTime).split(_timeSeparator);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.firstOrNull ?? '') ?? 2,
        minute: int.tryParse(parts.lastOrNull ?? '') ?? 0,
      ),
    );
    if (picked == null || !context.mounted) return;
    final hour = '${picked.hour}'.padLeft(2, '0');
    final minute = '${picked.minute}'.padLeft(2, '0');
    await _save(
      context,
      ref,
      InstanceSettings(backupTime: '$hour$_timeSeparator$minute'),
    );
  }

  static const _defaultTime = '02:00';
  static const _timeSeparator = ':';

  /// Lowering the number says first how many archives go.
  static Future<void> _keep(
    BuildContext context,
    WidgetRef ref,
    int keep,
    int stored,
  ) async {
    final l = L.of(context);
    if (keep < stored) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.settingsBackupKeepConfirm),
          content: Text(l.settingsBackupKeepLower(stored - keep)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.actionSave),
            ),
          ],
        ),
      );
      if (!(confirmed ?? false) || !context.mounted) return;
    }
    await _save(context, ref, InstanceSettings(backupKeep: keep));
  }

  static Future<void> _download(
    BuildContext context,
    WidgetRef ref,
    BackupInfo backup,
  ) async {
    final l = L.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final unreadable = l.errorBackupNotFound;
    try {
      final bytes = await downloadMutation.run(
        ref,
        (tsx) => tsx.get(settingsViewModelProvider.notifier).download(backup),
      );
      final saved = await saveArchive(_fileName(backup), bytes);
      if (saved) {
        messenger.showSnackBar(
          SnackBar(content: Text(l.settingsBackupDownloaded)),
        );
      }
    } on HiwiskiFailure catch (failure) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(failureText(context, failure))),
        );
      }
    } on Object catch (error) {
      debugPrint('hiwiski: backup not saved: $error');
      messenger.showSnackBar(SnackBar(content: Text(unreadable)));
    }
  }

  static String _fileName(BackupInfo backup) =>
      '$_filePrefix${backup.id}$_fileSuffix';

  static const _filePrefix = 'hiwiski-';
  static const _fileSuffix = '.hiwiski';

  static Future<void> _restoreFromFile(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final picked = await pickArchive();
    if (picked == null || !context.mounted) return;
    try {
      final upload = await uploadMutation.run(
        ref,
        (tsx) => tsx
            .get(settingsViewModelProvider.notifier)
            .upload(picked.bytes, picked.length),
      );
      if (!context.mounted) return;
      await _restore(context, ref, (id: upload.id, uploaded: true));
    } on HiwiskiFailure catch (failure) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failureText(context, failure))));
      }
    }
  }

  /// The password first, then the preview and "Replace everything".
  static Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    BackupSource source,
  ) async {
    final l = L.of(context);
    final password = await showDialog<String>(
      context: context,
      builder: (context) => _UnlockDialog(source: source),
    );
    if (password == null || !context.mounted) return;
    final preview = ref.read(inspectMutation);
    if (preview is! MutationSuccess<BackupPreview>) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.backupPreviewTitle),
        content: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            _Preview(preview: preview.value),
            const SizedBox(height: HiwiskiMetrics.space16),
            Text(l.backupPreviewWarning),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.backupReplaceEverything),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;
    // The instance ID is now a different one; the next sync throws away the
    // mirrored data and loads it again. The mutation's state holds the outcome, and
    // the listener in build says it.
    restoreMutation
        .run(
          ref,
          (tsx) => tsx
              .get(settingsViewModelProvider.notifier)
              .restore(source, password),
        )
        .ignore();
  }

  static Future<void> _changePassword(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l = L.of(context);
    final entered = await showDialog<({String current, String next})>(
      context: context,
      builder: (context) => _NewPasswordDialog(
        title: l.backupPasswordChangeTitle,
        hint: l.backupPasswordChangeHint,
        askCurrent: true,
      ),
    );
    if (entered == null || !context.mounted) return;
    // The listener in build says what came of it.
    backupPasswordMutation
        .run(
          ref,
          (tsx) => tsx
              .get(settingsViewModelProvider.notifier)
              .changeBackupPassword(entered.current, entered.next),
        )
        .ignore();
  }

  /// Says before anything happens that the backups so far open only with the old one.
  static Future<void> _resetPassword(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l = L.of(context);
    final entered = await showDialog<({String current, String next})>(
      context: context,
      builder: (context) => _NewPasswordDialog(
        title: l.backupPasswordResetTitle,
        hint: l.backupPasswordResetWarning,
        askCurrent: false,
      ),
    );
    if (entered == null || !context.mounted) return;
    // The listener in build says what came of it.
    backupPasswordMutation
        .run(
          ref,
          (tsx) => tsx
              .get(settingsViewModelProvider.notifier)
              .resetBackupPassword(entered.next),
        )
        .ignore();
  }
}

/// The restore under way — here on the device that started it, after a restart of
/// the app too, and on every other admin's.
class _RestoreRunning extends StatelessWidget {
  const _RestoreRunning();

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Card.filled(
      color: context.scheme.secondaryContainer,
      child: Padding(
        padding: const .all(HiwiskiMetrics.space16),
        child: Row(
          spacing: HiwiskiMetrics.space16,
          children: [
            const CircularProgressIndicator(),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: HiwiskiMetrics.space4,
                children: [
                  Text(l.restoreRunningTitle, style: context.texts.titleSmall),
                  Text(l.restoreRunningBody, style: context.texts.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupRow extends StatelessWidget {
  const _BackupRow({
    required this.backup,
    required this.onDownload,
    required this.onRestore,
  });

  final BackupInfo backup;
  final VoidCallback? onDownload;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final when = DateFormat.yMMMd(Localizations.localeOf(context).toString())
        .add_Hm()
        .format(backup.createdAt.toLocal());
    final reason = switch (backup.reason) {
      .beforeUpdate => l.settingsBackupBeforeUpdate(backup.updateTo ?? '?'),
      .beforeRestore => l.settingsBackupBeforeRestore,
      _ => null,
    };
    final oldKey = backup.currentKey ? null : l.settingsBackupOldPassword;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(HiwiskiSymbols.backup),
      title: Text(when),
      subtitle: Text(
        [
          '${backup.serverVersion} · ${megabytes(l, backup.bytes)}',
          ?reason,
          ?oldKey,
        ].join('\n'),
        style: context.tokens.text.monoSmall,
      ),
      isThreeLine: reason != null || oldKey != null,
      trailing: Row(
        mainAxisSize: .min,
        children: [
          IconButton(
            icon: const Icon(HiwiskiSymbols.download),
            tooltip: l.settingsBackupDownload,
            onPressed: onDownload,
          ),
          TextButton(onPressed: onRestore, child: Text(l.settingsRestore)),
        ],
      ),
    );
  }
}

/// The size as people read it: megabytes with one decimal.
String megabytes(L l, int bytes) =>
    l.unitMegabytes((bytes / _bytesPerMegabyte).toStringAsFixed(1));

const _bytesPerMegabyte = 1024 * 1024;

/// What the archive holds, from its decrypted manifest.
class _Preview extends StatelessWidget {
  const _Preview({required this.preview});

  final BackupPreview preview;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final when = DateFormat.yMMMd(Localizations.localeOf(context).toString())
        .add_Hm()
        .format(preview.createdAt.toLocal());
    return Text(
      [
        l.backupPreviewWhen(when),
        if (preview.familyName case final name?) l.backupPreviewFamily(name),
        l.backupPreviewVersion(preview.serverVersion),
        megabytes(l, preview.bytes),
        l.backupPreviewMembers(preview.members),
      ].join('\n'),
    );
  }
}

/// Asks for the archive's password and checks it right here: a wrong one stays in the
/// dialog — *"That password does not open this backup."* Pops the password once the
/// preview is read.
class _UnlockDialog extends ConsumerStatefulWidget {
  const _UnlockDialog({required this.source});

  final BackupSource source;

  @override
  ConsumerState<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends ConsumerState<_UnlockDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final password = _password.text;
    try {
      await inspectMutation.run(
        ref,
        (tsx) => tsx
            .get(settingsViewModelProvider.notifier)
            .inspect(widget.source, password),
      );
      if (mounted) Navigator.of(context).pop(password);
    } on Object catch (error) {
      // Shown from the mutation's state below, under the field.
      debugPrint('hiwiski: backup not opened: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final inspect = ref.watch(inspectMutation);
    final failure = switch (inspect) {
      MutationError(:final error) => HiwiskiFailure.from(error),
      _ => null,
    };
    // A wrong password belongs to the field. Anything else — another family's
    // archive, one too new, one damaged — is a sentence of its own: under the field
    // it was cut off after one line.
    return AlertDialog(
      title: Text(l.backupPasswordTitle),
      content: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Text(l.backupPasswordPrompt),
          const SizedBox(height: HiwiskiMetrics.space12),
          PasswordField(
            controller: _password,
            label: l.backupPasswordTitle,
            errorText: switch (failure) {
              final wrong?
                  when wrong.code == FailureCodes.backupPasswordWrong =>
                failureText(context, wrong),
              _ => null,
            },
            onSubmitted: () => unawaited(_unlock()),
          ),
          LoadingStrip(loading: inspect.isPending),
          if (failure case final other?
              when other.code != FailureCodes.backupPasswordWrong) ...[
            const SizedBox(height: HiwiskiMetrics.space12),
            NoticeBar.error(context, text: failureText(context, other)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: inspect.isPending ? null : () => unawaited(_unlock()),
          child: Text(l.actionContinue),
        ),
      ],
    );
  }
}

/// A new backup password, typed twice — and the current one, when changing it.
class _NewPasswordDialog extends StatefulWidget {
  const _NewPasswordDialog({
    required this.title,
    required this.hint,
    required this.askCurrent,
  });

  final String title;
  final String hint;
  final bool askCurrent;

  @override
  State<_NewPasswordDialog> createState() => _NewPasswordDialogState();
}

class _NewPasswordDialogState extends State<_NewPasswordDialog> {
  static const _minimumLength = 8;

  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _submit() {
    final l = L.of(context);
    if (_next.text.length < _minimumLength) {
      setState(() => _error = l.errorBackupPasswordTooShort);
      return;
    }
    if (_next.text != _repeat.text) {
      setState(() => _error = l.passwordMismatch);
      return;
    }
    Navigator.of(context).pop((current: _current.text, next: _next.text));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Text(widget.hint),
          const SizedBox(height: HiwiskiMetrics.space12),
          if (widget.askCurrent) ...[
            PasswordField(controller: _current, label: l.backupPasswordCurrent),
            const SizedBox(height: HiwiskiMetrics.space12),
          ],
          PasswordField(controller: _next, label: l.backupPasswordNew),
          const SizedBox(height: HiwiskiMetrics.space12),
          PasswordField(
            controller: _repeat,
            label: l.backupPasswordRepeat,
            errorText: _error,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(
            widget.askCurrent ? l.backupPasswordChange : l.backupPasswordSet,
          ),
        ),
      ],
    );
  }
}
