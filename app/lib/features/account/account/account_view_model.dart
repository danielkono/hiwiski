import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../app/stores.dart';
import '../../../core/api/generated/export.dart' hide Mutation;
import '../../../core/common/build_flavor.dart';
import '../../../core/common/command.dart';
import '../../../domain/legal/legal_links.dart';
import '../../../domain/catalog/catalog_product.dart';
import '../../../domain/preferences/preferences.dart';
import '../../../domain/tags/tag.dart';
import '../../../domain/todo/todo_models.dart';
import '../../../domain/wiki/wiki_models.dart';
import '../../../domain/wiki/wiki_page.dart';

part 'account_view_model.g.dart';

/// Signing out, run by the view: it keeps this ViewModel alive while the screen is
/// already gone.
final signOutMutation = Mutation<void>(label: 'accountViewModel.signOut');

/// `syncBeforeSignOut`, run by the sign-out dialog: it shows the sync running and asks
/// with what is left.
final syncBeforeSignOutMutation = Mutation<int>(
  label: 'accountViewModel.syncBeforeSignOut',
);

/// The account: who is signed in, the appearance, the storage and
/// how many of each thing there are behind the rows. A count is `null` while it is
/// not known.
@immutable
class const AccountState({
  required final Member? member,
  required final bool isAdmin,

  /// From the groups themselves: the session's copy of the member is not refreshed
  /// when a group changes, and the header kept the old groups until the next sign-in.
  required final List<String> myGroups,
  required final String? serverAddress,
  required final ThemePreference theme,

  /// Changes not yet on the server — signing out loses them, and it says so first.
  required final int pending,

  /// What the device keeps: database and images, in bytes; the database's size is
  /// `null` where it cannot be measured (the browser).
  final ({int? data, int images})? storage,
  final int? members,
  final int? tags,
  final int? aisles,
  final int? devices,

  /// Counted from the mirror — it works offline.
  final int? archived,
  final int? trash,

  /// Used without a server: no family, no devices, no settings and no
  /// sign-out — instead, connecting to a server and deleting everything.
  final bool local = false,

  /// The public demo: nothing to connect and nothing to delete, only a reset.
  final bool demo = false,

  /// Whether this device has home screen widgets to set up — phones and tablets.
  final bool homeWidgets = false,

  /// The operator's legal pages, for an instance open to the public.
  final LegalLinks legal = const LegalLinks(),
});

@riverpod
Stream<List<Group>> _groups(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchGroups();

@riverpod
Stream<List<Member>> _members(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchMembers();

@riverpod
Stream<List<Tag>> _tags(Ref ref) =>
    ref.watch(tagRepositoryProvider).watchTags();

@riverpod
Stream<List<CatalogAisle>> _aisles(Ref ref) =>
    ref.watch(catalogRepositoryProvider).watchAisles();

@riverpod
Stream<List<Device>> _devices(Ref ref) =>
    ref.watch(deviceRepositoryProvider).watchDevices();

@riverpod
Stream<List<WikiPage>> _pages(Ref ref) =>
    ref.watch(wikiRepositoryProvider).watchPages();

@riverpod
Stream<List<TodoListSummary>> _archivedLists(Ref ref) =>
    ref.watch(todoRepositoryProvider).watchLists(archived: true);

@riverpod
Stream<TrashList> _trash(Ref ref) =>
    ref.watch(adminRepositoryProvider).watchTrash();

@riverpod
Stream<int> _pending(Ref ref) =>
    ref.watch(syncRepositoryProvider).watchPendingCount();

@riverpod
Future<({int? data, int images})> _storage(Ref ref) =>
    ref.watch(mediaRepositoryProvider).storage();

@riverpod
class AccountViewModel extends _$AccountViewModel {
  @override
  Future<AccountState> build() async {
    final session = ref.watch(sessionProvider);
    final member = session.member;
    final theme = ref.watch(preferencesProvider.select((p) => p.themeMode));
    // From the server, or measured — not waited for: each count stays unknown until
    // it comes, and offline some never come.
    final groups = ref.watch(_groupsProvider).value ?? const <Group>[];
    final members = ref.watch(_membersProvider).value?.length;
    final devices = ref.watch(_devicesProvider).value?.length;
    final trash = ref.watch(_trashProvider).value?.entries.length;
    final storage = ref.watch(_storageProvider).value;
    final pending = ref.watch(_pendingProvider.future);
    final tags = ref.watch(_tagsProvider.future);
    final aisles = ref.watch(_aislesProvider.future);
    final pages = ref.watch(_pagesProvider.future);
    final lists = ref.watch(_archivedListsProvider.future);
    return AccountState(
      local: !session.hasServer,
      demo: BuildFlavor.demo,
      // The demo runs in the browser and has none; a phone has them with or without a
      // server.
      homeWidgets: ref.watch(homeWidgetRepositoryProvider).supported,
      legal: .forInstance(
        notice: session.handshake?.legalNoticeUrl,
        privacy: session.handshake?.privacyUrl,
      ),
      member: member,
      isAdmin: session.isAdmin,
      myGroups: [
        for (final group in groups)
          if (member != null && group.memberIds.contains(member.id)) group.name,
      ],
      serverAddress: session.serverAddress,
      theme: theme,
      pending: await pending,
      storage: storage,
      members: members,
      tags: (await tags).length,
      aisles: (await aisles).length,
      devices: devices,
      archived:
          topLevelArchivedPages([
            for (final page in await pages)
              if (page.archivedAt != null) page,
          ]).length +
          (await lists).length,
      trash: trash,
    );
  }

  /// The choice belongs to the member and goes to the server too.
  Future<void> setTheme(ThemePreference theme) =>
      ref.read(sessionStoreProvider).setTheme(theme);

  /// Throws the cached images away — they come back from the server when viewed.
  Future<void> freeStorage() async {
    await ref.read(mediaRepositoryProvider).clearCache();
    ref.invalidate(_storageProvider);
  }

  /// One last sync before the sign-out is confirmed, and the images added on this
  /// device after it. Returns how many changes still wait afterwards — those the
  /// confirmation has to name.
  @command
  Future<int> syncBeforeSignOut() async {
    final session = ref.read(sessionStoreProvider);
    final sync = ref.read(syncRepositoryProvider);
    await session.syncBeforeSignOut();
    try {
      // Awaited here, unlike after an ordinary sync: an image still on its way would
      // be counted as lost.
      await ref.read(mediaRepositoryProvider).carryOver();
    } on Object catch (error) {
      // Offline or refused: the confirmation names what still waits.
      debugPrint('hiwiski: images before sign-out not uploaded: $error');
    }
    return sync.watchPendingCount().first;
  }

  /// [synced]: the confirmation ran the last sync itself — see
  /// `SessionStore.signOut`.
  Future<void> signOut({bool synced = false}) =>
      ref.read(sessionStoreProvider).signOut(synced: synced);

  /// Without a server: the member made on this device and all their data go.
  Future<void> discardLocal() => ref.read(sessionStoreProvider).discardLocal();

  /// The demo begins anew.
  Future<void> resetDemo() => ref.read(demoProvider).reset();
}
