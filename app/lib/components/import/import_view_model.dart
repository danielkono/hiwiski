import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/repositories.dart';
import '../../core/common/command.dart';
import '../../core/common/wire.dart';
import '../../data/media/media_repository.dart';
import '../../data/tags/tag_repository.dart';
import '../../data/todo/todo_repository.dart';
import '../../data/wiki/wiki_repository.dart';
import '../../domain/common/recurrence.dart';
import '../../domain/todo/kanban.dart';
import '../../domain/transfer/page_markdown.dart';
import '../../domain/transfer/transfer_models.dart';
import '../../domain/transfer/transfer_bundle.dart';
import '../../domain/wiki/page_moves.dart';

part 'import_view_model.g.dart';

/// `take`, run by the sheet: it shows the command running and reacts to how it ended.
final takeImportMutation = Mutation<ImportResult>(
  label: 'importViewModel.take',
);

/// What an import created.
@immutable
class const ImportResult({required final int lists, required final int pages});

/// Markdown files and archives on their way in: read and checked for the preview,
/// then created as new lists and pages.
///
/// Everything is created on this device, like anything the person types — it works
/// offline and syncs later. Nothing existing is changed: an import of a list that is
/// there already is a second list.
@riverpod
class ImportViewModel extends _$ImportViewModel {
  /// What the picked files hold. Read once per pick: [ImportSource] is compared by
  /// identity.
  @override
  ImportPlan build(ImportSource source) =>
      readImport(source.files, place: source.place);

  /// Creates everything in the preview and says how much that was.
  @command
  Future<ImportResult> take() async {
    // All taken before the first wait: the sheet only reads this ViewModel, and it
    // may be gone before the last page is written.
    final plan = state;
    final todo = ref.read(todoRepositoryProvider);
    final wiki = ref.read(wikiRepositoryProvider);
    final media = ref.read(mediaRepositoryProvider);
    final tags = await _tagIds(ref.read(tagRepositoryProvider), plan.tagNames);

    for (final list in plan.lists) {
      await _createList(todo, list, tags);
    }

    // Below the pages already at the root, in the order they were exported in.
    final roots = (await wiki.watchPages().first)
        .where((page) => page.parentId == null)
        .map((page) => page.position);
    final end = roots.fold(-pagePositionStep, (a, b) => a > b ? a : b);
    final pageIds = <String, String>{};
    for (final (index, page) in plan.pages.indexed) {
      await _createPages(
        wiki,
        page,
        parentId: null,
        position: end + (index + 1) * pagePositionStep,
        into: pageIds,
      );
    }
    // The texts only now: a link may point to a page created after its own.
    final imageIds = <String, String>{};
    for (final page in plan.pages) {
      await _fillPages(
        wiki,
        media,
        page,
        plan: plan,
        tags: tags,
        pageIds: pageIds,
        imageIds: imageIds,
      );
    }
    return ImportResult(lists: plan.lists.length, pages: plan.pageCount);
  }
}

/// The ids of the tags called [names], by their name in lower case. A tag the
/// reader has under that name is taken; one they do not have is created.
Future<Map<String, String>> _tagIds(
  TagRepository tags,
  Set<String> names,
) async {
  if (names.isEmpty) return const {};
  final ids = {
    for (final tag in await tags.watchTags().first)
      tag.name.toLowerCase(): tag.id,
  };
  for (final name in names) {
    ids[name.toLowerCase()] ??= await tags.createTag(name);
  }
  return ids;
}

List<String> _tagsOf(List<String> names, Map<String, String> ids) => [
  ...{for (final name in names) ?ids[name.toLowerCase()]},
];

