import 'package:meta/meta.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/stores.dart';
import '../../core/api/backup_file_client.dart';
import '../../core/api/generated/export.dart' hide Mutation;
import '../../core/common/command.dart';

part 'setup_view_model.g.dart';

/// The setup code checked before the wizard's steps.
final setupCodeMutation = Mutation<void>(label: 'setupCode');

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

  /// Whether the server asks for the setup code from its log. Only where its operator
  /// switched it on, for a server reachable from the internet; a server older than
  /// the setting does not say, and always asks.
  final bool codeRequired = true,

  /// Whether the server can check the code before the wizard's steps. One older than
  /// the setting cannot: there a wrong code comes back only at the end.
  final bool codeCheckable = false,
});

/// The setup wizard: sets the instance up and signs its administrator in — or
/// restores an archive in its place, for a new machine after the old one is gone.
@riverpod
class SetupViewModel extends _$SetupViewModel {
  @override
  SetupState build() {
    // Rebuilt with the session: once the setup took the member over, it is gone.
    final session = ref.watch(sessionProvider);
    final store = ref.read(sessionStoreProvider);
    return SetupState(
      localName: store.connectingFromLocal
          ? store.localMember?.displayName
          : null,
      codeRequired: session.handshake?.setupCodeRequired ?? true,
      // The check came with the setting: a server that names it has the check.
      codeCheckable: session.handshake?.setupCodeRequired != null,
    );
  }

  /// The same state with the upload at [uploaded]: how far an upload has come must
  /// not lose whether the code is asked for.
  SetupState _withUploaded(double? uploaded) => .new(
    localName: state.localName,
    uploaded: uploaded,
    codeRequired: state.codeRequired,
    codeCheckable: state.codeCheckable,
  );

  /// Checks the setup code before the wizard's steps.
  @command
  Future<void> checkCode(String setupCode) =>
      ref.read(sessionStoreProvider).checkSetupCode(setupCode);

  /// [request] gets how this device introduces itself to the server.
  Future<void> setUp(
    SetupRequest Function(DeviceRegistration device) request,
  ) async {
    final session = ref.read(sessionStoreProvider);
    final device = await session.thisDevice();
    await session.runSetup(request(device));
  }

  /// Streams the archive up, with the setup code where the server asks for one; the
  /// state says how far it is.
  @command
  Future<UploadedBackup> upload(
    String? setupCode,
    Stream<List<int>> bytes,
    int length,
  ) async {
    final session = ref.read(sessionStoreProvider);
    state = _withUploaded(0);
    try {
      return await session.uploadSetupBackup(
        setupCode,
        bytes,
        length,
        onProgress: (done) => state = _withUploaded(done),
      );
    } finally {
      state = _withUploaded(null);
    }
  }

  /// The password first: a wrong one stays on its step.
  @command
  Future<BackupPreview> inspect(
    String? setupCode,
    String id,
    String password,
  ) => ref
      .read(sessionStoreProvider)
      .inspectSetupBackup(setupCode, id, password);

  /// Restores the archive. Nobody is signed in by it: the session goes on to the
  /// sign-in, with the members from the archive.
  @command
  Future<void> restore(String? setupCode, String id, String password) => ref
      .read(sessionStoreProvider)
      .restoreSetupBackup(setupCode, id, password);

  /// Back to using the app without a server, as it was.
  Future<void> backToLocal() => ref.read(sessionStoreProvider).backToLocal();
}
