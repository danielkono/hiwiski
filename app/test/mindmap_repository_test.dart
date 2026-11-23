import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/common/sync_limits.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/db/tables.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/sync/entity_codec.dart';
import 'package:hiwiski/core/sync/outbox.dart';
import 'package:hiwiski/domain/common/change.dart';
import 'package:hiwiski/domain/wiki/mindmap.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A mind map's elements and connections go through the local database and the
/// outbox like every item: each change written with its mutation, only the fields it
/// touches, in its page.
void main() {
  late HiwiskiDatabase db;
  late ProviderContainer container;
  late String pageId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = HiwiskiDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(await LocalSettings.open()),
      ],
    );
    pageId = await container
        .read(wikiRepositoryProvider)
        .createPage(title: 'Urlaub', kind: PageKinds.mindmap);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<Mindmap> map() =>
      container.read(mindmapRepositoryProvider).watchMap(pageId).first;

  Future<List<OutboxRow>> outboxOf(String id) => (db.select(
    db.outboxEntries,
  )..where((row) => row.entityId.equals(id))).get();

  Future<String> add(String text, {int x = 0}) => container
      .read(mindmapRepositoryProvider)
      .addNode(
        pageId: pageId,
        kind: MindmapKinds.plain,
        x: x,
        y: 0,
        width: 100,
        height: 40,
        text: text,
      );

  test(
    'a new element goes out in its page, above everything, after the page',
    () async {
      final first = await add('Meer');
      final second = await add('Berge', x: 200);

      final shown = await map();
      expect([
        for (final node in shown.nodes) node.text,
      ], equals(['Meer', 'Berge']));
      expect(shown.node(second)!.layer, greaterThan(shown.node(first)!.layer));

      final [entry] = await outboxOf(first);
      expect(entry.entityType, equals(EntityTypes.mindmapNode));
      expect(entry.containerType, equals(EntityTypes.wikiPage));
      expect(entry.containerId, equals(pageId));
      // On a page that is not on the server yet: not before the page.
      final [pageEntry] = await outboxOf(pageId);
      expect(entry.dependsOn, equals(pageEntry.mutationId));
      expect(jsonDecode(entry.fields), containsPair(WireFields.text, 'Meer'));
    },
  );

  test('a change sends only what it changes', () async {
    final id = await add('Meer');
    final node = (await map()).node(id)!;
    await container
        .read(mindmapRepositoryProvider)
        .changeNode(node, x: 50, y: node.y, color: const Change('#3B6939'));

    final entries = await outboxOf(id);
    expect(
      jsonDecode(entries.last.fields),
      equals({WireFields.x: 50, WireFields.color: '#3B6939'}),
    );
    final changed = (await map()).node(id)!;
    expect(changed.x, equals(50));
    expect(changed.color, equals('#3B6939'));

    // Nothing changed: nothing goes out.
    await container.read(mindmapRepositoryProvider).changeNode(changed, x: 50);
    expect(await outboxOf(id), hasLength(entries.length));
  });

  test(
    'a connection waits for its newer element and goes with either',
    () async {
      final a = await add('Meer');
      final b = await add('Berge', x: 200);
      final shown = await map();
      final edgeId = await container
          .read(mindmapRepositoryProvider)
          .connect(shown.node(a)!, shown.node(b)!);

      final [edgeEntry] = await outboxOf(edgeId);
      final [bEntry] = await outboxOf(b);
      expect(edgeEntry.dependsOn, equals(bEntry.mutationId));
      expect((await map()).edges, hasLength(1));

      await container
          .read(mindmapRepositoryProvider)
          .deleteNode(shown.node(b)!);

      final after = await map();
      expect(after.edges, isEmpty);
      // The connection follows the element: one delete goes out, the server deletes the
      // connection along with it.
      expect(await outboxOf(edgeId), hasLength(1));
      final rows = await db.select(db.mindmapEdges).get();
      expect(rows.single.deletedAt, isNotNull);
    },
  );

  group('a connection waits for an element that cannot go out yet', () {
    Future<String> connect(String a, String b) async {
      final shown = await map();
      return container
          .read(mindmapRepositoryProvider)
          .connect(shown.node(a)!, shown.node(b)!);
    }

    test(
      'the older one, held back as too long, and is let go with it',
      () async {
        final a = await add('x' * (SyncLimits.textChars + 1));
        final b = await add('Berge', x: 200);
        final edgeId = await connect(a, b);

        final [aEntry] = await outboxOf(a);
        final [edgeEntry] = await outboxOf(edgeId);
        expect(edgeEntry.dependsOn, equals(aEntry.mutationId));
        expect(edgeEntry.state, equals(OutboxStates.blocked));

        // Shortened, the element goes out — and the connection after it.
        await container
            .read(mindmapRepositoryProvider)
            .changeNode((await map()).node(a)!, text: 'Meer');
        final [released] = await outboxOf(edgeId);
        expect(released.state, equals(OutboxStates.pending));
      },
    );

    test('the older one, refused by the server', () async {
      final a = await add('Meer');
      final b = await add('Berge', x: 200);
      final [aEntry] = await outboxOf(a);
      await Outbox(db).reject(aEntry.mutationId, 'sync.invalid_field');

      final [edgeEntry] = await outboxOf(await connect(b, a));
      expect(edgeEntry.dependsOn, equals(aEntry.mutationId));
      expect(edgeEntry.state, equals(OutboxStates.blocked));
    });

    test('brought back by "Undo"', () async {
      final a = await add('Meer');
      final b = await add('Berge', x: 200);
      final edgeId = await connect(a, b);
      final maps = container.read(mindmapRepositoryProvider);
      final edge = (await maps.edge(edgeId))!;
      await maps.deleteEdge(edge);
      final [aEntry] = await outboxOf(a);
      await Outbox(db).reject(aEntry.mutationId, 'sync.invalid_field');

      await maps.restore(edges: [edge]);
      final [..., brought] = await outboxOf(edgeId);
      expect(brought.dependsOn, equals(aEntry.mutationId));
      expect(brought.state, equals(OutboxStates.blocked));
    });
  });

  test('an element is never larger than the server keeps one', () async {
    final maps = container.read(mindmapRepositoryProvider);
    final id = await maps.addNode(
      pageId: pageId,
      kind: MindmapKinds.drawing,
      x: 0,
      y: 0,
      width: 3 * mindmapMaxSize,
      height: 0,
    );
    final [made] = await outboxOf(id);
    expect(
      jsonDecode(made.fields),
      allOf(
        containsPair(WireFields.width, mindmapMaxSize),
        containsPair(WireFields.height, 1),
      ),
    );

    await maps.changeNode((await map()).node(id)!, width: 10, height: 10);
    await maps.changeNode((await map()).node(id)!, height: mindmapMaxSize + 1);
    await maps.arrangeNodes({
      (await map()).node(id)!: (
        x: 0,
        y: 0,
        width: 2 * mindmapMaxSize,
        height: 5,
      ),
    });
    final node = (await map()).node(id)!;
    expect(node.width, equals(mindmapMaxSize));
    expect(node.height, equals(5));
    final [..., resized, arranged] = await outboxOf(id);
    expect(
      jsonDecode(resized.fields),
      equals({WireFields.height: mindmapMaxSize}),
    );
    expect(
      jsonDecode(arranged.fields),
      equals({WireFields.width: mindmapMaxSize, WireFields.height: 5}),
    );
  });

  test('a deleted page takes its map along on the device', () async {
    final a = await add('Meer');
    final b = await add('Berge', x: 200);
    final shown = await map();
    await container
        .read(mindmapRepositoryProvider)
        .connect(shown.node(a)!, shown.node(b)!);
    final page = await container
        .read(wikiRepositoryProvider)
        .watchPage(pageId)
        .first;

    await container.read(wikiRepositoryProvider).deletePage(page!);

    expect(
      (await db.select(db.mindmapNodes).get()).every(
        (row) => row.deletedAt != null,
      ),
      isTrue,
    );
    expect(
      (await db.select(db.mindmapEdges).get()).every(
        (row) => row.deletedAt != null,
      ),
      isTrue,
    );
  });

  test(
    'what the server sends lands field by field; a lost share takes the map',
    () async {
      const codec = MindmapNodeCodec();
      await codec.upsert(
        db,
        id: 'n1',
        ownerId: 'ben',
        version: 7,
        containerId: pageId,
        entityKey: null,
        fields: {
          WireFields.kind: MindmapKinds.note,
          WireFields.x: 10,
          WireFields.y: 20,
          WireFields.width: 200,
          WireFields.height: 100,
          WireFields.layer: 2.5,
          WireFields.text: '# Plan',
          WireFields.color: 'TEAL',
        },
      );
      // A change carries only what changed: the rest stays.
      await codec.upsert(
        db,
        id: 'n1',
        ownerId: 'ben',
        version: 8,
        containerId: null,
        entityKey: null,
        fields: {WireFields.x: 99},
      );
      final node = (await map()).node('n1')!;
      expect(node.x, equals(99));
      expect(node.text, equals('# Plan'));
      expect(node.color, equals('TEAL'));
      expect(node.layer, equals(2.5));
      expect(node.pageId, equals(pageId));

      final stored = await codec.stored(db, 'n1');
      expect(stored!.containerId, equals(pageId));
      expect(stored.fields[WireFields.kind], equals(MindmapKinds.note));

      await const WikiPageCodec().purge(db, pageId);
      expect(await db.select(db.mindmapNodes).get(), isEmpty);
    },
  );
}
