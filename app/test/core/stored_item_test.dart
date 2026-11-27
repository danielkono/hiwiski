import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/sync/entity_codec.dart';

/// **What a restore left behind goes out as it came in.** Every type's row is turned
/// back into fields to bring it back to the server; a field read wrong there would
/// write a wrong value over the family's data. So: in through [EntityCodec.upsert],
/// out through [EntityCodec.stored], and the fields are the same.
void main() {
  late HiwiskiDatabase db;

  setUp(() => db = HiwiskiDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  final cases = <String, ({String? container, Map<String, Object?> fields})>{
    EntityTypes.todoList: (
      container: null,
      fields: {
        WireFields.name: 'Wocheneinkauf',
        WireFields.description: 'Samstags',
        WireFields.kind: 'KANBAN',
        WireFields.colorToken: 'green',
        WireFields.position: 3,
        WireFields.assignees: ['m1', 'm2'],
        WireFields.tags: ['t1'],
        WireFields.columns: [
          {'id': 'c1', 'name': 'Offen'},
        ],
        WireFields.archivedAt: '2026-10-01T08:00:00.000Z',
        WireFields.archivedBy: 'm1',
      },
    ),
    EntityTypes.todo: (
      container: 'l1',
      fields: {
        WireFields.title: 'Obst',
        WireFields.description: 'Äpfel und Birnen',
        WireFields.status: 'DONE',
        WireFields.dueDate: '2026-11-05',
        WireFields.dueTime: '18:30',
        WireFields.rrule: 'FREQ=WEEKLY',
        WireFields.assignees: ['m1'],
        WireFields.position: 2,
        WireFields.amount: 1.5,
        WireFields.unit: 'kg',
        WireFields.productId: 'p1',
        WireFields.columnId: 'c1',
        WireFields.tags: const <String>[],
      },
    ),
    EntityTypes.calendar: (
      container: null,
      fields: {
        WireFields.name: 'Familie',
        WireFields.colorToken: 'red',
        WireFields.kind: 'LOCAL',
        WireFields.position: 1,
        WireFields.tags: ['t1', 't2'],
        WireFields.defaultReminderMinutes: 30,
      },
    ),
    EntityTypes.event: (
      container: 'c1',
      fields: {
        WireFields.title: 'Zahnarzt',
        WireFields.description: null,
        WireFields.location: 'Praxis',
        WireFields.timeForm: 'TIMED',
        WireFields.startsAt: '2026-11-05T09:00:00.000Z',
        WireFields.endsAt: '2026-11-05T10:00:00.000Z',
        WireFields.startDate: null,
        WireFields.endDate: null,
        WireFields.localStart: '2026-11-05T10:00',
        WireFields.localEnd: '2026-11-05T11:00',
        WireFields.timeZone: 'Europe/Berlin',
        WireFields.rrule: null,
        WireFields.exceptions: {
          '2026-11-12': {'cancelled': true},
        },
        WireFields.attendees: ['m2'],
        WireFields.tags: const <String>[],
        WireFields.reminderMinutes: 15,
      },
    ),
    EntityTypes.calendarSubscription: (
      container: 'c1',
      fields: {
        WireFields.name: 'Ferien',
        WireFields.url: 'https://example.org/ferien.ics',
        WireFields.targetKind: 'EVENT',
        WireFields.targetListId: null,
        WireFields.syncInterval: 'WEEKLY',
      },
    ),
    EntityTypes.calendarFeed: (
      container: null,
      fields: {
        WireFields.name: 'Für Oma',
        WireFields.calendarIds: ['c1', 'c2'],
        WireFields.contentMode: 'BUSY',
      },
    ),
    EntityTypes.wikiPage: (
      container: 'parent',
      fields: {
        'servings': 4,
        WireFields.position: 0,
        WireFields.kind: 'RECIPE',
        WireFields.title: 'Pfannkuchen',
        WireFields.content: '# Teig',
        WireFields.tags: ['t1'],
        WireFields.archivedAt: null,
        WireFields.archivedBy: null,
      },
    ),
    EntityTypes.comment: (
      container: null,
      fields: {
        WireFields.itemType: 'TODO',
        WireFields.itemId: 'x1',
        WireFields.body: 'Erledigt?',
      },
    ),
    EntityTypes.board: (
      container: null,
      fields: {
        WireFields.kind: 'DASHBOARD',
        WireFields.name: 'Flur',
        WireFields.layout: 'GRID',
        WireFields.columns: 6,
      },
    ),
    EntityTypes.widget: (
      container: 'b1',
      fields: {
        WireFields.kind: 'CLOCK',
        WireFields.config: {'seconds': true},
        WireFields.gridX: 1,
        WireFields.gridY: 2,
        WireFields.gridW: 3,
        WireFields.gridH: 1,
        WireFields.position: 4,
      },
    ),
    EntityTypes.tag: (
      container: null,
      fields: {WireFields.name: 'Garten', WireFields.colorToken: 'green'},
    ),
    EntityTypes.listOrder: (
      container: null,
      fields: {
        WireFields.listIds: ['l2', 'l1'],
      },
    ),
    EntityTypes.mindmapNode: (
      container: 'page1',
      fields: {
        WireFields.kind: MindmapKinds.note,
        WireFields.x: 10,
        WireFields.y: -20,
        WireFields.width: 200,
        WireFields.height: 120,
        WireFields.layer: 2.5,
        WireFields.text: '# Plan',
        WireFields.target: 'hiwiski://todo/t1',
        WireFields.linkView: MindmapLinkViews.content,
        WireFields.color: '#3B6939',
        WireFields.shape: MindmapShapes.ellipse,
        WireFields.textSize: MindmapTextSizes.large,
        WireFields.textColor: '#1F2A44',
        WireFields.points: '0,0 5000,10000 10000,0',
        WireFields.strokeWidth: 4,
        WireFields.rotation: 30,
        WireFields.textAlign: MindmapTextAligns.bottomCenter,
        WireFields.textFlow: MindmapTextFlows.shape,
      },
    ),
    EntityTypes.mindmapEdge: (
      container: 'page1',
      fields: {
        WireFields.fromId: 'n1',
        WireFields.toId: 'n2',
        WireFields.text: 'und',
        WireFields.color: 'RUST',
        WireFields.strokeWidth: 6,
        WireFields.line: MindmapLines.dashed,
        WireFields.arrows: MindmapArrows.end,
      },
    ),
  };

  for (final MapEntry(key: type, value: example) in cases.entries) {
    test('$type goes out as it came in', () async {
      final codec = entityCodecs.firstWhere(
        (codec) => codec.entityType == type,
      );
      await codec.upsert(
        db,
        id: 'id1',
        ownerId: 'm1',
        version: 7,
        containerId: example.container,
        entityKey: null,
        fields: example.fields,
      );

      final stored = await codec.stored(db, 'id1');

      expect(stored, isNotNull);
      expect(stored!.fields, equals(example.fields));
      expect(stored.containerId, equals(example.container));
      expect(stored.version, equals(7));
      expect(stored.ownerId, equals('m1'));
      expect(stored.deleted, isFalse);
    });
  }

  test('a row deleted on this device goes out as its deletion', () async {
    const codec = TagCodec();
    await codec.upsert(
      db,
      id: 'id1',
      ownerId: 'm1',
      version: 3,
      containerId: null,
      entityKey: null,
      fields: {WireFields.name: 'Weg'},
    );
    await codec.markDeleted(db, 'id1', 4);

    final stored = await codec.stored(db, 'id1');
    expect(stored!.deleted, isTrue);
    expect(stored.version, equals(4));
  });

  test('every type but the server-written one can go out', () {
    expect(
      entityCodecs.map((codec) => codec.entityType).toSet(),
      equals({...cases.keys, EntityTypes.todoOccurrence}),
    );
  });
}
