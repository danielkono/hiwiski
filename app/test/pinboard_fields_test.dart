import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/sync/entity_codec.dart';
import 'package:hiwiski/core/sync/local_writes.dart';
import 'package:hiwiski/core/sync/outbox.dart';
import 'package:hiwiski/core/sync/sync_engine.dart';
import 'package:hiwiski/core/ui/history_field_label.dart';
import 'package:hiwiski/domain/sync/sync_items.dart';
import 'package:hiwiski/domain/wiki/pinboard.dart';
import 'package:hiwiski/features/wiki/pinboard/pinboard_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';

import 'support/fakes.dart';

/// **Every field of an element and of a connection goes the whole way**: what the
/// contract names arrives in the local database, is read from it, goes out again
/// whole, tells two versions apart, is changed on the map and taken back with "Undo",
/// is taken as this device's in a conflict and has a name in the history.
///
/// The fields come from the contract, not from a list here: one added there and
/// forgotten anywhere on the way fails this test, field by field.
void main() {
  final spec = loadYaml(
    File('../api/openapi.bundled.yaml').readAsStringSync(),
  ) as YamlMap;
  Map<String, YamlMap> fieldsOf(String schema) => {
    for (final MapEntry(:key, :value)
        in ((((spec['components'] as YamlMap)['schemas'] as YamlMap)[schema]
                    as YamlMap)['properties']
                as YamlMap)
            .entries)
      key as String: value as YamlMap,
  };
  final nodeFields = fieldsOf('PinboardNodeFields');
  final edgeFields = fieldsOf('PinboardEdgeFields');

  /// A value [field] may have by the contract — another one with [other], so that
  /// every field can be told from itself.
  Object sampleOf(String name, YamlMap field, {bool other = false}) =>
      switch (field['type']) {
        'integer' => switch ((field['minimum'], field['maximum'])) {
          (final num least?, final num most?) =>
            (least + (other ? 5 : 3)).clamp(least, most).toInt(),
          (final num least?, null) => least.toInt() + (other ? 5 : 3),
          _ => other ? 50 : 30,
        },
        'number' => other ? 7.5 : 3.25,
        _ => '${other ? 'OTHER' : 'SAMPLE'}_${name.toUpperCase()}',
      };

  Map<String, Object> samples(Map<String, YamlMap> fields) => {
    for (final MapEntry(:key, :value) in fields.entries)
      key: sampleOf(key, value),
  };

  test('the contract names the fields this test goes through', () {
    // Read wrong, the tests below would pass on nothing.
    expect(
      nodeFields.keys,
      containsAll([WireFields.kind, WireFields.x, WireFields.textFlow]),
    );
    expect(
      edgeFields.keys,
      containsAll([WireFields.fromId, WireFields.arrows]),
    );
  });

  test(
    'an element and a connection name each field in their history',
    () async {
      final l = await L.delegate.load(const Locale('en'));
      for (final name in {...nodeFields.keys, ...edgeFields.keys}) {
        expect(historyFieldLabel(l, name), isNot(equals(name)), reason: name);
      }
    },
  );

  group('through the local database,', () {
    late HiwiskiDatabase db;
    late ProviderContainer container;
    late String pageId;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = HiwiskiDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        retry: noRetry,
        overrides: [
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(await LocalSettings.open()),
          sessionAt(signedInAnna),
          localWritesProvider.overrideWith(
            (ref) => LocalWrites(db: db, outbox: Outbox(db), sync: _NoSync()),
          ),
        ],
      );
      pageId = await container
          .read(wikiRepositoryProvider)
          .createPage(title: 'Urlaub', kind: PageKinds.pinboard);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<void> arrive(
      EntityCodec codec,
      String id,
      Map<String, Object> fields,
    ) => codec.upsert(
      db,
      id: id,
      ownerId: 'anna',
      version: 1,
      containerId: pageId,
      entityKey: null,
      fields: fields,
    );

    Future<Map<String, dynamic>> lastSent(String id) async {
      final entries = await (db.select(
        db.outboxEntries,
      )..where((row) => row.entityId.equals(id))).get();
      return jsonDecode(entries.last.fields) as Map<String, dynamic>;
    }

    group('an element', () {
      const codec = PinboardNodeCodec();
      const id = 'element';

      Future<PinboardNode> read() async =>
          (await container.read(pinboardRepositoryProvider).node(id))!;

      /// The element as it arrived with every field at its sample, and then with
      /// [name] alone at another value.
      Future<(PinboardNode, PinboardNode)> twoVersions(String name) async {
        await arrive(codec, id, samples(nodeFields));
        final before = await read();
        await arrive(codec, id, {
          name: sampleOf(name, nodeFields[name]!, other: true),
        });
        return (before, await read());
      }

      test('arrives with every field and is kept with each', () async {
        final sent = samples(nodeFields);
        await arrive(codec, id, sent);
        final stored = (await codec.stored(db, id))!.fields;
        for (final name in nodeFields.keys) {
          expect(stored[name], equals(sent[name]), reason: name);
        }
      });

      test('brought back, goes out with every field', () async {
        final sent = samples(nodeFields);
        await arrive(codec, id, sent);
        await container
            .read(pinboardRepositoryProvider)
            .restore(nodes: [await read()]);
        final out = await lastSent(id);
        for (final name in nodeFields.keys) {
          expect(out[name], equals(sent[name]), reason: name);
        }
      });

      // Its kind is what it is: written with the element, and never changed.
      const setOnce = {WireFields.kind};

      test(
        'differs in each field, and a change writes just that field',
        () async {
          for (final name in nodeFields.keys) {
            final (before, after) = await twoVersions(name);
            expect(after, isNot(equals(before)), reason: name);
            expect(
              after.hashCode,
              isNot(equals(before.hashCode)),
              reason: name,
            );
            expect(
              before.fieldsChangedTo(after),
              equals(setOnce.contains(name) ? <String>{} : {name}),
              reason: name,
            );
          }
        },
      );

      test(
        'lost in a conflict, is drawn with this device\'s value of each field',
        () async {
          for (final name in nodeFields.keys) {
            final (map, mine) = await twoVersions(name);
            final conflict = SyncConflict(
              id: 'c-$name',
              entityType: EntityTypes.pinboardNode,
              entityId: id,
              field: name,
              mine: jsonEncode(sampleOf(name, nodeFields[name]!, other: true)),
              detectedAt: DateTime(2026),
            );
            expect(mineOf(map, [conflict]), equals(mine), reason: name);
          }
        },
      );
    });

    PinboardViewModel viewModel() {
      container.listen(pinboardViewModelProvider(pageId), (_, _) {});
      return container.read(pinboardViewModelProvider(pageId).notifier);
    }

    test(
      'an element\'s each field, changed, is taken back and done again',
      () async {
        const codec = PinboardNodeCodec();
        const id = 'element';
        final maps = container.read(pinboardRepositoryProvider);
        Future<Object?> stored(String name) async =>
            (await maps.node(id))!.fields[name];
        for (final name in nodeFields.keys) {
          if (name == WireFields.kind) continue;
          final field = nodeFields[name]!;
          await arrive(codec, id, samples(nodeFields));
          final other = sampleOf(name, field, other: true);
          await viewModel().setFields((await maps.node(id))!, {name: other});
          expect(await stored(name), equals(other), reason: name);
          await viewModel().undo();
          expect(
            await stored(name),
            equals(sampleOf(name, field)),
            reason: name,
          );
          await viewModel().redo();
          expect(await stored(name), equals(other), reason: name);
        }
      },
    );

    test(
      'a connection\'s each field, changed, is taken back and done again',
      () async {
        const codec = PinboardEdgeCodec();
        const id = 'connection';
        final maps = container.read(pinboardRepositoryProvider);
        Future<Object?> stored(String name) async =>
            (await maps.edge(id))!.fields[name];
        for (final name in edgeFields.keys) {
          // A connection joins the two it was drawn between.
          if (name == WireFields.fromId || name == WireFields.toId) continue;
          final field = edgeFields[name]!;
          await arrive(codec, id, samples(edgeFields));
          final other = sampleOf(name, field, other: true);
          await viewModel().setEdgeFields((await maps.edge(id))!, {
            name: other,
          });
          expect(await stored(name), equals(other), reason: name);
          await viewModel().undo();
          expect(
            await stored(name),
            equals(sampleOf(name, field)),
            reason: name,
          );
          await viewModel().redo();
          expect(await stored(name), equals(other), reason: name);
        }
      },
    );

    group('a connection', () {
      const codec = PinboardEdgeCodec();
      const id = 'connection';

      Future<PinboardEdge> read() async =>
          (await container.read(pinboardRepositoryProvider).edge(id))!;

      test('arrives with every field and is kept with each', () async {
        final sent = samples(edgeFields);
        await arrive(codec, id, sent);
        final stored = (await codec.stored(db, id))!.fields;
        for (final name in edgeFields.keys) {
          expect(stored[name], equals(sent[name]), reason: name);
        }
      });

      test('brought back, goes out with every field', () async {
        final sent = samples(edgeFields);
        await arrive(codec, id, sent);
        await container
            .read(pinboardRepositoryProvider)
            .restore(edges: [await read()]);
        final out = await lastSent(id);
        for (final name in edgeFields.keys) {
          expect(out[name], equals(sent[name]), reason: name);
        }
      });

      test('differs in each field', () async {
        for (final name in edgeFields.keys) {
          await arrive(codec, id, samples(edgeFields));
          final before = await read();
          await arrive(codec, id, {
            name: sampleOf(name, edgeFields[name]!, other: true),
          });
          final after = await read();
          expect(after, isNot(equals(before)), reason: name);
          expect(after.hashCode, isNot(equals(before.hashCode)), reason: name);
        }
      });
    });
  });
}

class _NoSync implements SyncTrigger {
  @override
  Future<void> syncNow() async {}
}
