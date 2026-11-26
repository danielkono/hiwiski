import 'dart:io';

import 'package:drift/drift.dart' show Table, TableInfo;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';

void main() {
  test('an upgrade fetches everything once', () async {
    final dir = await Directory.systemTemp.createTemp('hiwiski_schema');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/hiwiski.sqlite');

    // A device a schema behind that has already pulled up to 42.
    final old = HiwiskiDatabase(NativeDatabase(file));
    await old.setLastSeq(42);
    await old.customStatement('PRAGMA user_version = 18');
    await old.close();

    final db = HiwiskiDatabase(NativeDatabase(file));
    addTearDown(db.close);

    // The snapshot comes on the next pull; the log then goes on from 42.
    expect(await db.snapshotFrom, equals(42));
  });

  test('20 brings the pinboard tables to a device that had none', () async {
    final dir = await Directory.systemTemp.createTemp('hiwiski_schema');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/hiwiski.sqlite');

    // A device on 19: no tables for a pinboard's elements and connections.
    final old = HiwiskiDatabase(NativeDatabase(file));
    await old.customStatement('DROP TABLE pinboard_nodes');
    await old.customStatement('DROP TABLE pinboard_edges');
    await old.customStatement('PRAGMA user_version = 19');
    await old.close();

    final db = HiwiskiDatabase(NativeDatabase(file));
    addTearDown(db.close);

    expect(await db.select(db.pinboardNodes).get(), isEmpty);
    expect(await db.select(db.pinboardEdges).get(), isEmpty);
    // And the snapshot fetches what the older app skipped as a type it did not know.
    expect(await db.snapshotFrom, isNotNull);
  });

  test('every step from 20 on brings the columns its version added', () async {
    // What each version added to a pinboard's tables, as SQLite names them.
    const added = {
      21: ['pinboard_nodes.link_view'],
      22: ['pinboard_nodes.text_color'],
      23: ['pinboard_nodes.points', 'pinboard_nodes.stroke_width'],
      24: ['pinboard_edges.stroke_width'],
      25: ['pinboard_edges.line', 'pinboard_edges.arrows'],
      26: ['pinboard_nodes.rotation'],
      27: ['pinboard_nodes.text_align'],
      28: ['pinboard_nodes.text_flow'],
      29: ['pinboard_nodes.calendars', 'pinboard_nodes.week'],
    };
    for (int from = 20; from < 30; from++) {
      final dir = await Directory.systemTemp.createTemp('hiwiski_schema');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/hiwiski.sqlite');

      // A device on [from]: none of the columns added after it.
      final old = HiwiskiDatabase(NativeDatabase(file));
      for (final MapEntry(key: version, value: columns) in added.entries) {
        if (version <= from) continue;
        for (final column in columns) {
          final [table, name] = column.split('.');
          await old.customStatement('ALTER TABLE $table DROP COLUMN $name');
        }
      }
      await old.customStatement('PRAGMA user_version = $from');
      await old.close();

      final db = HiwiskiDatabase(NativeDatabase(file));
      // Every column the tables have now — an empty table reads without complaint
      // even where one is missing.
      for (final TableInfo<Table, Object?> table in [
        db.pinboardNodes,
        db.pinboardEdges,
      ]) {
        final columns = await db
            .customSelect('PRAGMA table_info(${table.actualTableName})')
            .get();
        expect(
          {for (final column in columns) column.read<String>('name')},
          containsAll([for (final column in table.$columns) column.name]),
          reason: 'from $from',
        );
      }
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), equals(db.schemaVersion));
      await db.close();
    }
  });

  test('25 gives a connection its line and arrow heads', () async {
    final dir = await Directory.systemTemp.createTemp('hiwiski_schema');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/hiwiski.sqlite');

    // A device on 24: connections without a line or heads of their own.
    final old = HiwiskiDatabase(NativeDatabase(file));
    await old.customStatement('ALTER TABLE pinboard_edges DROP COLUMN line');
    await old.customStatement('ALTER TABLE pinboard_edges DROP COLUMN arrows');
    // Nor did its elements turn.
    await old.customStatement(
      'ALTER TABLE pinboard_nodes DROP COLUMN rotation',
    );
    await old.customStatement('PRAGMA user_version = 24');
    await old.close();

    final db = HiwiskiDatabase(NativeDatabase(file));
    addTearDown(db.close);

    expect(await db.select(db.pinboardEdges).get(), isEmpty);
  });

  test('26 lets an element be turned', () async {
    final dir = await Directory.systemTemp.createTemp('hiwiski_schema');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/hiwiski.sqlite');

    // A device on 25: elements without a rotation.
    final old = HiwiskiDatabase(NativeDatabase(file));
    await old.customStatement(
      'ALTER TABLE pinboard_nodes DROP COLUMN rotation',
    );
    await old.customStatement('PRAGMA user_version = 25');
    await old.close();

    final db = HiwiskiDatabase(NativeDatabase(file));
    addTearDown(db.close);

    expect(await db.select(db.pinboardNodes).get(), isEmpty);
  });

  test('30 keeps a device\'s mind map, as a pinboard', () async {
    final dir = await Directory.systemTemp.createTemp('hiwiski_schema');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/hiwiski.sqlite');

    // A device on 29: a mind map with an element, a change of it waiting to go out
    // and a page made as one waiting too — by the names they had then.
    final old = HiwiskiDatabase(NativeDatabase(file));
    await old.customStatement(
      'ALTER TABLE pinboard_nodes RENAME TO mindmap_nodes',
    );
    await old.customStatement(
      'ALTER TABLE pinboard_edges RENAME TO mindmap_edges',
    );
    await old.customStatement(
      'INSERT INTO wiki_pages (id, owner_id, kind, title) '
      "VALUES ('p1', 'm1', 'MINDMAP', 'Urlaub')",
    );
    await old.customStatement(
      'INSERT INTO mindmap_nodes (id, owner_id, page_id, kind, x, y, width, '
      "height, layer, body) VALUES ('n1', 'm1', 'p1', 'NOTE', 0, 0, 100, 50, 1, "
      "'Meer')",
    );
    await old.customStatement(
      'INSERT INTO outbox_entries (mutation_id, entity_type, entity_id, op, '
      "fields, created_at) VALUES ('u1', 'MINDMAP_NODE', 'n1', 'upsert', "
      "'{\"x\":10}', 0), ('u2', 'WIKI_PAGE', 'p2', 'upsert', "
      "'{\"kind\":\"MINDMAP\"}', 0)",
    );
    await old.customStatement('PRAGMA user_version = 29');
    await old.close();

    final db = HiwiskiDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final [node] = await db.select(db.pinboardNodes).get();
    expect(node.body, equals('Meer'));
    final [page] = await db.select(db.wikiPages).get();
    expect(page.kind, equals(PageKinds.pinboard));
    final waiting = {
      for (final entry in await db.select(db.outboxEntries).get())
        entry.mutationId: entry,
    };
    expect(waiting['u1']?.entityType, equals(EntityTypes.pinboardNode));
    expect(waiting['u2']?.fields, equals('{"kind":"PINBOARD"}'));
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE name LIKE 'mindmap%'",
        )
        .get();
    expect(tables, isEmpty);
  });

  test('a step half done before is finished, not failed on', () async {
    final dir = await Directory.systemTemp.createTemp('hiwiski_schema');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/hiwiski.sqlite');

    // Stopped mid-upgrade: the newest column is there, the version still the one
    // before.
    final old = HiwiskiDatabase(NativeDatabase(file));
    await old.customStatement('PRAGMA user_version = 25');
    await old.close();

    final db = HiwiskiDatabase(NativeDatabase(file));
    addTearDown(db.close);

    expect(await db.select(db.pinboardNodes).get(), isEmpty);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), equals(db.schemaVersion));
  });
}
