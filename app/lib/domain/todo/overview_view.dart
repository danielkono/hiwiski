import '../../core/common/wire.dart';
import 'todo_models.dart';

/// How the task overview shows its lists.
enum TodoViewMode {
  /// All lists in one grid of cards.
  together,

  /// One titled group per kind: tasks, shopping, Kanban.
  byKind,

  /// The lists as rows on the left — like the wiki's pages — and, on a wide screen,
  /// the chosen list open next to them.
  sidebar,
}

/// The view as the preferences store it.
const _together = 'TOGETHER';
const _byKind = 'BY_KIND';
const _sidebar = 'SIDEBAR';

TodoViewMode todoViewModeOf(String? stored) => switch (stored) {
  _byKind => .byKind,
  _sidebar => .sidebar,
  _ => .together,
};

String storedTodoViewMode(TodoViewMode mode) => switch (mode) {
  .together => _together,
  .byKind => _byKind,
  .sidebar => _sidebar,
};

/// The lists of one kind, in their order.
typedef KindGroup = ({String kind, List<TodoListSummary> lists});

/// [lists] by kind — tasks, shopping, Kanban, then any kind this version does not
/// know — each in the order the lists stand in. Kinds without a list are left out.
List<KindGroup> listsByKind(List<TodoListSummary> lists) {
  const known = [ListKinds.standard, ListKinds.shopping, ListKinds.kanban];
  final byKind = <String, List<TodoListSummary>>{};
  for (final summary in lists) {
    byKind.putIfAbsent(summary.list.kind, () => []).add(summary);
  }
  return [
    for (final kind in [
      ...known,
      ...byKind.keys.where((kind) => !known.contains(kind)),
    ])
      if (byKind[kind] case final lists?) (kind: kind, lists: lists),
  ];
}

/// [lists] in the member's own [order]: the ones in it first, as they stand there,
/// then the others in their own order — a list new since the member last sorted, or
/// shared with them since.
List<TodoListSummary> inPersonalOrder(
  List<TodoListSummary> lists,
  List<String> order,
) {
  final rank = {for (final (index, id) in order.indexed) id: index};
  final sorted = [
    for (final summary in lists)
      if (rank.containsKey(summary.list.id)) summary,
  ]..sort((a, b) => rank[a.list.id]!.compareTo(rank[b.list.id]!));
  return [
    ...sorted,
    for (final summary in lists)
      if (!rank.containsKey(summary.list.id)) summary,
  ];
}

/// The ids of [lists] with [id] moved to where [targetId] stands — or `null` when
/// that changes nothing.
List<String>? movedOrder(
  List<TodoListSummary> lists,
  String id,
  String targetId,
) {
  final ids = [for (final summary in lists) summary.list.id];
  final from = ids.indexOf(id);
  final to = ids.indexOf(targetId);
  if (from < 0 || to < 0 || from == to) return null;
  ids.insert(to, ids.removeAt(from));
  return ids;
}
