import 'package:drift/native.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/sync/entity_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Only changed fields are transmitted. Not an optimization but a requirement:
/// otherwise an older app blanks out fields it does not know and deletes the work of a
/// newer device."
///
/// This also holds **locally**: an early client rewrote the whole row
/// when checking off an item, and "2 l Milch" became "2 l".
void main() {
  late HiwiskiDatabase db;

  setUp(() => db = HiwiskiDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('an upsert with one field leaves the others alone', () async {
    const codec = TodoCodec();

    await codec.upsert(
      db,
      id: 'todo-1',
      ownerId: 'anna',
      version: 1,
      containerId: 'list-1',
      entityKey: 'TD-1',
      fields: {'title': 'Milch', 'amount': 2, 'unit': 'l', 'status': 'OPEN'},
    );

    // When an item is checked off, the server sends back exactly one field.
    await codec.upsert(
      db,
      id: 'todo-1',
      ownerId: 'anna',
      version: 2,
      containerId: 'list-1',
      entityKey: 'TD-1',
      fields: {'status': 'DONE'},
    );

    final row = await (db.select(
      db.todos,
    )..where((todo) => todo.id.equals('todo-1'))).getSingle();
    expect(row.status, equals('DONE'));
    expect(
      row.title,
      equals('Milch'),
      reason: 'the title was not part of the change',
    );
    expect(row.amount, equals(2));
    expect(row.unit, equals('l'));
    expect(row.version, equals(2));
  });

  test('the readable key is not lost on a later pull', () async {
    const codec = TodoCodec();
    await codec.upsert(
      db,
      id: 'todo-1',
      ownerId: 'anna',
      version: 1,
      containerId: 'list-1',
      entityKey: 'TD-7',
      fields: {'title': 'Müll'},
    );
    // A later entry in the log no longer carries it -- it never changes.
    await codec.upsert(
      db,
      id: 'todo-1',
      ownerId: 'anna',
      version: 2,
      containerId: 'list-1',
      entityKey: null,
      fields: {'title': 'Biomüll'},
    );

    final row = await (db.select(
      db.todos,
    )..where((todo) => todo.id.equals('todo-1'))).getSingle();
    expect(row.entityKey, equals('TD-7'));
    expect(row.title, equals('Biomüll'));
  });

  test('an upsert after a deletion revives the item', () async {
    const codec = TodoListCodec();
    await codec.upsert(
      db,
      id: 'list-1',
      ownerId: 'anna',
      version: 1,
      containerId: null,
      entityKey: null,
      fields: {'name': 'Haushalt'},
    );
    await codec.markDeleted(db, 'list-1', 2);
    await codec.upsert(
      db,
      id: 'list-1',
      ownerId: 'anna',
      version: 3,
      containerId: null,
      entityKey: null,
      fields: {'name': 'Haushalt'},
    );

    final row = await (db.select(
      db.todoLists,
    )..where((list) => list.id.equals('list-1'))).getSingle();
    expect(row.deletedAt, isNull);
  });

  test('a configured tile keeps its kind', () async {
    // The configuration comes back without `kind`. The kind used to be blanked out
    // along the way, and every configured tile showed "your app version does not know
    // this".
    const codec = WidgetCodec();
    await codec.upsert(
      db,
      id: 'w-1',
      ownerId: 'anna',
      version: 1,
      containerId: 'board-1',
      entityKey: null,
      fields: {
        'kind': 'TODO_LISTS',
        'config': <String, dynamic>{},
        'gridW': 2,
        'gridH': 2,
      },
    );
    await codec.upsert(
      db,
      id: 'w-1',
      ownerId: 'anna',
      version: 2,
      containerId: null,
      entityKey: null,
      fields: {
        'config': {
          'listIds': ['a'],
        },
      },
    );

    final row = await db.select(db.widgets).getSingle();
    expect(row.kind, equals('TODO_LISTS'));
    expect(row.boardId, equals('board-1'));
    expect(row.config, equals('{"listIds":["a"]}'));
  });

  test('archiving and restoring arrive like any other field', () async {
    const codec = WikiPageCodec();
    Future<WikiPageRow> read() => (db.select(
      db.wikiPages,
    )..where((page) => page.id.equals('page-1'))).getSingle();

    await codec.upsert(
      db,
      id: 'page-1',
      ownerId: 'anna',
      version: 1,
      containerId: null,
      entityKey: 'WIKI-1',
      fields: {'title': 'Old flat', 'kind': 'PAGE'},
    );
    await codec.upsert(
      db,
      id: 'page-1',
      ownerId: 'anna',
      version: 2,
      containerId: null,
      entityKey: null,
      fields: {'archivedAt': '2026-03-12T09:30:00Z', 'archivedBy': 'anna'},
    );

    WikiPageRow page = await read();
    // The same moment: Drift hands it back in local time, and `==` on DateTime
    // also compares the zone — that only held on a machine running in UTC.
    expect(
      page.archivedAt!.isAtSameMomentAs(DateTime.utc(2026, 3, 12, 9, 30)),
      isTrue,
      reason: '${page.archivedAt}',
    );
    expect(page.archivedBy, equals('anna'));
    expect(
      page.title,
      equals('Old flat'),
      reason: 'archiving changes nothing else',
    );

    await codec.upsert(
      db,
      id: 'page-1',
      ownerId: 'anna',
      version: 3,
      containerId: null,
      entityKey: null,
      fields: {'archivedAt': null, 'archivedBy': null},
    );
    page = await read();
    expect(page.archivedAt, isNull);
    expect(page.archivedBy, isNull);
  });

  // A member's order of the lists, sorted on another device of theirs.
  test('a list order from the server lands in its table', () async {
    const codec = ListOrderCodec();

    await codec.upsert(
      db,
      id: 'anna',
      ownerId: 'anna',
      version: 3,
      containerId: null,
      entityKey: null,
      fields: {
        'listIds': ['list-2', 'list-1'],
      },
    );

    final row = await db.select(db.listOrders).getSingle();
    expect(row.listIds, equals('["list-2","list-1"]'));
    expect(row.version, equals(3));
    expect(
      entityCodecs.map((codec) => codec.entityType),
      contains('LIST_ORDER'),
    );
  });
}
