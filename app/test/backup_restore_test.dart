import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/data/admin/admin_repository.dart';
import 'package:hiwiski/data/family/family_repository.dart';
import 'package:hiwiski/data/sync/sync_repository.dart';
import 'package:hiwiski/features/admin/settings/settings_view_model.dart';

import 'support/fakes.dart';

/// **After a backup restore, nothing shows the state from before it.**
///
/// The synced items reloaded, but what comes over REST stayed cached: the family
/// screen kept groups that no longer existed, and the settings form, saved again,
/// put today's values back over the restored ones. The admin repository fetches its
/// own answers again (lib/data/query.dart); the family's are another repository's,
/// and the restore asks for them.
void main() {
  test('a restore fetches the family again and syncs', () async {
    final family = _FakeFamily();
    final admin = _FakeAdmin();
    final sync = _FakeSync();
    final container = ProviderContainer(
      overrides: [
        familyRepositoryProvider.overrideWithValue(family),
        adminRepositoryProvider.overrideWithValue(admin),
        syncRepositoryProvider.overrideWithValue(sync),
        sessionAt(signedInAnna),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(settingsViewModelProvider, (_, _) {});
    addTearDown(subscription.close);

    await container.read(settingsViewModelProvider.notifier).restore((
      id: 'b1',
      uploaded: false,
    ), 'backup-passwort');

    expect(admin.restored, equals(['b1 backup-passwort']));
    expect(family.refreshed, equals(1));
    expect(sync.synced, equals(1));
  });
}

class _FakeFamily implements FamilyRepository {
  int refreshed = 0;

  @override
  void refresh() => refreshed++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAdmin implements AdminRepository {
  final restored = <String>[];

  @override
  Stream<InstanceSettings> watchInstanceSettings() =>
      .value(const InstanceSettings());

  @override
  Stream<BackupList> watchBackups() => .value(
    const BackupList(
      backups: [],
      status: BackupStatus(directory: '/data/backup', passwordSet: true),
    ),
  );

  @override
  Future<RestoreResult> restoreBackup(
    String id,
    String password, {
    bool uploaded = false,
  }) async {
    restored.add('$id $password');
    return const RestoreResult(instanceId: 'new', rows: 1);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSync implements SyncRepository {
  int synced = 0;

  @override
  Future<void> syncNow() async => synced++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
