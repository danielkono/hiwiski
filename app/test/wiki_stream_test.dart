import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:flutter_test/flutter_test.dart';

/// On the first run the wiki screen got stuck on "loading" — the stream never emitted.
/// This test runs exactly the query behind it.
void main() {
  late HiwiskiDatabase db;

  setUp(() => db = HiwiskiDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('the empty page list emits', () async {
    final stream =
        (db.select(db.wikiPages)
              ..where((row) => row.deletedAt.isNull())
              ..orderBy([
                (row) => OrderingTerm.asc(row.position),
                (row) => OrderingTerm.asc(row.title),
              ]))
            .watch();

    expect(await stream.first, isEmpty);
  });

  // Through the stream, as the screen reads it — the original bug was in the stream,
  // and a `get()` passed regardless.
  test('a created page arrives', () async {
    final stream = (db.select(
      db.wikiPages,
    )..where((row) => row.deletedAt.isNull())).watch();
    final arrives = expectLater(
      stream,
      emitsThrough(
        predicate<List<WikiPageRow>>(
          (pages) => pages.length == 1 && pages.single.title == 'House',
        ),
      ),
    );

    await db
        .into(db.wikiPages)
        .insert(
          WikiPagesCompanion.insert(
            id: 'p1',
            ownerId: 'anna',
            title: const Value('House'),
          ),
        );

    await arrives;
  });

  test('the comment table accepts a comment', () async {
    await db
        .into(db.comments)
        .insert(
          CommentsCompanion.insert(
            id: 'c1',
            ownerId: 'anna',
            itemType: 'WIKI_PAGE',
            itemId: 'p1',
            body: const Value('Is the IP still current?'),
          ),
        );

    expect(await db.select(db.comments).get(), hasLength(1));
  });

  test('a missing table is created again on open', () async {
    // Once the wiki screen showed `no such table: wiki_pages`: the
    // database in the browser was on schema 2, the upgrade to 3 had never run — and
    // **the user could not have done anything** except uninstall the app. That is why
    // `beforeOpen` creates whatever is missing.
    //
    // Checked with a **file**, not in memory: only that way can the database be damaged
    // between two opens — and the second open is exactly what this is about.
    final file = File(
      '${Directory.systemTemp.path}/hiwiski-healing-'
      '${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(() => file.existsSync() ? file.deleteSync() : null);

    final first = HiwiskiDatabase(NativeDatabase(file));
    await first.select(first.wikiPages).get();
    // A table disappears — just as it was never created in the browser.
    await first.customStatement('DROP TABLE wiki_pages');
    await first.close();

    final second = HiwiskiDatabase(NativeDatabase(file));
    addTearDown(second.close);

    // `createAll` writes `CREATE TABLE IF NOT EXISTS` and is therefore a no-op as long as
    // everything is in place — and the rescue when something is missing.
    expect(await second.select(second.wikiPages).get(), isEmpty);
  });
}
