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

  test('20 brings the pinboard tables, with every column, to a device that had '
      'none', () async {
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

    for (final TableInfo<Table, Object?> table in [
      db.pinboardNodes,
      db.pinboardEdges,
    ]) {
      final columns = await db
          .customSelect('PRAGMA table_info(${table.actualTableName})')
          .get();
      expect(
        {for (final column in columns) column.read<String>('name')},
        equals({for (final column in table.$columns) column.name}),
        reason: table.actualTableName,
      );
    }
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), equals(db.schemaVersion));
    // And the snapshot fetches what the older app skipped as a type it did not know.
    expect(await db.snapshotFrom, isNotNull);
  });
}
