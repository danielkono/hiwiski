import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/repositories.dart';
import '../../core/api/hiwiski_failure.dart';
import '../../core/common/command.dart';
import '../../core/common/wire.dart';
import '../../domain/common/item_ref.dart';
import '../../domain/todo/todo_items.dart';
import '../../domain/transfer/transfer_bundle.dart';
import '../../domain/wiki/wiki_page.dart';

part 'export_view_model.g.dart';

/// `export`, run by the sheet: it shows the command running, saves the file it
/// answers with and shows why there is none.
final exportMutation = Mutation<ExportedFile>(label: 'exportViewModel.export');

/// What can be exported of an item, and so what the sheet offers to choose.
@immutable
class const ExportState({
  required final String name,

  /// Whether the item is a wiki page; otherwise it is a list.
  required final bool isPage,

  /// A list's tasks, and how many of them are done.
  final int tasks = 0,
  final int doneTasks = 0,

  /// The pages below a page, at any depth, without the archived ones.
  final int subpages = 0,

  /// The images of the page alone, and of the page with its subpages.
  final int images = 0,
  final int imagesWithSubpages = 0,
});

@riverpod
Stream<TodoList?> _list(Ref ref, String listId) =>
    ref.watch(todoRepositoryProvider).watchList(listId);

@riverpod
Stream<List<Todo>> _todos(Ref ref, String listId) =>
    ref.watch(todoRepositoryProvider).watchTodos(listId, doneLast: false);

@riverpod
Stream<List<WikiPage>> _pages(Ref ref) =>
    ref.watch(wikiRepositoryProvider).watchPages();

/// A list or a wiki page on its way into a file: Markdown anyone can read, with the
/// subpages and images the person asks for.
///
/// Everything comes from this device — an export works offline. Only an image never
/// viewed here has to be fetched first.
@riverpod
class ExportViewModel extends _$ExportViewModel {
  /// `null` once the item is gone.
  @override
  Future<ExportState?> build(ItemRef item) async {
    if (item.type == EntityTypes.wikiPage) {
      final pages = await ref.watch(_pagesProvider.future);
      final page = pages.where((page) => page.id == item.id).firstOrNull;
      if (page == null) return null;
      final branch = exportBranch(page, pages, withSubpages: true);
      return ExportState(
        name: page.title,
        isPage: true,
        subpages: branch.length - 1,
        images: branchImageIds([page]).length,
        imagesWithSubpages: branchImageIds(branch).length,
      );
    }
    final list = ref.watch(_listProvider(item.id).future);
    final todos = ref.watch(_todosProvider(item.id).future);
    final row = await list;
    if (row == null) return null;
    final tasks = await todos;
    return ExportState(
      name: row.name,
      isPage: false,
      tasks: tasks.length,
      doneTasks: tasks.where((todo) => todo.status == TodoStatuses.done).length,
    );
  }

  /// Builds the file. [withDone] is a list's choice, [withSubpages] and [withImages]
  /// are a page's.
  @command
  Future<ExportedFile> export({
    bool withDone = true,
    bool withSubpages = false,
    bool withImages = false,
  }) async {
    // All taken before the first wait: the sheet may close while the file is built.
    final todo = ref.read(todoRepositoryProvider);
    final wiki = ref.read(wikiRepositoryProvider);
    final media = ref.read(mediaRepositoryProvider);
    final tagNames = {
      for (final tag in await ref.read(tagRepositoryProvider).watchTags().first)
        tag.id: tag.name,
    };

    if (item.type != EntityTypes.wikiPage) {
      final list = await todo.watchList(item.id).first;
      if (list == null) throw StateError('the list is gone');
      final todos = await todo.watchTodos(item.id, doneLast: false).first;
      final file = listExportFile(
        list: list,
        todos: [
          for (final row in todos)
            if (withDone || row.status != TodoStatuses.done) row,
        ],
        tagNames: tagNames,
      );
      return packExport([file], name: list.name);
    }

    final pages = await wiki.watchPages().first;
    final page = pages.where((page) => page.id == item.id).firstOrNull;
    if (page == null) throw StateError('the page is gone');
    final branch = exportBranch(page, pages, withSubpages: withSubpages);
    final images = <String, Uint8List>{};
    if (withImages) {
      for (final id in branchImageIds(branch)) {
        try {
          images[id] = await media.image(id, preview: false);
        } on HiwiskiFailure catch (failure) {
          // Offline, the export would silently lack what was asked for: it stops
          // and says so. An image the server no longer has is left out — it is
          // missing on the page as well.
          if (failure.isNetwork || failure.isTransient) rethrow;
        }
      }
    }
    return packExport(
      pageExportFiles(branch: branch, tagNames: tagNames, images: images),
      name: page.title,
    );
  }
}
