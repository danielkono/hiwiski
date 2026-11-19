import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/sync/entity_codec.dart';
import 'package:hiwiski/domain/common/change.dart';
import 'package:hiwiski/domain/wiki/wiki_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// **What a kind of page adds lives in its properties** (ADR 0007) — on the device as
/// on the server: each field merged in on its own, a kind this app does not know kept,
/// each change going out as a field of its own.
void main() {
  late HiwiskiDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = HiwiskiDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<Map<String, Object?>> stored(String id) async => decodeProperties(
    (await (db.select(
      db.wikiPages,
    )..where((row) => row.id.equals(id))).getSingle()).properties,
  );

  test(
    'a pulled field that is no column is a property, merged key by key',
    () async {
      const codec = WikiPageCodec();
      await codec.upsert(
        db,
        id: 'p1',
        ownerId: 'anna',
        version: 1,
        containerId: null,
        entityKey: 'REC-1',
        fields: {
          WireFields.title: 'Plov',
          WireFields.kind: 'RECIPE',
          WireFields.servings: 4,
          WireFields.sourceUrl: 'https://a.example',
        },
      );
      // Later only the servings change — the source stays.
      await codec.upsert(
        db,
        id: 'p1',
        ownerId: 'anna',
        version: 2,
        containerId: null,
        entityKey: 'REC-1',
        fields: {WireFields.servings: 6},
      );
      expect(
        await stored('p1'),
        equals({'servings': 6, 'sourceUrl': 'https://a.example'}),
      );
    },
  );

  test('a field of a kind this app does not know yet is kept', () async {
    await const WikiPageCodec().upsert(
      db,
      id: 'p2',
      ownerId: 'anna',
      version: 1,
      containerId: null,
      entityKey: 'WIKI-2',
      fields: {
        WireFields.title: 'Oma',
        WireFields.kind: 'CONTACT',
        'phone': '+49 30 123',
      },
    );
    expect(await stored('p2'), equals({'phone': '+49 30 123'}));
  });

  test(
    'an edit writes its properties into the map and each as a field',
    () async {
      final settings = await LocalSettings.open();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(settings),
          sessionAt(signedInAnna),
        ],
      );
      addTearDown(container.dispose);
      final wiki = container.read(wikiRepositoryProvider);
      final id = await wiki.createPage(title: 'Plov', kind: 'RECIPE');
      WikiPage page = (await wiki.watchPage(id).first)!;
      await wiki.updatePage(
        page,
        properties: recipeChanges(servings: const Change(4)),
      );
      page = (await wiki.watchPage(id).first)!;
      await wiki.updatePage(
        page,
        properties: recipeChanges(sourceUrl: const Change('https://a.example')),
      );

      page = (await wiki.watchPage(id).first)!;
      expect(page.servings, equals(4));
      expect(page.sourceUrl, equals('https://a.example'));

      final sent = [
        for (final entry in await db.select(db.outboxEntries).get())
          jsonDecode(entry.fields) as Map,
      ];
      expect(sent, contains(equals({WireFields.servings: 4})));
      expect(
        sent,
        contains(equals({WireFields.sourceUrl: 'https://a.example'})),
      );
    },
  );
}
