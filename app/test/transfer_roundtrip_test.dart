import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/components/export/export_view_model.dart';
import 'package:hiwiski/components/import/import_view_model.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/data/media/media_repository.dart';
import 'package:hiwiski/domain/common/item_ref.dart';
import 'package:hiwiski/domain/links/link_text.dart';
import 'package:hiwiski/domain/todo/kanban.dart';
import 'package:hiwiski/domain/transfer/transfer_bundle.dart';
import 'package:hiwiski/domain/transfer/transfer_models.dart';
import 'package:hiwiski/domain/wiki/page_images.dart';
import 'package:hiwiski/domain/wiki/wiki_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **An export imported again is the same list, the same pages** — as new items,
/// through the outbox like anything typed.
void main() {
  late HiwiskiDatabase db;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    db = HiwiskiDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      retry: noRetry,
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  Future<ExportedFile> export(
    ItemRef item, {
    bool withDone = true,
    bool withSubpages = false,
    bool withImages = false,
  }) {
    final provider = exportViewModelProvider(item);
    final held = container.listen(provider, (_, _) {});
    addTearDown(held.close);
    return container
        .read(provider.notifier)
        .export(
          withDone: withDone,
          withSubpages: withSubpages,
          withImages: withImages,
        );
  }

  Future<ImportResult> import(ExportedFile file, ImportPlace place) {
    // One source for the watch and the command: it is compared by identity.
    final source = ImportSource([
      TransferFile(file.name, file.bytes),
    ], place: place);
    final held = container.listen(importViewModelProvider(source), (_, _) {});
    addTearDown(held.close);
    return container.read(importViewModelProvider(source).notifier).take();
  }

  test('a board comes back with its columns, cards and tags', () async {
    final todo = container.read(todoRepositoryProvider);
    final tags = container.read(tagRepositoryProvider);
    final tag = await tags.createTag('Haus');
    final columns = [
      KanbanColumn.create('Offen'),
      KanbanColumn.create('Läuft', colorToken: 'OCHRE'),
      KanbanColumn.create('Fertig', colorToken: 'GREEN', done: true),
    ];
    final listId = await todo.createList(
      name: 'Umbau',
      kind: 'KANBAN',
      description: 'Bis zum Sommer.',
      colorToken: 'TEAL',
      tags: [tag],
      columns: columns,
    );
    await todo.createTodo(
      listId: listId,
      title: 'Fliesen',
      columnId: columns[1].id,
      description: 'Im Bad.',
      dueDate: DateTime(2026, 12, 24),
      tags: [tag],
    );
    await todo.createTodo(
      listId: listId,
      title: 'Angebot',
      columnId: columns[2].id,
      done: true,
    );

    final file = await export(ItemRef.todoList(listId));
    expect(file.name, equals('Umbau.md'));
    final result = await import(file, .todo);
    expect(result.lists, equals(1));
    expect(result.pages, equals(0));

    final lists = await todo.watchAllLists().first;
    final copy = lists.singleWhere((list) => list.id != listId);
    expect(copy.name, equals('Umbau'));
    expect(copy.kind, equals('KANBAN'));
    expect(copy.description, equals('Bis zum Sommer.'));
    expect(copy.colorToken, equals('TEAL'));
    // The tag is the one that was there, not a second "Haus".
    expect(copy.tags, equals(tag));
    expect(await tags.watchTags().first, hasLength(1));
    final copied = parseColumns(copy.columns);
    expect(
      copied.map((column) => (column.name, column.colorToken, column.done)),
      equals([
        ('Offen', 'BLUE', false),
        ('Läuft', 'OCHRE', false),
        ('Fertig', 'GREEN', true),
      ]),
    );
    // New columns: the copy is a board of its own.
    expect(copied.map((column) => column.id), isNot(contains(columns[1].id)));

    final cards = await todo.watchTodos(copy.id, doneLast: false).first;
    final tiles = cards.singleWhere((card) => card.title == 'Fliesen');
    expect(tiles.columnId, equals(copied[1].id));
    expect(tiles.status, equals('OPEN'));
    expect(tiles.description, equals('Im Bad.'));
    expect(tiles.dueDate, equals(DateTime(2026, 12, 24)));
    expect(tiles.tags, equals(tag));
    final offer = cards.singleWhere((card) => card.title == 'Angebot');
    expect(offer.columnId, equals(copied[2].id));
    expect(offer.status, equals('DONE'));
  });

  test('a shopping list leaves its done entries behind when asked', () async {
    final todo = container.read(todoRepositoryProvider);
    final listId = await todo.createList(name: 'Einkauf', kind: 'SHOPPING');
    await todo.createTodo(listId: listId, title: 'Milch', amount: 2, unit: 'l');
    await todo.createTodo(listId: listId, title: 'Brot', done: true);

    final file = await export(ItemRef.todoList(listId), withDone: false);
    expect(utf8.decode(file.bytes), isNot(contains('Brot')));
    await import(file, .todo);

    final copy = (await todo.watchAllLists().first).singleWhere(
      (list) => list.id != listId,
    );
    expect(copy.kind, equals('SHOPPING'));
    final entry = (await todo.watchTodos(copy.id).first).single;
    expect((entry.title, entry.amount, entry.unit), equals(('Milch', 2, 'l')));
  });

  test('a branch comes back with its tree, links, images and recipe', () async {
    final wiki = container.read(wikiRepositoryProvider);
    final media = container.read(mediaRepositoryProvider);
    final bytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 9, 9]);

    Future<WikiPage> read(String id) async =>
        (await wiki.watchPage(id).firstWhere((page) => page != null))!;

    final rootId = await wiki.createPage(
      title: 'Rezepte',
      kind: 'RECIPE_FOLDER',
    );
    final waffleId = await wiki.createPage(
      title: 'Waffeln',
      parentId: rootId,
      kind: 'RECIPE',
      position: 1024,
    );
    final pancakeId = await wiki.createPage(
      title: 'Pfannkuchen',
      parentId: rootId,
      kind: 'RECIPE',
      position: 2048,
    );
    final inText = await media.keep(
      ownerType: ImageOwnerTypes.wikiPage,
      ownerItemId: pancakeId,
      bytes: bytes,
      filename: 'a.png',
    );
    final picture = await media.keep(
      ownerType: ImageOwnerTypes.wikiPage,
      ownerItemId: pancakeId,
      bytes: bytes,
      filename: 'b.png',
    );
    await wiki.updatePage(
      await read(pancakeId),
      content:
          'Wie ${UriReference.markdown('WIKI_PAGE', waffleId, 'Waffeln')}, '
          'nur flach.\n\n${imageMarkdown(inText)}',
      properties: {
        'servings': 4,
        'imageId': picture,
        'ingredients': [
          {'label': 'Mehl', 'amount': 250, 'unit': 'g'},
        ],
      },
    );

    final file = await export(
      ItemRef.wikiPage(rootId),
      withSubpages: true,
      withImages: true,
    );
    expect(file.name, equals('Rezepte.zip'));
    final result = await import(file, .wiki);
    expect(result.pages, equals(3));

    final pages = await wiki.watchPages().first;
    final originals = {rootId, waffleId, pancakeId};
    final copies = pages.where((page) => !originals.contains(page.id)).toList();
    final root = copies.singleWhere((page) => page.parentId == null);
    expect(root.title, equals('Rezepte'));
    expect(root.kind, equals('RECIPE_FOLDER'));
    // Below the root that was there.
    expect(root.position, greaterThan((await read(rootId)).position));
    final below = copies.where((page) => page.parentId == root.id).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    expect(below.map((page) => page.title), equals(['Waffeln', 'Pfannkuchen']));

    final pancakes = below[1];
    expect(pancakes.kind, equals('RECIPE'));
    expect(pancakes.servings, equals(4));
    expect(
      jsonDecode(pancakes.ingredients),
      equals([
        {'label': 'Mehl', 'amount': 250, 'unit': 'g'},
      ]),
    );
    // The link leads to the copy of the page it led to.
    expect(pancakes.content, contains('hiwiski://wiki_page/${below[0].id})'));
    // Both images are new ones, kept on the device until the page has arrived.
    final copiedImages = imageIdsOf(pancakes.content);
    expect(copiedImages, hasLength(1));
    expect(copiedImages.single, isNot(inText));
    expect(
      await media.image(copiedImages.single, preview: false),
      equals(bytes),
    );
    expect(pancakes.imageId, isNot(picture));
    expect(await media.image(pancakes.imageId!, preview: false), equals(bytes));
  });

  test('one page alone is one file, and its images stay behind', () async {
    final wiki = container.read(wikiRepositoryProvider);
    final id = await wiki.createPage(title: 'Router');
    await wiki.createPage(title: 'Unterseite', parentId: id);
    final page = (await wiki.watchPage(id).firstWhere((row) => row != null))!;
    await wiki.updatePage(
      page,
      content: 'Das Passwort.\n\n${imageMarkdown('some-image')}',
    );

    final file = await export(ItemRef.wikiPage(id));

    expect(file.name, equals('Router.md'));
    final text = utf8.decode(file.bytes);
    expect(text, contains('Das Passwort.'));
    expect(text, isNot(contains('some-image')));
  });
}

List<String> imageIdsOf(String content) => [
  for (final segment in pageSegments(content))
    if (segment is ImageGroup) ...segment.imageIds,
];
