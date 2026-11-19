import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/repositories.dart';
import '../../core/api/generated/export.dart';
import '../../core/common/wire.dart';
import '../../domain/access/access_rules.dart';
import '../../domain/common/item_ref.dart';
import '../../domain/todo/todo_models.dart';
import '../../domain/wiki/wiki_models.dart';
import '../../domain/wiki/wiki_page.dart';

part 'archive_view_model.g.dart';

/// An archived page or recipe, at the top of what was archived with it.
class const ArchivedPage({
  required final WikiPage page,

  /// How many subpages were archived with it.
  required final int nested,

  /// Who archived it, by name — `null` when unknown.
  required final String? archivedBy,

  /// Restoring needs what editing needs: owner or *write*.
  required final bool mayRestore,
});

/// An archived list with its numbers.
class const ArchivedList({
  required final TodoListSummary summary,
  required final String? archivedBy,
  required final bool mayRestore,
});

/// The archive — next to the trash, with the opposite promise: nothing here goes away
/// by itself.
@immutable
class ArchiveState {
  const ArchiveState({
    required this.pages,
    required this.recipes,
    required this.lists,
  });

  /// Newest first, each group.
  final List<ArchivedPage> pages;
  final List<ArchivedPage> recipes;
  final List<ArchivedList> lists;

  bool get empty => pages.isEmpty && recipes.isEmpty && lists.isEmpty;
}

@riverpod
Stream<List<WikiPage>> _pages(Ref ref) =>
    ref.watch(wikiRepositoryProvider).watchPages();

@riverpod
Stream<List<TodoListSummary>> _lists(Ref ref) =>
    ref.watch(todoRepositoryProvider).watchLists(archived: true);

@riverpod
Stream<List<Member>> _members(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchMembers();

@riverpod
Stream<ShareSheet> _shares(Ref ref, ItemRef item) =>
    ref.watch(accessRepositoryProvider).watchShareSheet(item);

/// **Read from the mirror, not from the server.** Archived items are ordinary items with
/// two fields set; they are on the device already, filtered by sharing like everything
/// else, and the archive works offline. An endpoint would be a second path to the same
/// rows.
@riverpod
class ArchiveViewModel extends _$ArchiveViewModel {
  @override
  Future<ArchiveState> build() async {
    // From the server — not waited for: offline it may never come.
    final names = {
      for (final member
          in ref.watch(_membersProvider).value ?? const <Member>[])
        member.id: member.displayName,
    };
    final pages = ref.watch(_pagesProvider.future);
    final lists = ref.watch(_listsProvider.future);
    final archived = [
      for (final page in await pages)
        if (page.archivedAt != null) page,
    ];
    bool mayRestore(ItemRef item) =>
        mayWrite(ref.watch(_sharesProvider(item)).value?.myLevel);

    final top = topLevelArchivedPages(archived)
      ..sort((a, b) => _newestFirst(a.archivedAt, b.archivedAt));
    ArchivedPage entry(WikiPage page) => .new(
      page: page,
      nested: branchOf(archived, page.id).length - 1,
      archivedBy: names[page.archivedBy],
      mayRestore: mayRestore(ItemRef.wikiPage(page.id)),
    );

    return ArchiveState(
      pages: [
        for (final page in top)
          if (page.kind != PageKinds.recipe) entry(page),
      ],
      recipes: [
        for (final page in top)
          if (page.kind == PageKinds.recipe) entry(page),
      ],
      lists: [
        for (final summary in [
          ...await lists,
        ]..sort((a, b) => _newestFirst(a.list.archivedAt, b.list.archivedAt)))
          ArchivedList(
            summary: summary,
            archivedBy: names[summary.list.archivedBy],
            mayRestore: mayRestore(ItemRef.todoList(summary.list.id)),
          ),
      ],
    );
  }

  static int _newestFirst(DateTime? a, DateTime? b) =>
      (b ?? DateTime(0)).compareTo(a ?? DateTime(0));

  Future<void> restorePage(WikiPage page, {required bool withSubpages}) => ref
      .read(wikiRepositoryProvider)
      .restorePage(page, withSubpages: withSubpages);

  Future<void> restoreList(ArchivedList entry) =>
      ref.read(todoRepositoryProvider).restoreList(entry.summary.list);
}
