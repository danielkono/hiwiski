import 'package:meta/meta.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/stores.dart';
import '../../core/api/backup_file_client.dart';
import '../../core/api/generated/export.dart' hide Mutation;
import '../../core/common/command.dart';

part 'setup_view_model.g.dart';

/// The archive going up to the fresh server.
final setupUploadMutation = Mutation<UploadedBackup>(label: 'setupUpload');

/// Its password checked and its preview read.
final setupInspectMutation = Mutation<BackupPreview>(label: 'setupInspect');

/// The archive restored in place of the setup.
final setupRestoreMutation = Mutation<void>(label: 'setupRestore');

/// What the wizard starts from.
@immutable
class const SetupState({
  /// The name of the member this device made without a server — it becomes the
  /// administrator, under the same id, and takes the device's data along.
  /// `null` on a device that never ran without one.
  final String? localName,

  /// How far an archive's upload has come, from 0 to 1; `null` while none runs.
  final double? uploaded,
});

/// The setup wizard: sets the instance up and signs its administrator in — or
/// restores an archive in its place, for a new machine after the old one is gone.
@riverpod
class SetupViewModel extends _$SetupViewModel {
  @override
  SetupState build() {
    // Rebuilt with the session: once the setup took the member over, it is gone.
    ref.watch(sessionProvider);
    final store = ref.read(sessionStoreProvider);
    return SetupState(
      localName: store.connectingFromLocal
          ? store.localMember?.displayName
          : null,
    );
  }

  /// [request] gets how this device introduces itself to the server.
  Future<void> setUp(
    SetupRequest Function(DeviceRegistration device) request,
  ) async {
    final session = ref.read(sessionStoreProvider);
    final device = await session.thisDevice();
    await session.runSetup(request(device));
  }

  /// Streams the archive up with the setup code; the state says how far it is.
  @command
  Future<UploadedBackup> upload(
    String setupCode,
    Stream<List<int>> bytes,
    int length,
  ) async {
    final session = ref.read(sessionStoreProvider);
    state = SetupState(localName: state.localName, uploaded: 0);
    try {
      return await session.uploadSetupBackup(
        setupCode,
        bytes,
        length,
        onProgress: (done) =>
            state = SetupState(localName: state.localName, uploaded: done),
      );
    } finally {
      state = SetupState(localName: state.localName);
    }
  }

  /// The password first: a wrong one stays on its step.
  @command
  Future<BackupPreview> inspect(String setupCode, String id, String password) =>
      ref
          .read(sessionStoreProvider)
          .inspectSetupBackup(setupCode, id, password);

  /// Restores the archive. Nobody is signed in by it: the session goes on to the
  /// sign-in, with the members from the archive.
  @command
  Future<void> restore(String setupCode, String id, String password) => ref
      .read(sessionStoreProvider)
      .restoreSetupBackup(setupCode, id, password);

  /// Back to using the app without a server, as it was.
  Future<void> backToLocal() => ref.read(sessionStoreProvider).backToLocal();
}
