import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/db/tables.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/wiki/wiki_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hiwiski/app/repositories.dart';

/// **What the server refuses for lack of permission does not stay on the device.**
///
/// When testing with read access only, a tag added to a page came back as "not
/// allowed" — and stayed on the page anyway, visible only on that device.
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
    await db
        .into(db.wikiPages)
        .insert(
          WikiPagesCompanion.insert(
            id: 'page',
            ownerId: 'anna',
            version: const Value(3),
            title: const Value('Router'),
          ),
        );
    return (await container
        .read(wikiRepositoryProvider)
        .watchPage('page')
        .first)!;
  }

  Future<void> reject(String code) async {
    final entry = (await db.select(db.outboxEntries).get()).single;
    await container
        .read(syncEngineProvider)
        .applyResult(
          MutationResult(
            mutationId: entry.mutationId,
            status: .rejected,
            entityId: entry.entityId,
            code: code,
          ),
        );
  }

  test(
    'a refused change asks for a snapshot, which brings the server state back',
    () async {
      await container
          .read(wikiRepositoryProvider)
          .updatePage(await page(), tags: ['tag-1']);
      expect(await db.snapshotFrom, isNull);

      await reject('access.denied');

      expect(await db.snapshotFrom, isNotNull);
    },
  );

  test('a refused new item is removed — the server never had it', () async {
    await db
        .into(db.wikiPages)
        .insert(
          WikiPagesCompanion.insert(
            id: 'new',
            ownerId: 'ben',
            title: const Value('Mine'),
          ),
        );
    await db
        .into(db.outboxEntries)
        .insert(
          OutboxEntriesCompanion.insert(
            mutationId: 'm1',
            entityType: 'WIKI_PAGE',
            entityId: 'new',
            op: 'upsert',
            fields: const Value('{"title":"Mine"}'),
            createdAt: DateTime.now(),
          ),
        );

    await reject('access.denied');

    expect(
      await (db.select(
        db.wikiPages,
      )..where((row) => row.id.equals('new'))).get(),
      isEmpty,
    );
  });

  test('"Try again" on a refused change: the server answers with the same '
      'rejection, which keeps it visible and rolls it back again', () async {
    await container
        .read(wikiRepositoryProvider)
        .updatePage(await page(), tags: ['tag-1']);
    await reject('access.denied');
    await db.finishSnapshot(0);
    final outbox = container.read(outboxProvider);

    await outbox.retryAll();
    expect(
      (await db.select(db.outboxEntries).getSingle()).state,
      equals(OutboxStates.pending),
    );
    // The resend carries the same mutation id; the server replays its answer.
    await reject('access.denied');

    final entry = (await db.select(db.outboxEntries).getSingle());
    expect(entry.state, equals(OutboxStates.rejected));
    expect(entry.errorCode, equals('access.denied'));
    expect(await outbox.watchStuck().first, hasLength(1));
    expect(await db.snapshotFrom, isNotNull);
  });

  test('other rejections leave the local state alone', () async {
    await container
        .read(wikiRepositoryProvider)
        .updatePage(await page(), title: '');

    await reject('validation.title_required');

    expect(await db.snapshotFrom, isNull);
    expect((await db.select(db.wikiPages).getSingle()).title, equals(''));
  });
}
