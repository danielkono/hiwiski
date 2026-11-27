import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/link_index.dart';
import '../../app/repositories.dart';
import '../../app/stores.dart';
import '../../core/api/generated/export.dart' show Member;
import '../../core/common/build_flavor.dart';
import '../../core/common/wire.dart';
import '../../core/sync/sync_status.dart';
import '../../domain/links/link_index.dart';
import '../../domain/sync/sync_items.dart';
import '../../domain/todo/kanban.dart';
import '../../domain/todo/todo_items.dart';
import '../../domain/wiki/mindmap.dart';

part 'sync_banner_view_model.g.dart';

/// What the banner above every page says: offline, stuck changes, conflicts, a newer
/// web app.
@immutable
class const SyncBannerState({
  required final SyncStatus status,
  required final List<SyncConflict> conflicts,

  /// The server serves another web app than the one running in this tab.
  required final bool webUpdate,

  /// What a conflict's item is called — "Title was changed" alone does not say which
  /// of twelve tasks.
  required final LinkIndex index,

  /// For a card's conflict over its column: the board's columns by conflict id, so
  /// the sheet names the column instead of showing its id.
  required final Map<String, List<KanbanColumn>> boards,

  /// For a conflict on a mind map's element or connection: its page by conflict id,
  /// so the sheet can show it there — an element has no page of its own.
  final Map<String, String> mindmaps = const {},

  /// The conflicts decided together with one in [conflicts], by its id: an element's
  /// x and y lost against the same move and are one conflict to the person, its width
  /// and height too.
  final Map<String, List<SyncConflict>> partners = const {},

  /// The family's names by member id — for a conflict over whom a mind map's member
  /// element shows: its address names a member, whom the link index does not know.
  final Map<String, String> members = const {},

  /// The public demo: every page says that nothing is kept.
  final bool demo = false,

  /// What a backup restore left behind on this device, waiting to be brought back.
  final int leftBehind = 0,
});

@riverpod
Stream<List<SyncConflict>> _conflicts(Ref ref) =>
    ref.watch(syncRepositoryProvider).watchConflicts();

@riverpod
Stream<TodoList?> _list(Ref ref, String listId) =>
    ref.watch(todoRepositoryProvider).watchList(listId);

@riverpod
Stream<List<OutboxChange>> _stuck(Ref ref) =>
    ref.watch(syncRepositoryProvider).watchStuck();

@riverpod
Stream<List<Member>> _members(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchMembers();

@riverpod
Stream<List<LeftBehindItem>> _leftBehind(Ref ref) =>
    ref.watch(syncRepositoryProvider).watchLeftBehind();

@riverpod
class SyncBannerViewModel extends _$SyncBannerViewModel {
  @override
  Future<SyncBannerState> build() async {
    final status = ref.watch(syncStatusProvider);
    final webUpdate = ref.watch(webUpdateProvider);
    final index = ref.watch(linkIndexProvider);
    final todos = ref.read(todoRepositoryProvider);
    // Decorates the banner: not waited for.
    final leftBehind = ref.watch(_leftBehindProvider).value?.length ?? 0;
    final groups = groupConflicts(await ref.watch(_conflictsProvider.future));
    final conflicts = [for (final group in groups) group.first];
    final boards = <String, List<KanbanColumn>>{};
    for (final conflict in conflicts) {
      if (conflict.entityType != EntityTypes.todo ||
          conflict.field != WireFields.columnId) {
        continue;
      }
      final listId = await todos.listOf(conflict.entityId);
      if (listId == null) continue;
      final list = await ref.watch(_listProvider(listId).future);
      boards[conflict.id] = parseColumns(list?.columns);
    }
    final maps = ref.read(mindmapRepositoryProvider);
    final mindmaps = <String, String>{};
    for (final conflict in conflicts) {
      if (conflict.entityType != EntityTypes.mindmapNode &&
          conflict.entityType != EntityTypes.mindmapEdge) {
        continue;
      }
      final pageId = await maps.pageOf(conflict.entityType, conflict.entityId);
      if (pageId != null) mindmaps[conflict.id] = pageId;
    }
    // Only for a conflict over an element's target — the banner stands on every
    // page — and not waited for: the names come from the server, and offline they
    // may never come.
    final aboutTargets = conflicts.any(
      (conflict) =>
          conflict.entityType == EntityTypes.mindmapNode &&
          conflict.field == WireFields.target,
    );
    final members = aboutTargets
        ? {
            for (final member
                in ref.watch(_membersProvider).value ?? const <Member>[])
              member.id: member.displayName,
          }
        : const <String, String>{};
    return SyncBannerState(
      demo: BuildFlavor.demo,
      status: status,
      conflicts: conflicts,
      webUpdate: webUpdate,
      index: index,
      boards: boards,
      mindmaps: mindmaps,
      partners: {
        for (final group in groups)
          if (group.length > 1) group.first.id: group.sublist(1),
      },
      members: members,
      leftBehind: leftBehind,
    );
  }

  void reload() => ref.read(webUpdateStoreProvider).reload();

  /// "Apply anyway": the device's own discarded version goes out once more — with
  /// what is decided together with it.
  Future<void> takeMine(SyncConflict conflict) async {
    final sync = ref.read(syncRepositoryProvider);
    for (final each in _together(conflict)) {
      await sync.takeMine(each);
    }
  }

  /// Seen, and the server state accepted.
  Future<void> dismissConflict(SyncConflict conflict) async {
    final sync = ref.read(syncRepositoryProvider);
    for (final each in _together(conflict)) {
      await sync.dismissConflict(each);
    }
  }

  List<SyncConflict> _together(SyncConflict conflict) => [
    conflict,
    ...?state.value?.partners[conflict.id],
  ];
}

/// The stuck changes, as a list that closes as soon as nothing is stuck any more.
@riverpod
class StuckChangesViewModel extends _$StuckChangesViewModel {
  @override
  Future<List<OutboxChange>> build() => ref.watch(_stuckProvider.future);

  /// Tries every stuck change once more.
  Future<void> retry() => ref.read(syncRepositoryProvider).retryStuck();

  /// Gives the stuck changes up.
  Future<void> discard() => ref.read(syncRepositoryProvider).discardStuck();
}

/// What a backup restore left behind, as a list that closes once it is decided.
@riverpod
class LeftBehindViewModel extends _$LeftBehindViewModel {
  @override
  Future<List<LeftBehindItem>> build() => ref.watch(_leftBehindProvider.future);

  /// Brings [item] back — every one without.
  Future<void> restore([LeftBehindItem? item]) => ref
      .read(syncRepositoryProvider)
      .restoreLeftBehind(item == null ? null : [item]);

  /// Lets [item] go — every one without.
  Future<void> discard([LeftBehindItem? item]) => ref
      .read(syncRepositoryProvider)
      .discardLeftBehind(item == null ? null : [item]);
}
