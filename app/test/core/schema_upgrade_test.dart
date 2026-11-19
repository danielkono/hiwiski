import 'dart:io';

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
}
