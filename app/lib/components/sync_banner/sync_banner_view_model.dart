import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/link_index.dart';
import '../../app/repositories.dart';
import '../../app/stores.dart';
import '../../core/common/build_flavor.dart';
import '../../core/common/wire.dart';
import '../../core/sync/sync_status.dart';
import '../../domain/links/link_index.dart';
import '../../domain/sync/sync_items.dart';
import '../../domain/todo/kanban.dart';
import '../../domain/todo/todo_items.dart';

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
    final conflicts = await ref.watch(_conflictsProvider.future);
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
    return SyncBannerState(
      demo: BuildFlavor.demo,
      status: status,
      conflicts: conflicts,
      webUpdate: webUpdate,
      index: index,
      boards: boards,
      leftBehind: leftBehind,
    );
  }

  void reload() => ref.read(webUpdateStoreProvider).reload();

  /// "Apply anyway": the device's own discarded version goes out once more.
  Future<void> takeMine(SyncConflict conflict) =>
      ref.read(syncRepositoryProvider).takeMine(conflict);

  /// Seen, and the server state accepted.
  Future<void> dismissConflict(SyncConflict conflict) =>
      ref.read(syncRepositoryProvider).dismissConflict(conflict);
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
