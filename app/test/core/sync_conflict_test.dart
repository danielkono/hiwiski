import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/wiki/wiki_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hiwiski/app/repositories.dart';

/// **A conflict is always shown, and the server state wins**.
///
/// When testing with two members, after a conflict on the wiki text the device kept
/// its own, rejected version: the pull did not bring the server state back, because the
/// other member's change had been pulled long before. From then on the device
/// permanently saw something different from everyone else.
void main() {
  late HiwiskiDatabase db;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    db = HiwiskiDatabase(NativeDatabase.memory());
    container = ProviderContainer(
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

  Future<WikiPage> page() async {
    for (final (id, parent) in [('parent', null), ('page', 'parent')]) {
      await db
          .into(db.wikiPages)
          .insert(
            WikiPagesCompanion.insert(
              id: id,
              ownerId: 'anna',
              version: const Value(3),
              parentId: Value(parent),
              title: const Value('Router'),
              content: const Value('Starting point'),
            ),
          );
    }
    return (await container
        .read(wikiRepositoryProvider)
        .watchPage('page')
        .first)!;
  }

  Future<WikiPageRow> reload() => (db.select(
    db.wikiPages,
  )..where((row) => row.id.equals('page'))).getSingle();

  /// Anna saves on version 3, Ben was faster: the server rejects `content`.
  Future<void> conflictOnContent() async {
    await container
        .read(wikiRepositoryProvider)
        .updatePage(await page(), content: "Anna's version");
    final entry = (await db.select(db.outboxEntries).get()).single;
    expect(entry.baseVersion, equals(3));

    await container
        .read(syncEngineProvider)
        .applyResult(
          MutationResult(
            mutationId: entry.mutationId,
            status: .conflict,
            entityId: 'page',
            version: 5,
            conflictFields: const ['content'],
            serverFields: const {'content': "Ben's version"},
            baseFields: const {'content': 'Starting point'},
          ),
        );
  }

  test('after a conflict the server state is stored locally', () async {
    await conflictOnContent();

    final row = await reload();
    expect(row.content, equals("Ben's version"));
    expect(row.version, equals(5));
    // Only the rejected field: the container stays where it was.
    expect(row.parentId, equals('parent'));
    expect(row.title, equals('Router'));
    expect(await db.select(db.outboxEntries).get(), isEmpty);
  });

  test('your own version stays visible as a conflict', () async {
    await conflictOnContent();

    final conflict = (await db.select(db.conflicts).get()).single;
    expect(conflict.entityType, equals('WIKI_PAGE'));
    expect(conflict.field, equals('content'));
    expect(jsonDecode(conflict.mine!), equals("Anna's version"));
    expect(jsonDecode(conflict.theirs!), equals("Ben's version"));
    // What both started from — the conflict view shows all three.
    expect(jsonDecode(conflict.base!), equals('Starting point'));
  });

  test(
    '"apply anyway" sends your own version on top of the new state',
    () async {
      await conflictOnContent();
      final conflict = (await db.select(db.conflicts).get()).single;

      await container.read(syncEngineProvider).takeMine(conflict);

      final row = await reload();
      expect(row.content, equals("Anna's version"));
      expect(row.parentId, equals('parent'));
      final entry = (await db.select(db.outboxEntries).get()).single;
      // On the version the conflict delivered — otherwise it would run into a conflict again.
      expect(entry.baseVersion, equals(5));
      expect(jsonDecode(entry.fields), equals({'content': "Anna's version"}));
      expect(await db.select(db.conflicts).get(), isEmpty);
    },
  );

  test('discarding keeps the server state and clears the conflict', () async {
    await conflictOnContent();
    final conflict = (await db.select(db.conflicts).get()).single;

    await container.read(syncEngineProvider).dismissConflict(conflict);

    expect((await reload()).content, equals("Ben's version"));
    expect(await db.select(db.conflicts).get(), isEmpty);
    expect(await db.select(db.outboxEntries).get(), isEmpty);
  });
}
