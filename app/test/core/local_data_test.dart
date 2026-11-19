import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/data/session/local_data.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/sync/entity_codec.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **The data on a device belongs to exactly one member.** A family computer is
/// shared: if Ben signs in after Anna, he must not see anything of hers — and her
/// pending changes must not go to the server under his name.
void main() {
  late HiwiskiDatabase db;
  late ProviderContainer container;
  late LocalSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await LocalSettings.open();
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

  LocalData local() => .new(db: db, settings: settings);

  /// What Anna has on the device: a mirrored list, a pending change, a hidden calendar
  /// — and the catalog, which belongs to everyone.
  Future<void> annasState() async {
    await const TodoListCodec().upsert(
      db,
      id: 'anna-list',
      ownerId: 'anna',
      version: 1,
      containerId: null,
      entityKey: 'TD-1',
      fields: {'name': 'Presents for Ben', 'kind': 'STANDARD'},
    );
    await container
        .read(outboxProvider)
        .add(
          entityType: 'TODO_LIST',
          entityId: 'anna-list',
          op: 'upsert',
          fields: {'name': 'Presents for Ben'},
        );
    await db.setLastSeq(42);
    await settings.setHiddenCalendars({'anna-calendar'});
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'p-1',
            name: 'Milk',
            aisleId: const Value('aisle-dairy'),
          ),
        );
  }

  test('another member finds nothing of the previous one', () async {
    await local().claimFor(memberId: 'anna', server: 'http://hiwiski.local');
    await annasState();

    await local().claimFor(memberId: 'ben', server: 'http://hiwiski.local');

    expect(await db.select(db.todoLists).get(), isEmpty);
    // Anna's queue does not go out under Ben's session.
    expect(await db.select(db.outboxEntries).get(), isEmpty);
    expect(await db.lastSeq, equals(0));
    expect(settings.hiddenCalendars, isEmpty);
    // The catalog belongs to everyone.
    expect(await db.select(db.products).get(), hasLength(1));
    expect(await db.owner, equals('ben@http://hiwiski.local'));
  });

  test('the same member keeps everything', () async {
    await local().claimFor(memberId: 'anna', server: 'http://hiwiski.local');
    await annasState();

    await local().claimFor(memberId: 'anna', server: 'http://hiwiski.local');

    expect(await db.select(db.todoLists).get(), hasLength(1));
    expect(await db.select(db.outboxEntries).get(), hasLength(1));
    expect(await db.lastSeq, equals(42));
  });

  test('another server is another owner', () async {
    await local().claimFor(memberId: 'anna', server: 'http://hiwiski.local');
    await annasState();

    await local().claimFor(memberId: 'anna', server: 'http://grandma.example');

    expect(await db.select(db.todoLists).get(), isEmpty);
    expect(await db.select(db.outboxEntries).get(), isEmpty);
  });

  test('a database from before the separation keeps its queue', () async {
    // No owner recorded: it is unknown whom the mirror belongs to — it goes. Deleting
    // unsynced work after an update, however, would be the worst trap
    // of an offline app.
    await annasState();

    await local().claimFor(memberId: 'anna', server: 'http://hiwiski.local');

    expect(await db.select(db.todoLists).get(), isEmpty);
    expect(await db.select(db.outboxEntries).get(), hasLength(1));
    expect(await db.lastSeq, equals(0));
  });

  test('signing out clears the device', () async {
    await local().claimFor(memberId: 'anna', server: 'http://hiwiski.local');
    await annasState();

    await local().wipe();

    expect(await db.select(db.todoLists).get(), isEmpty);
    expect(await db.select(db.outboxEntries).get(), isEmpty);
    expect(await db.owner, isNull);
    expect(settings.hiddenCalendars, isEmpty);
  });

  // Sign-out while the first sync after a start still claims the data: the claim must
  // not finish after the wipe and name the member who just left as the owner again.
  test('a wipe waits for a claim under way', () async {
    final data = local();

    final claiming = data.claimFor(
      memberId: 'anna',
      server: 'http://hiwiski.test',
    );
    final wiping = data.wipe();
    await Future.wait([claiming, wiping]);

    expect(await db.owner, isNull);
  });

  // The sync's claim and the session's confirmation at once. The sync writes once
  // its claim is done; the confirmation's claim must not then discard that. Without
  // the lock (and the transaction) both read "no owner", and the second discarded
  // what the sync had written in between — held back here so it comes last.
  test(
    'a second claim does not discard what was written after the first',
    () async {
      final gated = _GatedDatabase();
      addTearDown(gated.close);
      final data = LocalData(db: gated, settings: settings);

      final sync = data.claimFor(
        memberId: 'anna',
        server: 'http://hiwiski.test',
      );
      final confirmation = data.claimFor(
        memberId: 'anna',
        server: 'http://hiwiski.test',
      );
      await sync;
      await const TodoListCodec().upsert(
        gated,
        id: 'pulled',
        ownerId: 'anna',
        version: 1,
        containerId: null,
        entityKey: null,
        fields: {'name': 'Pulled', 'kind': 'STANDARD'},
      );
      gated.release.complete();
      await confirmation;

      expect(await gated.select(gated.todoLists).get(), hasLength(1));
    },
  );
}

/// Holds the second discard back until the test releases it.
class _GatedDatabase extends HiwiskiDatabase {
  _GatedDatabase() : super(NativeDatabase.memory());

  final release = Completer<void>();
  int _discards = 0;

  @override
  Future<void> discardMirroredData() async {
    if (++_discards == 2) await release.future;
    await super.discardMirroredData();
  }
}
