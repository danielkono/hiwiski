import 'dart:typed_data';

import '../../core/api/backup_file_client.dart';
import '../../core/api/generated/export.dart';
import '../../core/api/hiwiski_api.dart';
import '../query.dart';
import 'local_trash.dart';

/// The administration: instance settings, backups, the server log and the trash —
/// over REST and not over the sync.
///
/// What is deleted is no longer visible on the device anyway — and whoever opens the
/// trash wants to see the server's state, not the last sync.
///
/// **Without a server** the trash is the device's own ([LocalTrash]);
/// settings, backups and the log exist only on a server.
class AdminRepository {
  AdminRepository(this._api, {required this._localTrash});

  final HiwiskiApi _api;

  /// The trash on the device — set exactly when there is no server.
  final LocalTrash? _localTrash;

  // The trash is fetched whenever it is shown: kept, it was fetched once, and an item
  // deleted anywhere afterwards was missing from it until a restart — exactly where
  // one goes to ask "where did it go?".
  late final _trash = Query<String, TrashList>((_) => trash());
  late final _settings = Query<String, InstanceSettings>(
    (_) => instanceSettings(),
    keep: true,
  );
  late final _backups = Query<String, BackupList>((_) => backups(), keep: true);

  Stream<TrashList> watchTrash() => _localTrash?.watch() ?? _trash.watch('');

  Stream<InstanceSettings> watchInstanceSettings() => _settings.watch('');

  Stream<BackupList> watchBackups() => _backups.watch('');

  /// The entries, and how long the trash keeps them.
  Future<TrashList> trash() =>
      _localTrash?.list() ?? HiwiskiApi.run(() => _api.trash.listTrash());

  /// [targetContainerId] puts it somewhere else — for an item whose container is
  /// gone; left out, it goes back where it was.
  Future<void> restoreFromTrash(
    String itemType,
    String itemId, {
    String? targetContainerId,
  }) async {
    if (_localTrash case final local?) {
      return local.restore(
        itemType,
        itemId,
        targetContainerId: targetContainerId,
      );
    }
    await HiwiskiApi.run(
      () => _api.trash.restoreFromTrash(
        itemType: itemType,
        itemId: itemId,
        body: targetContainerId == null
            ? null
            : RestoreRequest(targetContainerId: targetContainerId),
      ),
    );
    _trash.refresh();
  }

  Future<InstanceSettings> instanceSettings() =>
      HiwiskiApi.run(() => _api.admin.getInstanceSettings());

  Future<InstanceSettings> setInstanceSettings(
    InstanceSettings settings,
  ) async {
    final saved = await HiwiskiApi.run(
      () => _api.admin.setInstanceSettings(body: settings),
    );
    _settings.refresh();
    return saved;
  }

  /// The archives, newest first, and how backing up goes.
  Future<BackupList> backups() =>
      HiwiskiApi.run(() => _api.admin.listBackups());

  Future<BackupInfo> createBackup() async {
    try {
      return await HiwiskiApi.run(() => _api.admin.createBackup());
    } finally {
      // A failure is part of the status too.
      _backups.refresh();
    }
  }

  /// What a restore would bring back — the password first, so a wrong one shows
  /// before anything is replaced. [uploaded] for an archive uploaded from a file.
  Future<BackupPreview> inspectBackup(
    String id,
    String password, {
    bool uploaded = false,
  }) {
    final body = BackupPasswordEntry(password: password);
    return HiwiskiApi.run(
      () => uploaded
          ? _api.admin.inspectUploadedBackup(id: id, body: body)
          : _api.admin.inspectBackup(id: id, body: body),
    );
  }

  /// The server's state changes under every device: what is fetched here shows the
  /// state from before no longer.
  Future<RestoreResult> restoreBackup(
    String id,
    String password, {
    bool uploaded = false,
  }) async {
    final body = BackupPasswordEntry(password: password);
    final result = await HiwiskiApi.run(
      () => uploaded
          ? _api.admin.restoreUploadedBackup(id: id, body: body)
          : _api.admin.restoreBackup(id: id, body: body),
    );
    _trash.refresh();
    _backups.refresh();
    _settings.refresh();
    return result;
  }

  /// Streams an archive to the server, where it waits for its password.
  Future<UploadedBackup> uploadBackup(
    Stream<List<int>> bytes,
    int length, {
    void Function(double done)? onProgress,
  }) => HiwiskiApi.run(
    () => _api.backupFiles.upload(
      bytes,
      length,
      onProgress: _progress(onProgress),
    ),
  );

  Future<Uint8List> downloadBackup(
    String id, {
    void Function(double done)? onProgress,
  }) => HiwiskiApi.run(
    () => _api.backupFiles.fetch(id, onProgress: _progress(onProgress)),
  );

  /// Wraps the same key anew; the archives on the server open with the new password.
  Future<void> changeBackupPassword(String current, String next) async {
    await HiwiskiApi.run(
      () => _api.admin.changeBackupPassword(
        body: BackupPasswordChange(currentPassword: current, newPassword: next),
      ),
    );
    _backups.refresh();
  }

  /// A new key: what was backed up before opens only with the old password.
  Future<void> resetBackupPassword(String next) async {
    await HiwiskiApi.run(
      () => _api.admin.resetBackupPassword(
        body: BackupPasswordReset(newPassword: next),
      ),
    );
    _backups.refresh();
  }

  static void Function(int, int)? _progress(
    void Function(double)? onProgress,
  ) => onProgress == null
      ? null
      : (done, total) => onProgress(total <= 0 ? 0 : done / total);

  Future<LogLines> logs() => HiwiskiApi.run(() => _api.admin.getLogs());
}
