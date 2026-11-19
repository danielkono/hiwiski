import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../app/stores.dart';
import '../../../domain/tags/tag.dart';
import '../../../domain/todo/overview_view.dart';
import '../../../domain/todo/todo_models.dart';

part 'todo_overview_view_model.g.dart';

/// The task overview: the lists through the tag filter.
@immutable
class const TodoOverviewState({
  /// The lists that pass the filter.
  required final List<TodoListSummary> lists,

  /// Whether there is any list at all — "no lists yet" is not "none matches".
  required final bool hasLists,

  /// The tags the filter bar offers, in the order that matters to this member.
  required final List<Tag> tags,

  /// The tags selected as a filter; empty is "All".
  required final Set<String> filter,

  /// How the lists show — kept on the device like the calendar's view.
  required final TodoViewMode mode,

  /// [lists] by kind, for [TodoViewMode.byKind].
  required final List<KindGroup> groups,

  /// The list open next to the rows in [TodoViewMode.sidebar] — the one chosen, or
  /// the first; `null` without lists.
  required final String? selectedId,
});

@riverpod
Stream<List<TodoListSummary>> _lists(Ref ref) =>
    ref.watch(todoRepositoryProvider).watchLists();

@riverpod
Stream<List<String>> _listOrder(Ref ref) =>
    ref.watch(todoRepositoryProvider).watchListOrder();

@riverpod
Stream<List<Tag>> _tags(Ref ref) =>
    ref.watch(tagRepositoryProvider).watchTags();

@riverpod
class TodoOverviewViewModel extends _$TodoOverviewViewModel {
  /// Which page holds the filter.
  static const _page = 'tasks';

  static const _area = TagFilterAreas.areas;

  /// The list chosen in the sidebar while areas do not keep their page; otherwise
  /// it is kept beyond the screen ([todoSidebarProvider]).
  String? _selected;

  /// Every list in the member's order — the filter hides some, a move counts them all.
  List<TodoListSummary> _ordered = const [];

  @override
  Future<TodoOverviewState> build() async {
    ref.watch(tagFilterHoldProvider(_area, _page));
    final filter = ref.watch(
      tagFiltersProvider.select((f) => f[_area] ?? const <String>{}),
    );
    final tagUses = ref.watch(preferencesProvider.select((p) => p.tagUses));
    final mode = ref.watch(
      preferencesProvider.select((p) => todoViewModeOf(p.todoView)),
    );
    final lists = ref.watch(_listsProvider.future);
    final order = ref.watch(_listOrderProvider.future);
    final tags = ref.watch(_tagsProvider.future);
    final keep = ref.watch(preferencesProvider.select((p) => p.keepAreas));
    final selected = keep ? ref.watch(todoSidebarProvider) : _selected;
    final all = inPersonalOrder(await lists, await order);
    _ordered = all;
    final shown = [
      for (final summary in all)
        if (passesTagFilter(filter, summary.list.tags)) summary,
    ];
    return TodoOverviewState(
      lists: shown,
      hasLists: all.isNotEmpty,
      tags: rankTags(await tags, tagUses),
      filter: filter,
      mode: mode,
      groups: listsByKind(shown),
      // A list filtered out or deleted is no longer the one open.
      selectedId:
          shown.where((s) => s.list.id == selected).firstOrNull?.list.id ??
          shown.firstOrNull?.list.id,
    );
  }

  /// Puts the list [id] where [targetId] stands — a card dropped on another. The
  /// order is the member's own: it needs no right on the list, changes nothing for
  /// anyone else, and follows them to their other devices.
  Future<void> move(String id, String targetId) async {
    final order = movedOrder(_ordered, id, targetId);
    if (order == null) return;
    await ref.read(todoRepositoryProvider).setListOrder(order);
  }

  Future<void> setMode(TodoViewMode mode) =>
      ref.read(preferencesStoreProvider).setTodoView(storedTodoViewMode(mode));

  /// Opens a list next to the rows ([TodoViewMode.sidebar]).
  void select(String listId) {
    if (ref.read(preferencesProvider).keepAreas) {
      ref.read(todoSidebarStoreProvider).select(listId);
      return;
    }
    _selected = listId;
    ref.invalidateSelf();
  }

  void toggleTag(String id) =>
      ref.read(tagFilterStoreProvider).toggle(_area, id);

  void clearTags() => ref.read(tagFilterStoreProvider).clear(_area);
}
