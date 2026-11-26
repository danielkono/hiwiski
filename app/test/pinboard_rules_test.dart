import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/domain/links/link_index.dart';
import 'package:hiwiski/domain/sync/sync_items.dart';
import 'package:hiwiski/domain/wiki/pinboard.dart';

PinboardNode node(
  String id, {
  int x = 0,
  int y = 0,
  int width = 100,
  int height = 50,
  double layer = 1,
  String kind = PinboardKinds.plain,
  String text = '',
  String? target,
  String? shape,
  int? rotation,
}) => .new(
  id: id,
  ownerId: 'anna',
  version: 1,
  pageId: 'page',
  kind: kind,
  x: x,
  y: y,
  width: width,
  height: height,
  layer: layer,
  text: text,
  target: target,
  shape: shape,
  rotation: rotation,
);

PinboardEdge edge(String id, String from, String to, {String text = ''}) =>
    .new(
      id: id,
      ownerId: 'anna',
      version: 1,
      pageId: 'page',
      fromId: from,
      toId: to,
      text: text,
    );

List<String> order(Pinboard map) => [for (final node in map.nodes) node.id];

/// The rules of a pinboard: how elements stack, where lines run, what a search finds.
void main() {
  group('stacking', () {
    test('later layers are above, a tie goes to the later id', () {
      final map = Pinboard(
        nodes: [node('c', layer: 1), node('a', layer: 2), node('b', layer: 1)],
        edges: const [],
      );
      expect(order(map), equals(['b', 'c', 'a']));
      expect(map.topLayer, equals(3));
    });

    test(
      'one step up passes the next overlapping element, not a distant one',
      () {
        final map = Pinboard(
          nodes: [
            node('me', layer: 1),
            // Far away: stepping past it would change nothing anyone sees.
            node('far', x: 1000, layer: 2),
            node('over', x: 50, layer: 3),
            node('top', x: 2000, layer: 4),
          ],
          edges: const [],
        );
        final me = map.node('me')!;
        final layer = layerUp(map, me)!;
        // Above "over", below what came after it.
        expect(layer, greaterThan(3));
        expect(layer, lessThan(4));
        final moved = Pinboard(
          nodes: [
            for (final n in map.nodes)
              n.id == 'me' ? n.changed(layer: layer) : n,
          ],
          edges: const [],
        );
        expect(order(moved), equals(['far', 'over', 'me', 'top']));
      },
    );

    test('nothing overlapping above or below: no step', () {
      final map = Pinboard(
        nodes: [node('a', layer: 1), node('b', x: 500, layer: 2)],
        edges: const [],
      );
      expect(layerUp(map, map.node('a')!), isNull);
      expect(layerDown(map, map.node('b')!), isNull);
    });

    test('one step down goes below the next overlapping element', () {
      final map = Pinboard(
        nodes: [
          node('bottom', x: 50, layer: 1),
          node('under', x: 40, layer: 2),
          node('me', layer: 3),
        ],
        edges: const [],
      );
      final layer = layerDown(map, map.node('me')!)!;
      expect(layer, greaterThan(1));
      expect(layer, lessThan(2));
    });

    test('to the front and to the back — once', () {
      final map = Pinboard(
        nodes: [node('a', layer: 1), node('b', layer: 5)],
        edges: const [],
      );
      expect(layerToFront(map, map.node('a')!), equals(6));
      expect(layerToFront(map, map.node('b')!), isNull);
      expect(layerToBack(map, map.node('b')!), equals(0));
      expect(layerToBack(map, map.node('a')!), isNull);
    });

    test('overlapping is judged as the elements are seen, turned', () {
      final map = Pinboard(
        nodes: [
          // A bar turned upright about its middle (100, 10): seen from x 90 to 110.
          node('me', width: 200, height: 20, rotation: 90),
          // Under where it lay before it was turned, clear of where it is seen.
          node('aside', width: 20, height: 20, layer: 2),
          // Over where it is seen now.
          node('over', x: 90, y: 60, width: 20, height: 20, layer: 3),
          node('top', x: 2000, layer: 4),
        ],
        edges: const [],
      );
      final layer = layerUp(map, map.node('me')!)!;
      expect(layer, greaterThan(3));
      expect(layer, lessThan(4));
      expect(layerDown(map, map.node('over')!), lessThan(1));

      // A square turned into a diamond, and one in the corner of the box around it:
      // they do not touch.
      final diamond = Pinboard(
        nodes: [
          node('diamond', width: 100, height: 100, rotation: 45),
          node('corner', x: -15, y: -15, width: 10, height: 10, layer: 2),
        ],
        edges: const [],
      );
      expect(layerUp(diamond, diamond.node('diamond')!), isNull);
    });

    test('two elements on the same layer still leave a step', () {
      final map = Pinboard(
        nodes: [node('a', layer: 1), node('b', layer: 2), node('c', layer: 2)],
        edges: const [],
      );
      final layer = layerUp(map, map.node('a')!)!;
      expect(layer, greaterThan(2));
    });
  });

  group('lines', () {
    test('run from outline to outline, on the line between the centres', () {
      final from = node('a', width: 100, height: 100);
      final to = node('b', x: 300, width: 100, height: 100);
      final (start, end) = edgeLine(from, to)!;
      expect(start, equals(const Offset(100, 50)));
      expect(end, equals(const Offset(300, 50)));
    });

    test('an ellipse is left on its curve', () {
      final from = node(
        'a',
        width: 100,
        height: 100,
        kind: PinboardKinds.note,
        shape: PinboardShapes.ellipse,
      );
      final to = node('b', x: 300, y: 300, width: 100, height: 100);
      final (start, _) = edgeLine(from, to)!;
      expect((start - from.center).distance, closeTo(50, 0.01));
    });

    test('elements lying on each other have no visible line', () {
      final from = node('a', width: 100, height: 100);
      final to = node('b', x: 10, width: 100, height: 100);
      expect(edgeLine(from, to), isNull);
    });

    test('connections whose element is gone are not drawn', () {
      final map = Pinboard(
        nodes: [node('a'), node('b', x: 300)],
        edges: [
          edge('ab', 'a', 'b'),
          edge('ax', 'a', 'x'),
          edge('aa', 'a', 'a'),
        ],
      );
      expect([for (final e in map.edges) e.id], equals(['ab']));
    });

    test(
      'two connections between the same pair bend apart, either way round',
      () {
        final map = Pinboard(
          nodes: [node('a'), node('b', x: 400)],
          edges: [edge('one', 'a', 'b'), edge('two', 'b', 'a')],
        );
        final one = edgePathOf(map, map.edge('one')!, 30)!;
        final two = edgePathOf(map, map.edge('two')!, 30)!;
        expect(one.bend.dy, isNot(two.bend.dy));
        expect((one.bend.dy - two.bend.dy).abs(), closeTo(30, 0.01));
      },
    );

    test('connections between the same pair bend alike on every device', () {
      // Listed in another order on each device, as a database may.
      final here = Pinboard(
        nodes: [node('a'), node('b', x: 400)],
        edges: [edge('one', 'a', 'b'), edge('two', 'a', 'b')],
      );
      final there = Pinboard(
        nodes: [node('a'), node('b', x: 400)],
        edges: [edge('two', 'a', 'b'), edge('one', 'a', 'b')],
      );
      for (final id in ['one', 'two']) {
        expect(
          edgePathOf(there, there.edge(id)!, 30)!.bend,
          equals(edgePathOf(here, here.edge(id)!, 30)!.bend),
        );
      }
    });

    test('a tap near a line hits it', () {
      final map = Pinboard(
        nodes: [node('a'), node('b', x: 400)],
        edges: [edge('ab', 'a', 'b')],
      );
      final path = edgePathOf(map, map.edge('ab')!, 30)!;
      expect(distanceToPath(const Offset(250, 30), path), closeTo(5, 0.01));
    });
  });

  group('search', () {
    test('finds elements and labels, by link title too, top to bottom', () {
      final map = Pinboard(
        nodes: [
          node(
            'note',
            y: 300,
            kind: PinboardKinds.note,
            text: '## Strand\nSonne',
          ),
          node('plain', y: 0, text: 'Sonnencreme'),
          node(
            'link',
            y: 100,
            kind: PinboardKinds.link,
            target: 'hiwiski://wiki_page/p1',
          ),
          node('other', y: 200, text: 'Berge'),
        ],
        edges: [edge('e', 'plain', 'other', text: 'statt Sonne')],
      );
      final hits = searchPinboard(
        map,
        'SONNE',
        titleOf: (target) => target.endsWith('p1') ? 'Sonnenschirm' : null,
      );
      expect([
        for (final hit in hits) hit.id,
      ], equals(['plain', 'link', 'e', 'note']));
      expect(hits.last.snippet, contains('Sonne'));
      // The Markdown of a note is not searched, its text is.
      expect(searchPinboard(map, '##', titleOf: (_) => null), isEmpty);
    });

    test('a match behind a lot of whitespace shows in its snippet', () {
      final map = Pinboard(
        nodes: [
          node('beach', text: 'Strand${' ' * 80}Sonne\n\nMeer'),
          node('plain', y: 100, text: 'Berge   und\n\nSonne'),
        ],
        edges: const [],
      );
      final hits = searchPinboard(map, 'sonne', titleOf: (_) => null);
      expect([
        for (final hit in hits) hit.snippet,
      ], equals(['Strand Sonne Meer', 'Berge und Sonne']));
      // What is typed with a line break or two spaces finds the words on one line.
      expect(
        searchPinboard(
          map,
          'und  sonne',
          titleOf: (_) => null,
        ).map((hit) => hit.id),
        equals(['plain']),
      );
    });

    test('an empty search finds nothing', () {
      final map = Pinboard(
        nodes: [node('a', text: 'x')],
        edges: const [],
      );
      expect(searchPinboard(map, '  ', titleOf: (_) => null), isEmpty);
    });

    test('a note reads without its Markdown', () {
      expect(
        plainOfMarkdown(
          '# Title\n- [x] **done** and [a link](hiwiski://todo/1)\n![](hiwiski-image:x)',
        ),
        equals('Title\ndone and a link'),
      );
    });
  });

  group('colours', () {
    test('a token or an own colour, as stored', () {
      expect(PinboardColor.parse('TEAL'), equals(const TokenColor('TEAL')));
      expect(PinboardColor.parse('#a1b2c3'), equals(const OwnColor(0xA1B2C3)));
      expect(const OwnColor(0x3B6939).stored, equals('#3B6939'));
      // See-through: with its alpha; covering, stored as before.
      expect(
        PinboardColor.parse('#a1b2c340'),
        equals(const OwnColor(0xA1B2C3, alpha: 0x40)),
      );
      expect(const OwnColor(0x3B6939, alpha: 0x80).stored, equals('#3B693980'));
      expect(
        const OwnColor(0x3B6939, alpha: OwnColor.opaque).stored,
        equals('#3B6939'),
      );
      expect(PinboardColor.parse(null), isNull);
      expect(PinboardColor.parse('rot'), isNull);
      expect(PinboardColor.parse('#12345'), isNull);
    });
  });

  group('links', () {
    test('the picker\'s Markdown becomes the address a link element stores', () {
      expect(
        linkAddressOf(
          '[Einkauf](hiwiski://todo_list/0190c1d4-7a1b-7c3d-9e8f-123456789abc)',
        ),
        equals('hiwiski://todo_list/0190c1d4-7a1b-7c3d-9e8f-123456789abc'),
      );
      expect(linkAddressOf('no link'), isNull);
    });

    test('a link element shows its target\'s current title', () {
      const id = '0190c1d4-7a1b-7c3d-9e8f-123456789abc';
      final index = LinkIndex.from([
        const LinkItem(
          itemType: EntityTypes.wikiPage,
          itemId: id,
          title: 'Packliste',
        ),
      ]);
      final map = Pinboard(
        nodes: [
          node(
            'l',
            kind: PinboardKinds.link,
            target: 'hiwiski://wiki_page/$id',
          ),
          node('gone', kind: PinboardKinds.link, target: 'hiwiski://todo/$id'),
        ],
        edges: const [],
      );
      final targets = pinboardTargetsOf(map, index);
      expect(targets.keys, equals(['hiwiski://wiki_page/$id']));
      expect(targets.values.single.title, equals('Packliste'));
    });
  });

  group('conflicts', () {
    SyncConflict lost(String field, String mine, {String entity = 'a'}) => .new(
      id: '$entity:$field',
      entityType: EntityTypes.pinboardNode,
      entityId: entity,
      field: field,
      mine: mine,
      theirs: '0',
      detectedAt: DateTime(2026, 11, 21),
    );

    test('a position is one conflict, a size another', () {
      final groups = groupConflicts([
        lost(WireFields.y, '40'),
        lost(WireFields.width, '200'),
        lost(WireFields.x, '30'),
        lost(WireFields.height, '90'),
        lost(WireFields.x, '5', entity: 'b'),
      ]);

      expect(
        [
          for (final group in groups)
            [for (final each in inReadingOrder(group)) each.id],
        ],
        equals([
          ['a:x', 'a:y'],
          ['a:width', 'a:height'],
          ['b:x'],
        ]),
      );
    });

    test('this device\'s version takes back what it wrote', () {
      final mine = mineOf(node('a', x: 0, y: 0), [
        lost(WireFields.x, '30'),
        lost(WireFields.y, '40'),
        lost(WireFields.color, '"TEAL"'),
        lost(WireFields.textColor, 'null'),
      ]);

      expect((mine.x, mine.y), equals((30, 40)));
      expect(mine.color, equals('TEAL'));
      expect(mine.textColor, isNull);
      expect(mine.width, equals(100));
    });

    test('this device\'s version is turned and drawn as it wrote it', () {
      final theirs = node('a', rotation: 90);

      final mine = mineOf(theirs, [
        lost(WireFields.rotation, 'null'),
        lost(WireFields.points, '"0,0 10000,10000"'),
      ]);
      expect(mine.rotation, isNull);
      expect(mine.points, equals('0,0 10000,10000'));
      expect(
        mineOf(node('a'), [lost(WireFields.rotation, '45')]).rotation,
        equals(45),
      );
      // What did not lose stays as the map has it.
      expect(mineOf(theirs, [lost(WireFields.x, '30')]).rotation, equals(90));
    });

    test('a version differing only in its look stands beside the other', () {
      final theirs = node('a', x: 10, y: 20);
      final recoloured = theirs.withFields({WireFields.color: 'TEAL'});
      final moved = theirs.changed(x: 300);

      expect(
        mineBoundsOf(theirs, recoloured, 24),
        equals(const Rect.fromLTWH(134, 20, 100, 50)),
      );
      expect(mineBoundsOf(theirs, moved, 24), equals(moved.bounds));
    });
  });

  group('strokes drawn by hand', () {
    test('a stroke is kept across its element and drawn where it was', () {
      const drawn = [Offset(100, 100), Offset(200, 150), Offset(300, 100)];
      final stroke = strokeOf(drawn, 10);

      expect(stroke.bounds, equals(const Rect.fromLTRB(95, 95, 305, 155)));
      final node = drawingOf(stroke);
      final back = strokePointsOf(node);
      for (int i = 0; i < drawn.length; i++) {
        expect((back[i] - drawn[i]).distance, lessThan(0.1));
      }
    });

    test('a stroke too long for the server is thinned until it fits', () {
      // A long scribble: every point a turn, nothing a first thinning drops.
      final scribble = [
        for (int i = 0; i < 20000; i++)
          Offset(i * 3.0, (i.isEven ? 0 : 40) + i % 7 * 3.0),
      ];
      final stroke = strokeOf(scribble, 4);

      expect(stroke.points.length, lessThanOrEqualTo(pinboardMaxPointsChars));
      // Its ends where they were drawn, as near as a stored point can say.
      final resolution = stroke.bounds.longestSide / strokeScale;
      final back = strokePointsOf(drawingOf(stroke));
      expect((back.first - scribble.first).distance, lessThan(resolution));
      expect((back.last - scribble.last).distance, lessThan(resolution));
      // What fits stays as drawn.
      const short = [Offset(0, 0), Offset(50, 40), Offset(100, 0)];
      expect(strokePointsOf(drawingOf(strokeOf(short, 4))), hasLength(3));
    });

    test('a straight line keeps its ends, a corner its corner', () {
      final straight = [for (int i = 0; i <= 20; i++) Offset(i * 10.0, 0)];
      expect(thinOut(straight, 0.5), equals([straight.first, straight.last]));
      final corner = [
        for (int i = 0; i <= 10; i++) Offset(i * 10.0, 0),
        for (int i = 1; i <= 10; i++) Offset(100, i * 10.0),
      ];
      expect(
        thinOut(corner, 0.5),
        equals(const [Offset(0, 0), Offset(100, 0), Offset(100, 100)]),
      );
    });

    test('the eraser takes the strokes it goes over, and only those', () {
      final across = drawingOf(
        strokeOf(const [Offset(0, 50), Offset(200, 50)], 4),
      );
      final aside = drawingOf(
        strokeOf(const [Offset(0, 300), Offset(200, 300)], 4),
        id: 'aside',
      );
      final box = node('box', x: 90, y: 0, width: 20, height: 100);
      final map = Pinboard(nodes: [across, aside, box], edges: const []);

      // A quick swipe down from above to below the line: two points only.
      final erased = erasedBy(
        const [Offset(100, 0), Offset(100, 100)],
        map,
        12,
      );

      expect(erased, equals({across.id}));
    });

    test('the eraser takes a turned stroke where it is seen', () {
      // Drawn across, turned upright about its middle (100, 50).
      final upright = drawingOf(
        strokeOf(const [Offset(0, 50), Offset(200, 50)], 4),
        rotation: 90,
      );
      final map = Pinboard(nodes: [upright], edges: const []);

      // Across where it is seen now, upright through x = 100.
      expect(
        erasedBy(const [Offset(60, 120), Offset(140, 120)], map, 12),
        equals({upright.id}),
      );
      // Along where it lay before it was turned, clear of where it is seen.
      expect(erasedBy(const [Offset(0, 50), Offset(40, 50)], map, 12), isEmpty);
    });
  });

  test('a lasso goes round what it encloses, a rectangle what lies in it', () {
    final map = Pinboard(
      nodes: [
        node('in', x: 40, y: 40, width: 20, height: 20),
        node('out', x: 300, y: 40, width: 20, height: 20),
      ],
      edges: const [],
    );
    // A rough circle round the first.
    final lasso = [
      for (int i = 0; i < 12; i++)
        Offset(
          50 + 40 * math.cos(i * math.pi / 6),
          50 + 40 * math.sin(i * math.pi / 6),
        ),
    ];
    expect(insideLasso(map, lasso), equals({'in'}));
    expect(
      insideRectangle(map, const Offset(0, 0), const Offset(400, 100)),
      equals({'in', 'out'}),
    );
    expect(insideLasso(map, const [Offset(0, 0), Offset(10, 10)]), isEmpty);
  });

  test('hits are put in order by place, alphabetically or by when made', () {
    PinboardHit hit(String id, String text, double top) => .new(
      id: id,
      isEdge: false,
      kind: PinboardKinds.plain,
      snippet: text,
      text: text,
      bounds: Rect.fromLTWH(0, top, 10, 10),
    );
    // Ids of version 7 begin with the time they were made.
    final hits = [
      hit('01a2-made-second', 'Berge', 0),
      hit('01a1-made-first', 'meer', 50),
      hit('01a3-made-third', 'Alpen', 100),
    ];
    List<String> texts(PinboardHitOrder order, {bool descending = false}) => [
      for (final hit in sortHits(hits, order, descending: descending)) hit.text,
    ];
    expect(texts(.place), equals(['Berge', 'meer', 'Alpen']));
    expect(texts(.alphabetical), equals(['Alpen', 'Berge', 'meer']));
    expect(texts(.created), equals(['meer', 'Berge', 'Alpen']));
    expect(
      texts(.created, descending: true),
      equals(['Alpen', 'Berge', 'meer']),
    );
    // A letter with marks stands with its plain one, as in a dictionary — not after
    // the Z, where its code would put it.
    expect([
      for (final hit in sortHits(
        [
          hit('z', 'Zelt', 0),
          hit('o', 'Öl', 10),
          hit('a', 'Äpfel', 20),
          hit('s', 'Straße', 30),
          hit('b', 'Birne', 40),
          hit('e', 'Éclair', 50),
        ],
        .alphabetical,
        descending: false,
      ))
        hit.text,
    ], equals(['Äpfel', 'Birne', 'Éclair', 'Öl', 'Straße', 'Zelt']));
  });

  test('a turned element covers its turned box and grows from its corner', () {
    final upright = node('a', x: 0, y: 0, width: 100, height: 20);
    final turned = PinboardNode(
      id: 'a',
      ownerId: 'anna',
      version: 1,
      pageId: 'page',
      kind: PinboardKinds.plain,
      x: 0,
      y: 0,
      width: 100,
      height: 20,
      layer: 1,
      text: '',
      rotation: 90,
    );
    // Upright, a long thin box; a quarter turn stands it on end about its centre.
    expect(turned.turnedBounds.width, closeTo(20, 0.001));
    expect(turned.turnedBounds.height, closeTo(100, 0.001));
    expect(turned.covers(const Offset(50, -30)), isTrue);
    expect(upright.covers(const Offset(50, -30)), isFalse);

    // The corner seen at the top right — the turned top left — stays put.
    Offset seenTopLeft(PinboardNode node) =>
        node.center +
        turnOffset(Offset(-node.width / 2, -node.height / 2), node.turn);
    final before = seenTopLeft(turned);
    final grown = turned.resizedTo(160, 40);
    expect((seenTopLeft(grown) - before).distance, lessThan(1));
    expect(rotationOf(360), isNull);
    expect(rotationOf(-90), equals(270));
  });

  test('a shape is a stroke along its outline, with sharp corners', () {
    final rectangle = penShapeOutline(
      .rectangle,
      const Offset(0, 0),
      const Offset(100, 50),
      head: 10,
    );
    expect(rectangle, hasLength(10));
    expect(rectangle.toSet(), hasLength(4));
    final arrow = penShapeOutline(
      .arrow,
      const Offset(0, 0),
      const Offset(100, 0),
      head: 10,
    );
    // Out to the tip and along both sides of the head.
    expect(arrow.first, equals(Offset.zero));
    expect(arrow[1], equals(const Offset(100, 0)));
    expect(arrow.where((point) => point.dx < 100).length, greaterThan(2));
  });

  test('a text size of its own is a number of pixels within bounds', () {
    expect(pinboardTextPixels('18'), equals(18));
    expect(pinboardTextPixels(PinboardTextSizes.large), isNull);
    expect(pinboardTextPixels('1'), isNull);
    expect(pinboardTextPixels('9999'), isNull);
  });

  test('a fitted camera shows everything, centred, never closer than 1', () {
    final camera = fitInto(
      const Rect.fromLTWH(0, 0, 200, 100),
      const Size(800, 600),
      margin: 0,
    );
    expect(camera.scale, equals(1));
    expect(camera.origin, equals(const Offset(300, 250)));
    final far = fitInto(
      const Rect.fromLTWH(-1000, -1000, 4000, 2000),
      const Size(800, 600),
    );
    expect(far.scale, equals(0.2));
  });
}

/// A drawing element of [stroke].
PinboardNode drawingOf(
  ({Rect bounds, String points}) stroke, {
  String id = 'stroke',
  int? rotation,
}) => .new(
  id: id,
  ownerId: 'anna',
  version: 1,
  pageId: 'page',
  kind: PinboardKinds.drawing,
  x: stroke.bounds.left.round(),
  y: stroke.bounds.top.round(),
  width: stroke.bounds.width.round(),
  height: stroke.bounds.height.round(),
  layer: 1,
  text: '',
  points: stroke.points,
  strokeWidth: 4,
  rotation: rotation,
);