Future<void> _createList(
  TodoRepository todo,
  TransferList list,
  Map<String, String> tags,
) async {
  final columns = [
    for (final column in list.columns)
      KanbanColumn.create(
        column.name,
        colorToken: _color(column.colorToken),
        done: column.done,
      ),
  ];
  final listId = await todo.createList(
    name: list.name,
    kind: list.kind,
    description: list.description,
    colorToken: _color(list.colorToken),
    tags: _tagsOf(list.tags, tags),
    columns: columns.isEmpty ? null : columns,
  );
  for (final task in list.tasks) {
    final column = switch (task.column) {
      final index? when index < columns.length => columns[index],
      _ => null,
    };
    await todo.createTodo(
      listId: listId,
      title: task.title,
      description: task.description,
      dueDate: task.dueDate,
      dueTime: task.dueTime,
      // A rule the server would refuse held the whole list back; a card on a board
      // does not repeat at all.
      rrule: switch (task.rrule) {
        final rule? when columns.isEmpty && Recurrence.expandable(rule) => rule,
        _ => null,
      },
      amount: task.amount,
      unit: task.unit,
      tags: _tagsOf(task.tags, tags),
      columnId: column?.id,
      // On a board the column decides: a card moved below "Done" in an editor is
      // done, whatever its box still says.
      done: column?.done ?? task.done,
    );
  }
}

/// Creates [page] and the pages below it, empty, and notes each one's id by its
/// path in [into].
Future<void> _createPages(
  WikiRepository wiki,
  TransferPage page, {
  required String? parentId,
  required int position,
  required Map<String, String> into,
}) async {
  final id = await wiki.createPage(
    title: page.title,
    parentId: parentId,
    kind: page.kind,
    position: position,
  );
  into[page.path] = id;
  for (final (index, child) in page.children.indexed) {
    await _createPages(
      wiki,
      child,
      parentId: id,
      position: index * pagePositionStep,
      into: into,
    );
  }
}

/// Gives [page] and the pages below it their text, tags and properties, with the
/// images they show kept for upload and every path turned into the id it stands for.
Future<void> _fillPages(
  WikiRepository wiki,
  MediaRepository media,
  TransferPage page, {
  required ImportPlan plan,
  required Map<String, String> tags,
  required Map<String, String> pageIds,
  required Map<String, String> imageIds,
}) async {
  final id = pageIds[page.path];
  if (id == null) return;
  final picture = switch (page.properties[WireFields.imageId]) {
    final String target => resolvePath(target, from: page.path),
    _ => null,
  };
  for (final path in [
    ...imagePathsIn(page.content, path: page.path),
    ?picture,
  ]) {
    final bytes = plan.images[path];
    if (bytes == null || imageIds.containsKey(path)) continue;
    imageIds[path] = await media.keep(
      ownerType: ImageOwnerTypes.wikiPage,
      ownerItemId: id,
      bytes: bytes,
      filename: p.posix.basename(path),
    );
  }

  final content = importContent(
    page.content,
    path: page.path,
    imageId: (path) => imageIds[path],
    pageId: (path) => pageIds[path],
  );
  final properties = {...page.properties};
  // A picture that did not come along is none: its path means nothing here.
  if (properties.containsKey(WireFields.imageId)) {
    properties[WireFields.imageId] = switch (picture) {
      final path? => imageIds[path],
      null => null,
    };
  }
  final pageTags = _tagsOf(page.tags, tags);
  final row = await wiki.watchPage(id).firstWhere((row) => row != null);
  if (row != null) {
    await wiki.updatePage(
      row,
      content: content.isEmpty ? null : content,
      properties: properties,
      tags: pageTags.isEmpty ? null : pageTags,
    );
  }
  for (final child in page.children) {
    await _fillPages(
      wiki,
      media,
      child,
      plan: plan,
      tags: tags,
      pageIds: pageIds,
      imageIds: imageIds,
    );
  }
}

/// A color the app has; anything else — a file edited by hand — is the default.
String _color(String? token) =>
    _colorTokens.contains(token) ? token ?? ColorTokens.blue : ColorTokens.blue;

const _colorTokens = {
  ColorTokens.blue,
  ColorTokens.rust,
  ColorTokens.violet,
  ColorTokens.green,
  ColorTokens.pink,
  ColorTokens.ochre,
  ColorTokens.teal,
  ColorTokens.slate,
};
