import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/todo/todo_items.dart';
import 'package:hiwiski/domain/transfer/front_matter.dart';
import 'package:hiwiski/domain/transfer/list_markdown.dart';
import 'package:hiwiski/domain/transfer/page_markdown.dart';
import 'package:hiwiski/domain/transfer/transfer_bundle.dart';
import 'package:hiwiski/domain/transfer/transfer_models.dart';
import 'package:hiwiski/domain/wiki/wiki_page.dart';

/// **What an export writes, an import reads back** — and what a person wrote by hand
/// in another editor is read as well.
void main() {
  TransferFile md(String path, String text) => .new(path, utf8.encode(text));

  final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

  WikiPage page(
    String id,
    String title, {
    String? parentId,
    String content = '',
    String kind = 'PAGE',
    int position = 0,
    String tags = '',
    String properties = '{}',
    DateTime? archivedAt,
  }) => .new(
    id: id,
    ownerId: 'anna',
    version: 1,
    parentId: parentId,
    position: position,
    kind: kind,
    title: title,
    content: content,
    tags: tags,
    properties: properties,
    archivedAt: archivedAt,
  );

  group('front matter', () {
    test('texts YAML would read as something else come back as texts', () {
      final written = writeFrontMatter({
        'title': 'Yes: no — "maybe" #1',
        'flag': 'true',
        'number': '12',
        'date': '2026-12-01',
        'empty': '',
        'left_out': null,
        'nested': {
          'servings': 4,
          'ingredients': [
            {'label': 'Mehl, Type 405', 'amount': 250.0, 'unit': 'g'},
          ],
        },
      });
      final (:fields, :body) = splitFrontMatter('$written\nText');

      expect(fields['title'], equals('Yes: no — "maybe" #1'));
      expect(fields['flag'], equals('true'));
      expect(fields['number'], equals('12'));
      expect(fields['date'], equals('2026-12-01'));
      expect(fields['empty'], equals(''));
      expect(fields.containsKey('left_out'), isFalse);
      expect(
        fields['nested'],
        equals({
          'servings': 4,
          'ingredients': [
            {'label': 'Mehl, Type 405', 'amount': 250, 'unit': 'g'},
          ],
        }),
      );
      expect(body, equals('Text'));
    });

    test('a text that only starts with a rule is all text', () {
      final (:fields, :body) = splitFrontMatter('---\nNot: [yaml\n---\nrest');
      expect(fields, isEmpty);
      expect(body, startsWith('---'));
    });

    test('Windows line ends and a byte order mark are read', () {
      final (:fields, :body) = splitFrontMatter(
        '\u{FEFF}---\r\ntitle: Router\r\n---\r\n\r\nText\r\n',
      );
      expect(fields['title'], equals('Router'));
      expect(body, equals('Text\n'));
    });
  });

  group('a list', () {
    test('comes back with everything its tasks have', () {
      final list = TransferList(
        name: 'Wocheneinkauf: Markt',
        kind: 'SHOPPING',
        description: 'Samstags.\n\nNicht vergessen: Taschen.',
        colorToken: 'GREEN',
        tags: const ['Haushalt'],
        tasks: [
          const TransferTask(title: 'Milch', amount: 2, unit: 'l'),
          const TransferTask(title: 'Brot', done: true, amount: 1.5),
          TransferTask(
            title: 'Müll rausbringen',
            description: '- due_date: this is text\n\nSecond paragraph.',
            dueDate: DateTime(2026, 12),
            dueTime: '18:00',
            rrule: 'FREQ=WEEKLY;BYDAY=MO',
            tags: const ['Haushalt', 'Eilig'],
          ),
          const TransferTask(title: 'Zuletzt'),
        ],
      );

      final read = parseList(listMarkdown(list), fallbackName: 'file');

      expect(read.name, equals(list.name));
      expect(read.kind, equals('SHOPPING'));
      expect(read.description, equals(list.description));
      expect(read.colorToken, equals('GREEN'));
      expect(read.tags, equals(['Haushalt']));
      expect(
        read.tasks.map((task) => task.title),
        equals(['Milch', 'Brot', 'Müll rausbringen', 'Zuletzt']),
      );
      expect(read.tasks[0].amount, equals(2));
      expect(read.tasks[0].unit, equals('l'));
      expect(read.tasks[1].done, isTrue);
      expect(read.tasks[1].amount, equals(1.5));
      final chore = read.tasks[2];
      expect(chore.description, equals(list.tasks[2].description));
      expect(chore.dueDate, equals(DateTime(2026, 12)));
      expect(chore.dueTime, equals('18:00'));
      expect(chore.rrule, equals('FREQ=WEEKLY;BYDAY=MO'));
      expect(chore.tags, equals(['Haushalt', 'Eilig']));
      expect(read.tasks[3].description, isNull);
    });

    test('a board keeps its columns and where each card stands', () {
      const list = TransferList(
        name: 'Umbau',
        kind: 'KANBAN',
        columns: [
          TransferColumn(name: 'Offen', colorToken: 'BLUE', done: false),
          TransferColumn(name: 'In Arbeit', colorToken: 'OCHRE', done: false),
          TransferColumn(name: 'Fertig', colorToken: 'GREEN', done: true),
        ],
        tasks: [
          TransferTask(title: 'Streichen', column: 0),
          TransferTask(title: 'Boden', column: 1),
          TransferTask(title: 'Planung', done: true, column: 2),
        ],
      );

      final markdown = listMarkdown(list);
      final read = parseList(markdown, fallbackName: 'file');

      expect(markdown, contains('## In Arbeit'));
      expect(read.kind, equals('KANBAN'));
      expect(
        read.columns.map((column) => column.name),
        equals(['Offen', 'In Arbeit', 'Fertig']),
      );
      expect(read.columns[1].colorToken, equals('OCHRE'));
      expect(read.columns[2].done, isTrue);
      expect(
        read.tasks.map((task) => (task.title, task.column)),
        equals([('Streichen', 0), ('Boden', 1), ('Planung', 2)]),
      );
    });

    test('a board without usable columns is a plain list', () {
      final read = parseList(
        '---\ntype: todo_list\nkind: KANBAN\n---\n\n## Open\n\n- [ ] One\n',
        fallbackName: 'Board',
      );
      expect(read.kind, equals('STANDARD'));
      expect(read.columns, isEmpty);
      expect(read.tasks.single.title, equals('One'));
    });

    test('a task list written by hand is read', () {
      final read = parseList(
        'Für den Urlaub.\n\n'
        '- [ ] Pässe\n'
        '* [X] Tickets\n'
        '- Sonnencreme\n'
        '\tgroße Flasche\n',
        fallbackName: 'Packliste',
      );
      expect(read.name, equals('Packliste'));
      expect(read.kind, equals('STANDARD'));
      expect(read.description, equals('Für den Urlaub.'));
      expect(
        read.tasks.map((task) => (task.title, task.done)),
        equals([('Pässe', false), ('Tickets', true), ('Sonnencreme', false)]),
      );
      expect(read.tasks[2].description, equals('große Flasche'));
    });

    test('the file of a list from the database', () {
      const list = TodoList(
        id: 'l1',
        ownerId: 'anna',
        version: 1,
        name: 'Renovierung / Bad',
        kind: 'KANBAN',
        columns:
            '[{"id":"a","name":"Offen","colorToken":"BLUE","done":false},'
            '{"id":"b","name":"Fertig","colorToken":"GREEN","done":true}]',
        colorToken: 'BLUE',
        position: 0,
        assignees: 'ben',
        tags: 't1,hidden',
      );
      Todo todo(String id, String title, String status, String? columnId) =>
          .new(
            id: id,
            ownerId: 'anna',
            version: 1,
            listId: 'l1',
            title: title,
            status: status,
            columnId: columnId,
            assignees: '',
            tags: '',
            position: 0,
          );

      final file = listExportFile(
        list: list,
        todos: [
          todo('1', 'Fliesen', 'OPEN', 'a'),
          // Done in an open column: it stands in the done column, as on the board.
          todo('2', 'Angebot', 'DONE', 'a'),
        ],
        tagNames: const {'t1': 'Haus'},
      );
      final read = parseList(utf8.decode(file.bytes), fallbackName: 'x');

      expect(file.path, equals('Renovierung - Bad.md'));
      // A tag the reader cannot see is left out; assignees never leave.
      expect(read.tags, equals(['Haus']));
      expect(utf8.decode(file.bytes), isNot(contains('ben')));
      expect(
        read.tasks.map((task) => (task.title, task.column, task.done)),
        equals([('Fliesen', 0, false), ('Angebot', 1, true)]),
      );
    });
  });

  group('a page', () {
    test('its text is rewritten on the way out and back in', () {
      const content =
          'Intro with a [link](hiwiski://wiki_page/p2) and '
          '[another](hiwiski://todo/t1).\n\n'
          '![](hiwiski-image:img1)\n'
          '![](hiwiski-image:gone)\n\n'
          '```\n![](hiwiski-image:img1)\n```\n';

      final exported = exportContent(
        content,
        path: 'Haus/Router.md',
        imagePath: (id) => id == 'img1' ? 'media/img1.png' : null,
        pagePath: (id) => id == 'p2' ? 'Haus/Netz (alt).md' : null,
      );

      expect(exported, contains('[link](Netz%20%28alt%29.md)'));
      // A link to anything else stays: on its own server it still works.
      expect(exported, contains('[another](hiwiski://todo/t1)'));
      expect(exported, contains('![](../media/img1.png)'));
      // An image that did not come along is taken out, its line with it.
      expect(exported, isNot(contains('gone')));
      // Code is text.
      expect(exported, contains('```\n![](hiwiski-image:img1)\n```'));

      final imported = importContent(
        exported,
        path: '0/Haus/Router.md',
        imageId: (path) => path == '0/media/img1.png' ? 'new-img' : null,
        pageId: (path) => path == '0/Haus/Netz (alt).md' ? 'new-p2' : null,
      );

      expect(imported, contains('[link](hiwiski://wiki_page/new-p2)'));
      expect(imported, contains('![](hiwiski-image:new-img)'));
      expect(imported, contains('[another](hiwiski://todo/t1)'));
    });

    test('a path that leaves the export, or an address, is not followed', () {
      expect(resolvePath('../../etc/passwd', from: 'a.md'), isNull);
      expect(resolvePath('/etc/passwd', from: 'a.md'), isNull);
      expect(resolvePath('https://example.org/a.md', from: 'a.md'), isNull);
      expect(resolvePath('#heading', from: 'a.md'), isNull);
      expect(resolvePath('b/c.md', from: 'x/a.md'), equals('x/b/c.md'));
    });

    test('a note without front matter is a page named after its file', () {
      final read = parsePage('# Hello\n\nText', path: 'notes/My note.md');
      expect(read.title, equals('My note'));
      expect(read.kind, equals('PAGE'));
      expect(read.content, equals('# Hello\n\nText'));
    });
  });

  group('an export', () {
    final pages = [
      page('root', 'Rezepte', kind: 'RECIPE_FOLDER', tags: 't1'),
      page(
        'b',
        'Pfannkuchen',
        parentId: 'root',
        position: 2048,
        kind: 'RECIPE',
        content:
            'Siehe [Waffeln](hiwiski://wiki_page/a).\n\n'
            '![](hiwiski-image:img1)',
        properties:
            '{"servings":4,"imageId":"img2","ingredients":'
            '[{"label":"Mehl","amount":250,"unit":"g"}]}',
      ),
      page('a', 'Waffeln', parentId: 'root', position: 1024, kind: 'RECIPE'),
      page('a2', 'Waffeln', parentId: 'root', position: 3072),
      page('old', 'Alt', parentId: 'root', archivedAt: DateTime(2026)),
      page('deep', 'Tipps', parentId: 'a'),
      page('other', 'Woanders'),
    ];

    test('a branch is the page and what lies below it, in order', () {
      final branch = exportBranch(pages.first, pages, withSubpages: true);
      // Parents before children, siblings by position, the archive left out.
      expect(
        branch.map((page) => page.id),
        equals(['root', 'a', 'deep', 'b', 'a2']),
      );
      expect(
        exportBranch(pages.first, pages, withSubpages: false).single.id,
        equals('root'),
      );
      expect(branchImageIds(branch), equals({'img1', 'img2'}));
    });

    test('one page without images is one Markdown file', () {
      final file = packExport(
        pageExportFiles(
          branch: [pages[1]],
          tagNames: const {},
          images: const {},
        ),
        name: 'Pfannkuchen',
      );
      expect(file.name, equals('Pfannkuchen.md'));
      final text = utf8.decode(file.bytes);
      expect(text, startsWith('---\ntype: wiki_page\n'));
      // No image came along: neither in the text nor as the recipe's picture.
      expect(text, isNot(contains('img1')));
      expect(text, isNot(contains('imageId')));
    });

    test('a branch with images is an archive that imports as it was', () {
      final branch = exportBranch(pages.first, pages, withSubpages: true);
      final file = packExport(
        pageExportFiles(
          branch: branch,
          tagNames: const {'t1': 'Essen'},
          images: {'img1': png, 'img2': png},
        ),
        name: 'Rezepte',
      );
      expect(file.name, equals('Rezepte.zip'));
      final names = ZipDecoder()
          .decodeBytes(file.bytes)
          .files
          .map((entry) => entry.name)
          .toSet();
      expect(
        names,
        equals({
          'Rezepte.md',
          'Rezepte/Waffeln.md',
          'Rezepte/Waffeln/Tipps.md',
          'Rezepte/Pfannkuchen.md',
          // Two pages of one name next to each other are two files.
          'Rezepte/Waffeln (2).md',
          'media/img1.png',
          'media/img2.png',
        }),
      );

      final plan = readImport([
        TransferFile(file.name, file.bytes),
      ], place: .todo);

      expect(plan.skipped, isEmpty);
      expect(plan.lists, isEmpty);
      expect(plan.pageCount, equals(5));
      final root = plan.pages.single;
      expect(root.title, equals('Rezepte'));
      expect(root.kind, equals('RECIPE_FOLDER'));
      expect(root.tags, equals(['Essen']));
      expect(
        root.children.map((child) => child.title),
        equals(['Waffeln', 'Pfannkuchen', 'Waffeln']),
      );
      expect(root.children.first.children.single.title, equals('Tipps'));
      final pancakes = root.children[1];
      expect(pancakes.kind, equals('RECIPE'));
      expect(pancakes.properties['servings'], equals(4));
      expect(
        pancakes.properties['ingredients'],
        equals([
          {'label': 'Mehl', 'amount': 250, 'unit': 'g'},
        ]),
      );
      // Both images came along, found from the page that shows them.
      expect(
        plan.images.keys.toSet(),
        equals({'0/media/img1.png', '0/media/img2.png'}),
      );
      expect(
        resolvePath(
          pancakes.properties['imageId']! as String,
          from: pancakes.path,
        ),
        equals('0/media/img2.png'),
      );
      final text = importContent(
        pancakes.content,
        path: pancakes.path,
        imageId: (path) => path == '0/media/img1.png' ? 'n1' : null,
        pageId: (path) => path == root.children.first.path ? 'waffles' : null,
      );
      expect(text, contains('[Waffeln](hiwiski://wiki_page/waffles)'));
      expect(text, contains('![](hiwiski-image:n1)'));
    });
  });

  test('a mind map goes along as its picture, and comes back as a page', () {
    final file = packExport(
      pageExportFiles(
        branch: [
          page('map', 'Urlaub [Ideen]', kind: 'MINDMAP', content: 'Notizen'),
        ],
        tagNames: const {},
        images: const {},
        mindmaps: {'map': png},
      ),
      name: 'Urlaub',
    );
    final names = ZipDecoder()
        .decodeBytes(file.bytes)
        .files
        .map((entry) => entry.name)
        .toSet();
    expect(names, equals({'Urlaub [Ideen].md', 'media/map.png'}));

    final plan = readImport([
      TransferFile(file.name, file.bytes),
    ], place: .wiki);
    final imported = plan.pages.single;
    // Not a mind map again — its elements are not in the file — but a page that
    // shows it.
    expect(imported.kind, equals('PAGE'));
    expect(plan.images.keys, equals(['0/media/map.png']));
    final text = importContent(
      imported.content,
      path: imported.path,
      imageId: (path) => path == '0/media/map.png' ? 'picture' : null,
      pageId: (_) => null,
    );
    expect(text, equals('![Urlaub Ideen](hiwiski-image:picture)\n\nNotizen'));
  });

  group('an import', () {
    Uint8List zip(Map<String, List<int>> files) {
      final archive = Archive();
      for (final MapEntry(:key, :value) in files.entries) {
        archive.addFile(ArchiveFile.bytes(key, value));
      }
      return ZipEncoder().encodeBytes(archive);
    }

    test('a zipped folder of notes keeps its folders as pages', () {
      final plan = readImport([
        TransferFile(
          'vault.zip',
          zip({
            'Vault/Home.md': utf8.encode('Welcome ![x](img/a.png)'),
            'Vault/Trips/Rome.md': utf8.encode('Pasta'),
            'Vault/img/a.png': png,
            'Vault/.obsidian/app.json': utf8.encode('{}'),
            '__MACOSX/Vault/._Home.md': [0],
            'Vault/readme.txt': utf8.encode('ignored'),
          }),
        ),
      ], place: .wiki);

      expect(plan.skipped, isEmpty);
      final vault = plan.pages.single;
      expect(vault.title, equals('Vault'));
      expect(
        vault.children.map((page) => page.title),
        equals(['Home', 'Trips']),
      );
      expect(vault.children[1].children.single.title, equals('Rome'));
      expect(plan.images.keys, equals(['0/Vault/img/a.png']));
    });

    test('a file that does not say what it is follows the place', () {
      final file = md('Packliste.md', '- [ ] Pässe\n- [x] Tickets\n');

      final asList = readImport([file], place: .todo);
      expect(asList.lists.single.name, equals('Packliste'));
      expect(asList.lists.single.doneCount, equals(1));
      expect(asList.pages, isEmpty);

      final asPage = readImport([file], place: .wiki);
      expect(asPage.pages.single.title, equals('Packliste'));
      expect(asPage.lists, isEmpty);
    });

    test('a file that says what it is, is that everywhere', () {
      final plan = readImport([
        md('a.md', '---\ntype: wiki_page\ntitle: Router\n---\n\nText'),
        md('b.md', '---\ntype: todo_list\nname: Einkauf\n---\n\n- [ ] Milch'),
      ], place: .todo);
      expect(plan.pages.single.title, equals('Router'));
      expect(plan.lists.single.name, equals('Einkauf'));
    });

    test('what cannot be read is named, and the rest goes on', () {
      final plan = readImport([
        md('ok.md', '- [ ] One'),
        md('empty.md', 'No tasks here.'),
        TransferFile('broken.zip', Uint8List.fromList([1, 2, 3, 4])),
        TransferFile('photo.heic', Uint8List(4)),
        TransferFile('latin1.md', Uint8List.fromList([0x2D, 0x20, 0xE4, 0xFF])),
        md('long.md', '- [ ] x\n${'a' * 200001}'),
      ], place: .todo);

      expect(plan.lists.single.name, equals('ok'));
      expect(
        {for (final file in plan.skipped) file.path: file.reason},
        equals({
          'empty.md': SkipReason.noTasks,
          'broken.zip': SkipReason.brokenArchive,
          'photo.heic': SkipReason.unsupported,
          'latin1.md': SkipReason.notText,
          'long.md': SkipReason.tooLong,
        }),
      );
    });

    test('a path out of the archive is not unpacked', () {
      final plan = readImport([
        TransferFile(
          'evil.zip',
          zip({
            '../outside.md': utf8.encode('x'),
            '/abs.md': utf8.encode('x'),
            'fine.md': utf8.encode('x'),
          }),
        ),
      ], place: .wiki);
      expect(plan.pages.map((page) => page.title), equals(['fine']));
    });
  });

  test('a title becomes a file name every system takes', () {
    expect(fileName('Plan: A/B?'), equals('Plan- A-B-'));
    expect(fileName('  ..hidden  '), equals('hidden'));
    expect(fileName('///'), equals('---'));
    expect(fileName(' '), equals('untitled'));
    expect(fileName('x' * 200).length, equals(80));
  });
}
