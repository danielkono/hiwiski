import 'dart:io';

import 'package:drift/drift.dart' show Table, TableInfo;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('20 brings the mind map tables to a device that had none', () async {
    final dir = await Directory.systemTemp.createTemp('hiwiski_schema');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/hiwiski.sqlite');

    // A device on 19: no tables for a mind map's elements and connections.
    final old = HiwiskiDatabase(NativeDatabase(file));
    await old.customStatement('DROP TABLE mindmap_nodes');
    await old.customStatement('DROP TABLE mindmap_edges');
    await old.customStatement('PRAGMA user_version = 19');
    await old.close();

    final db = HiwiskiDatabase(NativeDatabase(file));
    addTearDown(db.close);

    expect(await db.select(db.mindmapNodes).get(), isEmpty);
    expect(await db.select(db.mindmapEdges).get(), isEmpty);
    // And the snapshot fetches what the older app skipped as a type it did not know.
    expect(await db.snapshotFrom, isNotNull);
  });

  test('every step from 20 on brings the columns its version added', () async {
    // What each version added to a mind map's tables, as SQLite names them.
    const added = {
      21: ['mindmap_nodes.link_view'],
      22: ['mindmap_nodes.text_color'],
      23: ['mindmap_nodes.points', 'mindmap_nodes.stroke_width'],
      24: ['mindmap_edges.stroke_width'],
      25: ['mindmap_edges.line', 'mindmap_edges.arrows'],
      26: ['mindmap_nodes.rotation'],
    };
    for (int from = 20; from < 26; from++) {
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
        db.mindmapNodes,
        db.mindmapEdges,
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
    await old.customStatement('ALTER TABLE mindmap_edges DROP COLUMN line');
    await old.customStatement('ALTER TABLE mindmap_edges DROP COLUMN arrows');
    // Nor did its elements turn.
    await old.customStatement('ALTER TABLE mindmap_nodes DROP COLUMN rotation');
    await old.customStatement('PRAGMA user_version = 24');
    await old.close();

    final db = HiwiskiDatabase(NativeDatabase(file));
    addTearDown(db.close);

    expect(await db.select(db.mindmapEdges).get(), isEmpty);
  });

  test('26 lets an element be turned', () async {
    final dir = await Directory.systemTemp.createTemp('hiwiski_schema');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/hiwiski.sqlite');

    // A device on 25: elements without a rotation.
    final old = HiwiskiDatabase(NativeDatabase(file));
    await old.customStatement('ALTER TABLE mindmap_nodes DROP COLUMN rotation');
    await old.customStatement('PRAGMA user_version = 25');
    await old.close();

    final db = HiwiskiDatabase(NativeDatabase(file));
    addTearDown(db.close);

    expect(await db.select(db.mindmapNodes).get(), isEmpty);
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

    expect(await db.select(db.mindmapNodes).get(), isEmpty);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), equals(db.schemaVersion));
  });
}
