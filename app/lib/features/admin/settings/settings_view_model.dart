import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../app/stores.dart';
import '../../../core/api/backup_file_client.dart';
import '../../../core/api/generated/export.dart' hide Mutation;
import '../../../core/common/command.dart';

part 'settings_view_model.g.dart';

/// A backup being made: the screen shows it running and says when it is done.
final backUpMutation = Mutation<BackupInfo>(label: 'backUp');

/// A backup being restored.
final restoreMutation = Mutation<RestoreResult>(label: 'restore');

/// The password checked and the preview read — before "Replace everything".
final inspectMutation = Mutation<BackupPreview>(label: 'inspectBackup');

/// An archive going up from a file.
final uploadMutation = Mutation<UploadedBackup>(label: 'uploadBackup');

/// An archive coming down, to be saved.
final downloadMutation = Mutation<Uint8List>(label: 'downloadBackup');

/// The backup password changed, or set anew without the old one.
final backupPasswordMutation = Mutation<void>(label: 'backupPassword');

/// What a restore starts from: an archive in the list, or one uploaded from a file.
typedef BackupSource = ({String id, bool uploaded});

/// The instance's settings, its backups and its log — for the administrator.
@immutable
class const SettingsState({
  required final InstanceSettings settings,

  /// Not waited for: the form does not need them. `null` while unknown.
  required final BackupList? backups,

  /// A backup is being restored — by this device or another: nothing can be
  /// changed until it is done.
  final bool restoring = false,
});

@riverpod
Stream<InstanceSettings> _settings(Ref ref) =>
    ref.watch(adminRepositoryProvider).watchInstanceSettings();

@riverpod
Stream<BackupList> _backups(Ref ref) =>
    ref.watch(adminRepositoryProvider).watchBackups();

@riverpod
class SettingsViewModel extends _$SettingsViewModel {
  /// The settings are what the screen is about: they are waited for, even from the
  /// server. A form shown without them saved empty values.
  @override
  Future<SettingsState> build() async {
    final backups = ref.watch(_backupsProvider).value;
    final restoring = ref.watch(sessionProvider.select((s) => s.restoring));
    return SettingsState(
      settings: await ref.watch(_settingsProvider.future),
      backups: backups,
      restoring: restoring,
    );
  }

  /// Asks the server again — after the settings could not be fetched.
  void retry() => ref.invalidate(_settingsProvider);

  Future<void> save(InstanceSettings settings) =>
      ref.read(adminRepositoryProvider).setInstanceSettings(settings);

  @command
  Future<BackupInfo> backUp() =>
      ref.read(adminRepositoryProvider).createBackup();

  /// The password first: a wrong one shows here, before anything is replaced.
  @command
  Future<BackupPreview> inspect(BackupSource source, String password) => ref
      .read(adminRepositoryProvider)
      .inspectBackup(source.id, password, uploaded: source.uploaded);

  /// Restores a backup. The server backs up the current state first. Every device's
  /// state changes: what is fetched over REST shows the state from before no
  /// longer, and the next sync notices the new instance and fetches everything again.
  @command
  Future<RestoreResult> restore(BackupSource source, String password) async {
    final family = ref.read(familyRepositoryProvider);
    final sync = ref.read(syncRepositoryProvider);
    final session = ref.read(sessionStoreProvider);
    final admin = ref.read(adminRepositoryProvider);
    // Read-only at once on this device, before the server's handshake says so.
    session.beginRestore();
    final RestoreResult result;
    try {
      result = await admin.restoreBackup(
        source.id,
        password,
        uploaded: source.uploaded,
      );
    } finally {
      await session.checkRestore();
    }
    family.refresh();
    // The restore is done; the sync that brings it reports its own failure. Awaited,
    // a 503 there turned a successful restore into an error on the screen.
    sync.syncNow().ignore();
    return result;
  }

  @command
  Future<UploadedBackup> upload(Stream<List<int>> bytes, int length) =>
      ref.read(adminRepositoryProvider).uploadBackup(bytes, length);

  @command
  Future<Uint8List> download(BackupInfo backup) =>
      ref.read(adminRepositoryProvider).downloadBackup(backup.id);

  @command
  Future<void> changeBackupPassword(String current, String next) =>
      ref.read(adminRepositoryProvider).changeBackupPassword(current, next);

  @command
  Future<void> resetBackupPassword(String next) =>
      ref.read(adminRepositoryProvider).resetBackupPassword(next);
}

/// The server's log, fetched when its sheet opens.
@riverpod
class SettingsLogViewModel extends _$SettingsLogViewModel {
  @override
  Future<LogLines> build() => ref.watch(adminRepositoryProvider).logs();

  void retry() => ref.invalidateSelf();
}
