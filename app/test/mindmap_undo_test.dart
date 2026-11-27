import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/sync/local_writes.dart';
import 'package:hiwiski/core/sync/outbox.dart';
import 'package:hiwiski/core/sync/sync_engine.dart';
import 'package:hiwiski/data/wiki/mindmap_repository.dart';
import 'package:hiwiski/domain/common/change.dart';
import 'package:hiwiski/domain/wiki/mindmap.dart';
import 'package:hiwiski/features/wiki/mindmap/mindmap_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// "Undo" takes a change made on the map back, "Redo" does it again — each written
/// as any change is, so it syncs and conflicts like one.
void main() {
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
        mindmapRepositoryProvider.overrideWith(
          (ref) => _GatedMaps(
            db: db,
            writes: ref.watch(localWritesProvider),
            currentMemberId: () => 'anna',
          ),
        ),
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

  MindmapViewModel viewModel() =>
      container.read(mindmapViewModelProvider(pageId).notifier);

  Future<MindmapState> state() async {
    // Settled: the map's stream has delivered what was written.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final Future<MindmapState?> loaded = container.read(
      mindmapViewModelProvider(pageId).future,
    );
    return (await loaded)!;
  }

  Future<String> place(String text, {int x = 0}) => viewModel().addNode(
    kind: MindmapKinds.plain,
    at: (x: x, y: 0),
    size: (width: 100, height: 40),
    text: text,
  );

  test(
    'a new element of a kind takes the size the last one was given',
    () async {
      container.listen(mindmapViewModelProvider(pageId), (_, _) {});
      Future<String> note(int width, int height) => viewModel().addNode(
        kind: MindmapKinds.note,
        at: (x: 0, y: 0),
        size: (width: width, height: height),
        text: 'Notiz',
      );
      // Before any: none for notes; snippets are sized by their text, never.
      expect((await state()).lastSizes[MindmapKinds.note], isNull);
      await place('Meer');
      expect((await state()).lastSizes[MindmapKinds.plain], isNull);

      final first = await note(300, 200);
      expect(
        (await state()).lastSizes[MindmapKinds.note],
        equals((width: 300, height: 200)),
      );
      await viewModel().resize(
        (await state()).map.node(first)!,
        width: 180,
        height: 120,
      );
      expect(
        (await state()).lastSizes[MindmapKinds.note],
        equals((width: 180, height: 120)),
      );
    },
  );

  test('a group lined up is one step back and forth', () async {
    container.listen(mindmapViewModelProvider(pageId), (_, _) {});
    final a = await place('Meer');
    final b = await place('Berge', x: 300);
    final map = (await state()).map;
    final meer = map.node(a)!;
    final berge = map.node(b)!;

    await viewModel().arrange({
      meer: meer.changed(y: 50, height: 80),
      berge: berge.changed(x: 0, y: 50),
    });
    Mindmap now = (await state()).map;
    expect(now.node(a)!.bounds, equals(const Rect.fromLTWH(0, 50, 100, 80)));
    expect(now.node(b)!.bounds, equals(const Rect.fromLTWH(0, 50, 100, 40)));

    await viewModel().undo();
    now = (await state()).map;
    expect(now.node(a)!.bounds, equals(const Rect.fromLTWH(0, 0, 100, 40)));
    expect(now.node(b)!.bounds, equals(const Rect.fromLTWH(300, 0, 100, 40)));

    await viewModel().redo();
    now = (await state()).map;
    expect(now.node(a)!.bounds, equals(const Rect.fromLTWH(0, 50, 100, 80)));
    expect(now.node(b)!.x, equals(0));
  });

  test('a move is taken back and done again', () async {
    container.listen(mindmapViewModelProvider(pageId), (_, _) {});
    final id = await place('Meer');
    final node = (await state()).map.node(id)!;

    await viewModel().move({node: (x: 300, y: 50)});
    expect((await state()).map.node(id)!.x, equals(300));
    expect((await state()).canUndo, isTrue);

    await viewModel().undo();
    expect((await state()).map.node(id)!.x, equals(0));
    expect((await state()).canRedo, isTrue);

    await viewModel().redo();
    expect((await state()).map.node(id)!.x, equals(300));
  });

  test('a deleted element comes back with its connections', () async {
    container.listen(mindmapViewModelProvider(pageId), (_, _) {});
    final a = await place('Meer');
    final b = await place('Berge', x: 300);
    Mindmap map = (await state()).map;
    await viewModel().connect(map.node(a)!, map.node(b)!);
    map = (await state()).map;
    expect(map.edges, hasLength(1));

    await viewModel().delete(map.node(b)!);
    map = (await state()).map;
    expect(map.node(b), isNull);
    expect(map.edges, isEmpty);

    await viewModel().undo();
    map = (await state()).map;
    expect(map.node(b)?.text, equals('Berge'));
    expect(map.edges, hasLength(1));
  });

  test('elements brought back go out before their connection', () async {
    container.listen(mindmapViewModelProvider(pageId), (_, _) {});
    final a = await place('Meer');
    final b = await place('Berge', x: 300);
    Mindmap map = (await state()).map;
    await viewModel().connect(map.node(a)!, map.node(b)!);
    map = (await state()).map;
    await viewModel().delete(map.node(a)!);
    map = (await state()).map;
    await viewModel().delete(map.node(b)!);

    await viewModel().undo();
    await viewModel().undo();
    expect((await state()).map.edges, hasLength(1));

    // The server refuses a connection whose ends are gone: written in the same
    // moment, the elements still have to arrive first.
    final sent = [
      for (final entry in await Outbox(db).pending(limit: 100)) entry.entityId,
    ];
    final connection = (await state()).map.edges.single.id;
    expect(sent.lastIndexOf(connection), greaterThan(sent.lastIndexOf(a)));
    expect(sent.lastIndexOf(connection), greaterThan(sent.lastIndexOf(b)));
  });

  test('strokes go last first — "Undo" right after drawing too', () async {
    container.listen(mindmapViewModelProvider(pageId), (_, _) {});
    await viewModel().draw(
      const [Offset(0, 0), Offset(100, 0)],
      color: null,
      width: 4,
    );
    // Not waited for: "Undo" pressed while the stroke is still being written.
    final drawing = viewModel().draw(
      const [Offset(0, 200), Offset(100, 200)],
      color: null,
      width: 4,
    );
    final undoing = viewModel().undo();
    await drawing;
    await undoing;

    final strokes = [
      for (final node in (await state()).map.nodes)
        if (node.kind == MindmapKinds.drawing) node,
    ];
    expect(strokes.single.y, lessThan(100));
  });

  test('the thickness of a connection is set, and taken back', () async {
    container.listen(mindmapViewModelProvider(pageId), (_, _) {});
    final a = await place('Meer');
    final b = await place('Berge', x: 300);
    Mindmap map = (await state()).map;
    await viewModel().connect(map.node(a)!, map.node(b)!);
    map = (await state()).map;

    await viewModel().setEdgeWidth(map.edges.single, 6);
    expect((await state()).map.edges.single.strokeWidth, equals(6));
    await viewModel().undo();
    expect((await state()).map.edges.single.strokeWidth, isNull);
  });

  test('a swipe of the eraser comes back as one', () async {
    container.listen(mindmapViewModelProvider(pageId), (_, _) {});
    for (final y in [0.0, 100.0, 200.0]) {
      await viewModel().draw(
        [Offset(0, y), Offset(100, y)],
        color: null,
        width: 4,
      );
    }
    final drawn = (await state()).map.nodes;
    await viewModel().erase(drawn.take(2).toList());
    expect((await state()).map.nodes, hasLength(1));

    await viewModel().undo();
    expect((await state()).map.nodes, hasLength(3));
    await viewModel().redo();
    expect((await state()).map.nodes, hasLength(1));
  });

  test(
    'placing is taken back, and nothing is left to take back after',
    () async {
      container.listen(mindmapViewModelProvider(pageId), (_, _) {});
      final id = await place('Meer');

      await viewModel().undo();
      expect((await state()).map.node(id), isNull);
      expect((await state()).canUndo, isFalse);

      await viewModel().redo();
      expect((await state()).map.node(id)?.text, equals('Meer'));
    },
  );

  group('"Undo" and "Redo" write only what the step changed', () {
    // What someone else changed meanwhile: written as a pulled change would leave
    // the element — on the row, past the version the step was made on.
    Future<void> meanwhile(
      String id, {
      int? x,
      int? y,
      String? text,
      String? color,
    }) async {
      final maps = container.read(mindmapRepositoryProvider);
      await maps.changeNode(
        (await maps.node(id))!,
        x: x,
        y: y,
        text: text,
        color: color == null ? null : Change(color),
      );
    }

    test('a move taken back leaves the other axis as it is now', () async {
      container.listen(mindmapViewModelProvider(pageId), (_, _) {});
      final id = await place('Meer');
      await viewModel().move({(await state()).map.node(id)!: (x: 300, y: 0)});
      await meanwhile(id, y: 80);

      await viewModel().undo();
      expect(
        (await state()).map.node(id)!.bounds.topLeft,
        equals(const Offset(0, 80)),
      );
      await viewModel().redo();
      expect(
        (await state()).map.node(id)!.bounds.topLeft,
        equals(const Offset(300, 80)),
      );
    });

    test('a resize taken back leaves where it was moved since', () async {
      container.listen(mindmapViewModelProvider(pageId), (_, _) {});
      final id = await place('Meer');
      final node = (await state()).map.node(id)!;
      await viewModel().arrange({node: node.changed(width: 200)});
      await meanwhile(id, x: 50);

      await viewModel().undo();
      expect(
        (await state()).map.node(id)!.bounds,
        equals(const Rect.fromLTWH(50, 0, 100, 40)),
      );
    });

    test('a colour taken back leaves a text written since', () async {
      container.listen(mindmapViewModelProvider(pageId), (_, _) {});
      final id = await place('Meer');
      await viewModel().setColor((await state()).map.node(id)!, 'TEAL');
      await meanwhile(id, text: 'Strand');

      await viewModel().undo();
      final node = (await state()).map.node(id)!;
      expect(node.color, isNull);
      expect(node.text, equals('Strand'));
      await viewModel().redo();
      expect((await state()).map.node(id)!.color, equals('TEAL'));
      expect((await state()).map.node(id)!.text, equals('Strand'));
    });

    test('a connection\'s thickness taken back leaves its new label', () async {
      container.listen(mindmapViewModelProvider(pageId), (_, _) {});
      final a = await place('Meer');
      final b = await place('Berge', x: 300);
      Mindmap map = (await state()).map;
      await viewModel().connect(map.node(a)!, map.node(b)!);
      map = (await state()).map;
      await viewModel().setEdgeWidth(map.edges.single, 6);
      final maps = container.read(mindmapRepositoryProvider);
      final edge = (await maps.edge(map.edges.single.id))!;
      await maps.changeEdge(edge, text: 'oder');

      await viewModel().undo();
      final back = (await state()).map.edges.single;
      expect(back.strokeWidth, isNull);
      expect(back.text, equals('oder'));
    });

    test('one colour for a group paints over nothing else', () async {
      container.listen(mindmapViewModelProvider(pageId), (_, _) {});
      final a = await place('Meer');
      final b = await place('Berge', x: 300);
      // As the corner showed them when the colour was chosen.
      final shown = [...(await state()).map.nodes];
      await meanwhile(a, text: 'Strand');
      await meanwhile(b, color: 'RUST');

      await viewModel().setColors(shown, 'TEAL');
      Mindmap map = (await state()).map;
      expect(map.node(a)!.text, equals('Strand'));
      expect(map.node(a)!.color, equals('TEAL'));
      expect(map.node(b)!.color, equals('TEAL'));
      final [..., painted] = await (db.select(
        db.outboxEntries,
      )..where((row) => row.entityId.equals(a))).get();
      expect(jsonDecode(painted.fields), equals({WireFields.color: 'TEAL'}));

      await meanwhile(b, text: 'Gipfel');
      await viewModel().undo();
      map = (await state()).map;
      // Each the colour it had when painted, and what was written since stays.
      expect(map.node(a)!.color, isNull);
      expect(map.node(a)!.text, equals('Strand'));
      expect(map.node(b)!.color, equals('RUST'));
      expect(map.node(b)!.text, equals('Gipfel'));
    });
  });

  group('what a delete took is brought back as it was when taken', () {
    Future<void> rewrite(String id, String text) async {
      final maps = container.read(mindmapRepositoryProvider);
      await maps.changeNode((await maps.node(id))!, text: text);
    }

    test('not as the screen last showed it', () async {
      container.listen(mindmapViewModelProvider(pageId), (_, _) {});
      final id = await place('Meer');
      final shown = (await state()).map.node(id)!;
      await rewrite(id, 'Strand');

      await viewModel().deleteAll([shown]);
      await viewModel().undo();
      expect((await state()).map.node(id)?.text, equals('Strand'));
    });

    test('as "Redo" took it again, with what came since', () async {
      container.listen(mindmapViewModelProvider(pageId), (_, _) {});
      final a = await place('Meer');
      final b = await place('Berge', x: 300);
      await viewModel().deleteAll([(await state()).map.node(a)!]);
      await viewModel().undo();
      // Meanwhile, outside this screen's steps: a new text, a new connection.
      await rewrite(a, 'Strand');
      final map = (await state()).map;
      await container
          .read(mindmapRepositoryProvider)
          .connect(map.node(a)!, map.node(b)!);

      await viewModel().redo();
      expect((await state()).map.node(a), isNull);
      await viewModel().undo();
      final back = (await state()).map;
      expect(back.node(a)?.text, equals('Strand'));
      expect(back.edges, hasLength(1));
    });

    test('a connection between two taken goes out once', () async {
      container.listen(mindmapViewModelProvider(pageId), (_, _) {});
      final a = await place('Meer');
      final b = await place('Berge', x: 300);
      Mindmap map = (await state()).map;
      await viewModel().connect(map.node(a)!, map.node(b)!);
      map = (await state()).map;
      final edge = map.edges.single.id;

      await viewModel().deleteAll([map.node(a)!, map.node(b)!]);
      await viewModel().undo();
      expect((await state()).map.edges, hasLength(1));
      final entries = await (db.select(
        db.outboxEntries,
      )..where((row) => row.entityId.equals(edge))).get();
      // Made, and brought back.
      expect(entries, hasLength(2));
    });
  });

  test(
    'a move waiting for its turn is written after the screen closed',
    () async {
      final watching = container.listen(
        mindmapViewModelProvider(pageId),
        (_, _) {},
      );
      final id = await place('Meer');
      final node = (await state()).map.node(id)!;
      final gate = Completer<void>();
      (container.read(mindmapRepositoryProvider) as _GatedMaps).gate = gate;

      // The first move takes its time; the second waits for it.
      final first = viewModel().move({node: (x: 100, y: 0)});
      final second = viewModel().move({node: (x: 300, y: 0)});
      // The screen closes, and its ViewModel goes with it.
      watching.close();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete();
      await first;
      await second;

      final maps = container.read(mindmapRepositoryProvider);
      expect((await maps.node(id))!.x, equals(300));
    },
  );

  group(
    'a step that fails to be taken back or done again stays where it was',
    () {
      test('"Undo"', () async {
        container.listen(mindmapViewModelProvider(pageId), (_, _) {});
        final id = await place('Meer');
        await viewModel().move({(await state()).map.node(id)!: (x: 300, y: 0)});
        final maps = container.read(mindmapRepositoryProvider) as _GatedMaps;

        maps.failNext = true;
        await expectLater(viewModel().undo(), throwsStateError);
        final shown = await state();
        expect(shown.map.node(id)!.x, equals(300));
        expect(shown.canRedo, isFalse);

        // Tried again, it is the move that is taken back — not the placing before it.
        await viewModel().undo();
        expect((await state()).map.node(id)?.x, equals(0));
      });

      test('"Redo"', () async {
        container.listen(mindmapViewModelProvider(pageId), (_, _) {});
        final id = await place('Meer');
        await viewModel().move({(await state()).map.node(id)!: (x: 300, y: 0)});
        await viewModel().undo();
        final maps = container.read(mindmapRepositoryProvider) as _GatedMaps;

        maps.failNext = true;
        await expectLater(viewModel().redo(), throwsStateError);
        expect((await state()).map.node(id)!.x, equals(0));
        expect((await state()).canRedo, isTrue);

        await viewModel().redo();
        expect((await state()).map.node(id)!.x, equals(300));
      });
    },
  );

  test('a link shown with its content grows to room for it', () async {
    container.listen(mindmapViewModelProvider(pageId), (_, _) {});
    final id = await viewModel().addNode(
      kind: MindmapKinds.link,
      at: (x: 0, y: 0),
      size: (width: 240, height: 56),
      target: 'hiwiski://wiki_page/$pageId',
    );
    final node = (await state()).map.node(id)!;

    await viewModel().setLinkView(
      node,
      MindmapLinkViews.content,
      room: (width: 360, height: 420),
    );

    final shown = (await state()).map.node(id)!;
    expect(shown.showsContent, isTrue);
    expect(shown.width, equals(360));
    expect(shown.height, equals(420));
  });
}

/// The repository, with a gate a test can close in front of the next move — a
/// write that takes its time.
class _GatedMaps extends MindmapRepository {
  _GatedMaps({
    required super.db,
    required super.writes,
    required super.currentMemberId,
  });

  Completer<void>? gate;

  /// Whether the next arrangement fails — a write that does not get through.
  bool failNext = false;

  @override
  Future<void> arrangeNodes(
    Map<MindmapNode, ({int x, int y, int width, int height})> places,
  ) async {
    if (failNext) {
      failNext = false;
      throw StateError('The database is gone.');
    }
    await super.arrangeNodes(places);
  }

  @override
  Future<void> moveNodes(Map<MindmapNode, ({int x, int y})> moves) async {
    final closed = gate;
    gate = null;
    await closed?.future;
    await super.moveNodes(moves);
  }
}

class _NoSync implements SyncTrigger {
  @override
  Future<void> syncNow() async {}
}
