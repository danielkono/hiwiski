import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../db/hiwiski_database.dart';
import '../db/tables.dart';
import '../common/page_properties.dart';
import '../common/wire.dart';

/// How an entity type gets from the envelope into the local database.
///
/// **A hand-written dispatcher decodes based on `entityType`**.
/// No `oneOf`, no discriminator: the generators handle that poorly, and an unknown
/// type has to stay skippable.
abstract class EntityCodec {
  const EntityCodec();

  String get entityType;

  /// The local table. Each one carries [SyncedItem], i.e. `id` and `version`.
  TableInfo<Table, Object?> table(HiwiskiDatabase db);

  /// The owner of the local row — a change from this device must not overwrite it with
  /// the reader's own ID.
  Future<String?> localOwner(HiwiskiDatabase db, String id) =>
      _localColumn(db, id, (row) => row.ownerId);

  /// The version of the local row — the `baseVersion` for a change that builds on the
  /// local state without the caller knowing the row.
  Future<int?> localVersion(HiwiskiDatabase db, String id) =>
      _localColumn(db, id, (row) => row.version);

  Future<T?> _localColumn<T extends Object>(
    HiwiskiDatabase db,
    String id,
    Column<T> Function(SyncedItem row) column,
  ) async {
    final info = table(db);
    // Every synced table mixes in [SyncedItem]; its columns are the generated ones.
    final row = info as SyncedItem;
    final selected = column(row);
    final result =
        await (db.selectOnly(info)
              ..addColumns([selected])
              ..where(row.id.equals(id)))
            .getSingleOrNull();
    return result?.read(selected);
  }

  /// Writes the **delivered** fields into the local row.
  ///
  /// Only the delivered ones: every log entry carries what *this* mutation changed.
  /// A missing field means "unchanged", not "empty".
  ///
  /// That is no subtlety. An early client rewrote the whole row when checking
  /// something off, and "2 l Milch" became "2 l" — exactly why only changed fields
  /// are sent: *Otherwise an older app blanks fields it does not know and deletes
  /// the work of a newer device.*
  Future<void> upsert(
    HiwiskiDatabase db, {
    required String id,
    required String ownerId,
    required int version,
    required String? containerId,
    required String? entityKey,
    required Map<String, dynamic> fields,
  });

  Future<void> markDeleted(HiwiskiDatabase db, String id, int version);

  /// The container of the local row, as [upsert] expects it as `containerId`.
  ///
  /// For the conflict: only the discarded fields come along there, and [upsert] would
  /// otherwise write the container empty. `null` for types without a container.
  Future<String?> containerOf(HiwiskiDatabase db, String id) async => null;

  /// Throws the item and everything below it away **for real**.
  ///
  /// For `access_revoked`: whoever loses the share should not keep the data. This is
  /// not a soft delete — a tombstone would mean the item was deleted, and that is not
  /// true: it still exists, just not for me any more.
  Future<void> purge(HiwiskiDatabase db, String id);

  /// The local row as it would go out — every field, as [upsert] reads them.
  ///
  /// For what a restore left behind: rows this device has and the restored server no
  /// longer has, or has older. `null` without a row, and for a type
  /// whose rows only the server writes.
  Future<StoredItem?> stored(HiwiskiDatabase db, String id) async => null;

  /// `Value.absent()` if the field was not delivered.
  static Value<T?> optional<T>(
    Map<String, dynamic> fields,
    String name,
    T? Function(Object?) read,
  ) => fields.containsKey(name) ? .new(read(fields[name])) : const .absent();

  /// Like [optional], but for non-null columns: if nothing comes, the old value stays.
  static Value<T> required<T>(
    Map<String, dynamic> fields,
    String name,
    T Function(Object?) read,
  ) => fields.containsKey(name) ? .new(read(fields[name])) : const .absent();

  static DateTime? _date(Object? value) =>
      value == null ? null : .tryParse(value.toString());

  /// The way back of `join(',')`.
  static List<String> _ids(String joined) =>
      joined.isEmpty ? const [] : joined.split(_idSeparator);

  static const _idSeparator = ',';

  /// A wall-clock date as the wire carries it: `2026-10-05`.
  static String? _day(DateTime? value) => value == null
      ? null
      : '${_pad(value.year, 4)}-${_pad(value.month, 2)}-${_pad(value.day, 2)}';

  /// An instant as the wire carries it: ISO 8601 in UTC.
  static String? _stamp(DateTime? value) => value?.toUtc().toIso8601String();

  static Object? _json(String? value) =>
      value == null ? null : jsonDecode(value);

  static String _pad(int value, int width) =>
      value.toString().padLeft(width, '0');
}

/// A local row as it would go out (`EntityCodec.stored`).
@immutable
class const StoredItem({
  required final String ownerId,
  required final int version,

  /// Deleted on this device — what goes out is the deletion, not the fields.
  required final bool deleted,
  required final Map<String, Object?> fields,

  /// What a person recognizes it by: its title or its name.
  required final String label,
  final String? containerId,
  final String? entityKey,
});

class TodoListCodec extends EntityCodec {
  const TodoListCodec();

  @override
  String get entityType => EntityTypes.todoList;

  @override
  TableInfo<Table, Object?> table(HiwiskiDatabase db) => db.todoLists;

  @override
  Future<void> upsert(
    HiwiskiDatabase db, {
    required String id,
    required String ownerId,
    required int version,
    required String? containerId,
    required String? entityKey,
    required Map<String, dynamic> fields,
  }) async {
    await db
        .into(db.todoLists)
        .insertOnConflictUpdate(
          TodoListsCompanion.insert(
            id: id,
            ownerId: ownerId,
            version: Value(version),
            entityKey: entityKey == null
                ? const Value.absent()
                : Value(entityKey),
            name: EntityCodec.required(
              fields,
              WireFields.name,
              (value) => value as String? ?? '',
            ),
            description: EntityCodec.optional(
              fields,
              WireFields.description,
              (value) => value as String?,
            ),
            kind: EntityCodec.required(
              fields,
              WireFields.kind,
              (value) => value as String? ?? ListKinds.standard,
            ),
            colorToken: EntityCodec.required(
              fields,
              WireFields.colorToken,
              (value) => value as String? ?? ColorTokens.blue,
            ),
            position: EntityCodec.required(
              fields,
              WireFields.position,
              (value) => (value as num?)?.toInt() ?? 0,
            ),
            assignees: EntityCodec.required(
              fields,
              WireFields.assignees,
              (value) => (value as List?)?.join(',') ?? '',
            ),
            tags: EntityCodec.required(
              fields,
              WireFields.tags,
              (value) => (value as List?)?.join(',') ?? '',
            ),
            // Kept as the JSON it arrives as — the board reads it, nothing else does.
            columns: EntityCodec.optional(
              fields,
              WireFields.columns,
              (value) => value == null ? null : jsonEncode(value),
            ),
            archivedAt: EntityCodec.optional(
              fields,
              WireFields.archivedAt,
              EntityCodec._date,
            ),
            archivedBy: EntityCodec.optional(
              fields,
              WireFields.archivedBy,
              (value) => value as String?,
            ),
            // An upsert on a deleted item revives it: the server did that, and
            // silently discarding it would be data loss.
            deletedAt: const Value(null),
          ),
        );
  }

  @override
  Future<void> markDeleted(HiwiskiDatabase db, String id, int version) =>
      (db.update(db.todoLists)..where((row) => row.id.equals(id))).write(
        TodoListsCompanion(
          deletedAt: Value(clock.now()),
          version: Value(version),
        ),
      );

  @override
  Future<void> purge(HiwiskiDatabase db, String id) async {
    await db.transaction(() async {
      final todos = await (db.select(
        db.todos,
      )..where((row) => row.listId.equals(id))).get();
      for (final todo in todos) {
        await const TodoCodec().purge(db, todo.id);
      }
      await (db.delete(db.todoLists)..where((row) => row.id.equals(id))).go();
    });
  }

  @override
  Future<StoredItem?> stored(HiwiskiDatabase db, String id) async {
    final row = await (db.select(
      db.todoLists,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return StoredItem(
      ownerId: row.ownerId,
      version: row.version,
      deleted: row.deletedAt != null,
      entityKey: row.entityKey,
      label: row.name,
      fields: {
        WireFields.name: row.name,
        WireFields.description: row.description,
        WireFields.kind: row.kind,
        WireFields.colorToken: row.colorToken,
        WireFields.position: row.position,
        WireFields.assignees: EntityCodec._ids(row.assignees),
        WireFields.tags: EntityCodec._ids(row.tags),
        WireFields.columns: EntityCodec._json(row.columns),
        WireFields.archivedAt: EntityCodec._stamp(row.archivedAt),
        WireFields.archivedBy: row.archivedBy,
      },
    );
  }
}

class TodoCodec extends EntityCodec {
  const TodoCodec();

  @override
  String get entityType => EntityTypes.todo;

  @override
  TableInfo<Table, Object?> table(HiwiskiDatabase db) => db.todos;

  @override
  Future<void> upsert(
    HiwiskiDatabase db, {
    required String id,
    required String ownerId,
    required int version,
    required String? containerId,
    required String? entityKey,
    required Map<String, dynamic> fields,
  }) async {
    await db
        .into(db.todos)
        .insertOnConflictUpdate(
          TodosCompanion.insert(
            id: id,
            ownerId: ownerId,
            version: Value(version),
            listId: containerId ?? '',
            entityKey: entityKey == null
                ? const Value.absent()
                : Value(entityKey),
            title: EntityCodec.required(
              fields,
              WireFields.title,
              (value) => value as String? ?? '',
            ),
            description: EntityCodec.optional(
              fields,
              WireFields.description,
              (value) => value as String?,
            ),
            status: EntityCodec.required(
              fields,
              WireFields.status,
              (value) => value as String? ?? TodoStatuses.open,
            ),
            dueDate: EntityCodec.optional(
              fields,
              WireFields.dueDate,
              EntityCodec._date,
            ),
            dueTime: EntityCodec.optional(
              fields,
              WireFields.dueTime,
              (value) => value as String?,
            ),
            rrule: EntityCodec.optional(
              fields,
              WireFields.rrule,
              (value) => value as String?,
            ),
            assignees: EntityCodec.required(
              fields,
              WireFields.assignees,
              (value) => (value as List?)?.join(',') ?? '',
            ),
            position: EntityCodec.required(
              fields,
              WireFields.position,
              (value) => (value as num?)?.toInt() ?? 0,
            ),
            amount: EntityCodec.optional(
              fields,
              WireFields.amount,
              (value) => (value as num?)?.toDouble(),
            ),
            unit: EntityCodec.optional(
              fields,
              WireFields.unit,
              (value) => value as String?,
            ),
            productId: EntityCodec.optional(
              fields,
              WireFields.productId,
              (value) => value as String?,
            ),
            columnId: EntityCodec.optional(
              fields,
              WireFields.columnId,
              (value) => value as String?,
            ),
            tags: EntityCodec.required(
              fields,
              WireFields.tags,
              (value) => (value as List?)?.join(',') ?? '',
            ),
            deletedAt: const Value(null),
          ),
        );
  }

  @override
  Future<String?> containerOf(HiwiskiDatabase db, String id) async =>
      (await (db.select(
        db.todos,
      )..where((row) => row.id.equals(id))).getSingleOrNull())?.listId;

  @override
  Future<void> markDeleted(HiwiskiDatabase db, String id, int version) =>
      (db.update(db.todos)..where((row) => row.id.equals(id))).write(
        TodosCompanion(deletedAt: Value(clock.now()), version: Value(version)),
      );

  @override
  Future<void> purge(HiwiskiDatabase db, String id) async {
    await db.transaction(() async {
      await (db.delete(
        db.todoOccurrences,
      )..where((row) => row.todoId.equals(id))).go();
      await (db.delete(db.todos)..where((row) => row.id.equals(id))).go();
    });
  }

  @override
  Future<StoredItem?> stored(HiwiskiDatabase db, String id) async {
    final row = await (db.select(
      db.todos,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return StoredItem(
      ownerId: row.ownerId,
      version: row.version,
      deleted: row.deletedAt != null,
      containerId: row.listId,
      entityKey: row.entityKey,
      label: row.title,
      fields: {
        WireFields.title: row.title,
        WireFields.description: row.description,
        WireFields.status: row.status,
        WireFields.dueDate: EntityCodec._day(row.dueDate),
        WireFields.dueTime: row.dueTime,
        WireFields.rrule: row.rrule,
        WireFields.assignees: EntityCodec._ids(row.assignees),
        WireFields.position: row.position,
        WireFields.amount: row.amount,
        WireFields.unit: row.unit,
        WireFields.productId: row.productId,
        WireFields.columnId: row.columnId,
        WireFields.tags: EntityCodec._ids(row.tags),
      },
    );
  }
}

class TodoOccurrenceCodec extends EntityCodec {
  const TodoOccurrenceCodec();

  @override
  String get entityType => EntityTypes.todoOccurrence;

  @override
  TableInfo<Table, Object?> table(HiwiskiDatabase db) => db.todoOccurrences;

  @override
  Future<void> upsert(
    HiwiskiDatabase db, {
    required String id,
    required String ownerId,
    required int version,
    required String? containerId,
    required String? entityKey,
    required Map<String, dynamic> fields,
  }) async {
    await db
        .into(db.todoOccurrences)
        .insertOnConflictUpdate(
          TodoOccurrencesCompanion.insert(
            id: id,
            ownerId: ownerId,
            version: Value(version),
            todoId: containerId ?? '',
            occurrenceDate:
                EntityCodec._date(fields[WireFields.occurrenceDate]) ??
                clock.now(),
            doneAt: EntityCodec.optional(
              fields,
              WireFields.doneAt,
              EntityCodec._date,
            ),
            doneBy: EntityCodec.optional(
              fields,
              WireFields.doneBy,
              (value) => value as String?,
            ),
            skipped: EntityCodec.required(
              fields,
              WireFields.skipped,
              (value) => value as bool? ?? false,
            ),
            deletedAt: const Value(null),
          ),
        );
  }

  @override
  Future<String?> containerOf(HiwiskiDatabase db, String id) async =>
      (await (db.select(
        db.todoOccurrences,
      )..where((row) => row.id.equals(id))).getSingleOrNull())?.todoId;

  @override
  Future<void> markDeleted(HiwiskiDatabase db, String id, int version) =>
      (db.update(db.todoOccurrences)..where((row) => row.id.equals(id))).write(
        TodoOccurrencesCompanion(
          deletedAt: Value(clock.now()),
          version: Value(version),
        ),
      );

  @override
  Future<void> purge(HiwiskiDatabase db, String id) =>
      (db.delete(db.todoOccurrences)..where((row) => row.id.equals(id))).go();
}

// --- Calendar -------------------------------------------------------------

class CalendarCodec extends EntityCodec {
  const CalendarCodec();

  @override
  String get entityType => EntityTypes.calendar;

  @override
  TableInfo<Table, Object?> table(HiwiskiDatabase db) => db.calendars;

  @override
  Future<void> upsert(
    HiwiskiDatabase db, {
    required String id,
    required String ownerId,
    required int version,
    required String? containerId,
    required String? entityKey,
    required Map<String, dynamic> fields,
  }) async {
    await db
        .into(db.calendars)
        .insertOnConflictUpdate(
          CalendarsCompanion.insert(
            id: id,
            ownerId: ownerId,
            version: Value(version),
            name: EntityCodec.required(
              fields,
              WireFields.name,
              (value) => value as String? ?? '',
            ),
            colorToken: EntityCodec.required(
              fields,
              WireFields.colorToken,
              (value) => value as String? ?? ColorTokens.blue,
            ),
            kind: EntityCodec.required(
              fields,
              WireFields.kind,
              (value) => value as String? ?? CalendarKinds.local,
            ),
            position: EntityCodec.required(
              fields,
              WireFields.position,
              (value) => (value as num?)?.toInt() ?? 0,
            ),
            tags: EntityCodec.required(
              fields,
              WireFields.tags,
              (value) => (value as List?)?.join(',') ?? '',
            ),
            defaultReminderMinutes: EntityCodec.optional(
              fields,
              WireFields.defaultReminderMinutes,
              (value) => (value as num?)?.toInt(),
            ),
            deletedAt: const Value(null),
          ),
        );
  }

  @override
  Future<void> markDeleted(HiwiskiDatabase db, String id, int version) =>
      (db.update(db.calendars)..where((row) => row.id.equals(id))).write(
        CalendarsCompanion(
          deletedAt: Value(clock.now()),
          version: Value(version),
        ),
      );

  @override
  Future<void> purge(HiwiskiDatabase db, String id) async {
    await db.transaction(() async {
      await (db.delete(
        db.events,
      )..where((row) => row.calendarId.equals(id))).go();
      await (db.delete(
        db.calendarSubscriptions,
      )..where((row) => row.calendarId.equals(id))).go();
      await (db.delete(db.calendars)..where((row) => row.id.equals(id))).go();
    });
  }

  @override
  Future<StoredItem?> stored(HiwiskiDatabase db, String id) async {
    final row = await (db.select(
      db.calendars,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return StoredItem(
      ownerId: row.ownerId,
      version: row.version,
      deleted: row.deletedAt != null,
      label: row.name,
      fields: {
        WireFields.name: row.name,
        WireFields.colorToken: row.colorToken,
        WireFields.kind: row.kind,
        WireFields.position: row.position,
        WireFields.tags: EntityCodec._ids(row.tags),
        WireFields.defaultReminderMinutes: row.defaultReminderMinutes,
      },
    );
  }
}

class EventCodec extends EntityCodec {
  const EventCodec();

  @override
  String get entityType => EntityTypes.event;

  @override
  TableInfo<Table, Object?> table(HiwiskiDatabase db) => db.events;

  @override
  Future<void> upsert(
    HiwiskiDatabase db, {
    required String id,
    required String ownerId,
    required int version,
    required String? containerId,
    required String? entityKey,
    required Map<String, dynamic> fields,
  }) async {
    await db
        .into(db.events)
        .insertOnConflictUpdate(
          EventsCompanion.insert(
            id: id,
            ownerId: ownerId,
            version: Value(version),
            calendarId: containerId ?? '',
            entityKey: entityKey == null
                ? const Value.absent()
                : Value(entityKey),
            title: EntityCodec.required(
              fields,
              WireFields.title,
              (value) => value as String? ?? '',
            ),
            description: EntityCodec.optional(
              fields,
              WireFields.description,
              (value) => value as String?,
            ),
            location: EntityCodec.optional(
              fields,
              WireFields.location,
              (value) => value as String?,
            ),
            timeForm: EntityCodec.required(
              fields,
              WireFields.timeForm,
              (value) => value as String? ?? TimeForms.timed,
            ),
            startsAt: EntityCodec.optional(
              fields,
              WireFields.startsAt,
              EntityCodec._date,
            ),
            endsAt: EntityCodec.optional(
              fields,
              WireFields.endsAt,
              EntityCodec._date,
            ),
            startDate: EntityCodec.optional(
              fields,
              WireFields.startDate,
              EntityCodec._date,
            ),
            endDate: EntityCodec.optional(
              fields,
              WireFields.endDate,
              EntityCodec._date,
            ),
            localStart: EntityCodec.optional(
              fields,
              WireFields.localStart,
              (value) => value as String?,
            ),
            localEnd: EntityCodec.optional(
              fields,
              WireFields.localEnd,
              (value) => value as String?,
            ),
            timeZone: EntityCodec.optional(
              fields,
              WireFields.timeZone,
              (value) => value as String?,
            ),
            rrule: EntityCodec.optional(
              fields,
              WireFields.rrule,
              (value) => value as String?,
            ),
            // The exceptions come back as a whole object — the server added to
            // them, it did not replace them. Locally exactly this object
            // is the new state.
            exceptions: EntityCodec.required(
              fields,
              WireFields.exceptions,
              (value) => value == null ? '{}' : jsonEncode(value),
            ),
            attendees: EntityCodec.required(
              fields,
              WireFields.attendees,
              (value) => (value as List?)?.join(',') ?? '',
            ),
            tags: EntityCodec.required(
              fields,
              WireFields.tags,
              (value) => (value as List?)?.join(',') ?? '',
            ),
            reminderMinutes: EntityCodec.optional(
              fields,
              WireFields.reminderMinutes,
              (value) => (value as num?)?.toInt(),
            ),
            deletedAt: const Value(null),
          ),
        );
  }

  @override
  Future<String?> containerOf(HiwiskiDatabase db, String id) async =>
      (await (db.select(
        db.events,
      )..where((row) => row.id.equals(id))).getSingleOrNull())?.calendarId;

  @override
  Future<void> markDeleted(HiwiskiDatabase db, String id, int version) =>
      (db.update(db.events)..where((row) => row.id.equals(id))).write(
        EventsCompanion(deletedAt: Value(clock.now()), version: Value(version)),
      );

  @override
  Future<void> purge(HiwiskiDatabase db, String id) =>
      (db.delete(db.events)..where((row) => row.id.equals(id))).go();

  @override
  Future<StoredItem?> stored(HiwiskiDatabase db, String id) async {
    final row = await (db.select(
      db.events,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return StoredItem(
      ownerId: row.ownerId,
      version: row.version,
      deleted: row.deletedAt != null,
      containerId: row.calendarId,
      entityKey: row.entityKey,
      label: row.title,
      fields: {
        WireFields.title: row.title,
        WireFields.description: row.description,
        WireFields.location: row.location,
        WireFields.timeForm: row.timeForm,
        WireFields.startsAt: EntityCodec._stamp(row.startsAt),
        WireFields.endsAt: EntityCodec._stamp(row.endsAt),
        WireFields.startDate: EntityCodec._day(row.startDate),
        WireFields.endDate: EntityCodec._day(row.endDate),
        WireFields.localStart: row.localStart,
        WireFields.localEnd: row.localEnd,
        WireFields.timeZone: row.timeZone,
        WireFields.rrule: row.rrule,
        WireFields.exceptions: EntityCodec._json(row.exceptions),
        WireFields.attendees: EntityCodec._ids(row.attendees),
        WireFields.tags: EntityCodec._ids(row.tags),
        WireFields.reminderMinutes: row.reminderMinutes,
      },
    );
  }
}

class CalendarSubscriptionCodec extends EntityCodec {
  const CalendarSubscriptionCodec();

  @override
  String get entityType => EntityTypes.calendarSubscription;

  @override
  TableInfo<Table, Object?> table(HiwiskiDatabase db) =>
      db.calendarSubscriptions;

  @override
  Future<void> upsert(
    HiwiskiDatabase db, {
    required String id,
    required String ownerId,
    required int version,
    required String? containerId,
    required String? entityKey,
    required Map<String, dynamic> fields,
  }) async {
    await db
        .into(db.calendarSubscriptions)
        .insertOnConflictUpdate(
          CalendarSubscriptionsCompanion.insert(
            id: id,
            ownerId: ownerId,
            version: Value(version),
            calendarId: containerId ?? '',
            name: EntityCodec.required(
              fields,
              WireFields.name,
              (value) => value as String? ?? '',
            ),
            url: EntityCodec.required(
              fields,
              WireFields.url,
              (value) => value as String? ?? '',
            ),
            targetKind: EntityCodec.required(
              fields,
              WireFields.targetKind,
              (value) => value as String? ?? SubscriptionTargets.event,
            ),
            targetListId: EntityCodec.optional(
              fields,
              WireFields.targetListId,
              (value) => value as String?,
            ),
            syncInterval: EntityCodec.required(
              fields,
              WireFields.syncInterval,
              (value) => value as String? ?? SyncIntervals.daily,
            ),
            lastSyncAt: EntityCodec.optional(
              fields,
              WireFields.lastSyncAt,
              EntityCodec._date,
            ),
            lastError: EntityCodec.optional(
              fields,
              WireFields.lastError,
              (value) => value as String?,
            ),
            importedCount: EntityCodec.required(
              fields,
              WireFields.importedCount,
              (value) => (value as num?)?.toInt() ?? 0,
            ),
            deletedAt: const Value(null),
          ),
        );
  }

  @override
  Future<String?> containerOf(HiwiskiDatabase db, String id) async =>
      (await (db.select(
        db.calendarSubscriptions,
      )..where((row) => row.id.equals(id))).getSingleOrNull())?.calendarId;

  @override
  Future<void> markDeleted(HiwiskiDatabase db, String id, int version) =>
      (db.update(
        db.calendarSubscriptions,
      )..where((row) => row.id.equals(id))).write(
        CalendarSubscriptionsCompanion(
          deletedAt: Value(clock.now()),
          version: Value(version),
        ),
      );

  @override
  Future<void> purge(HiwiskiDatabase db, String id) => (db.delete(
    db.calendarSubscriptions,
  )..where((row) => row.id.equals(id))).go();

  /// Without what the server writes itself: when it last fetched, how that went.
  @override
  Future<StoredItem?> stored(HiwiskiDatabase db, String id) async {
    final row = await (db.select(
      db.calendarSubscriptions,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return StoredItem(
      ownerId: row.ownerId,
      version: row.version,
      deleted: row.deletedAt != null,
      containerId: row.calendarId,
      label: row.name,
      fields: {
        WireFields.name: row.name,
        WireFields.url: row.url,
        WireFields.targetKind: row.targetKind,
        WireFields.targetListId: row.targetListId,
        WireFields.syncInterval: row.syncInterval,
      },
    );
  }
}

class CalendarFeedCodec extends EntityCodec {
  const CalendarFeedCodec();

  @override
  String get entityType => EntityTypes.calendarFeed;

  @override
  TableInfo<Table, Object?> table(HiwiskiDatabase db) => db.calendarFeeds;

  @override
  Future<void> upsert(
    HiwiskiDatabase db, {
    required String id,
    required String ownerId,
    required int version,
    required String? containerId,
    required String? entityKey,
    required Map<String, dynamic> fields,
  }) async {
    await db
        .into(db.calendarFeeds)
        .insertOnConflictUpdate(
          CalendarFeedsCompanion.insert(
            id: id,
            ownerId: ownerId,
            version: Value(version),
            name: EntityCodec.required(
              fields,
              WireFields.name,
              (value) => value as String? ?? '',
            ),
            calendarIds: EntityCodec.required(
              fields,
              WireFields.calendarIds,
              (value) => (value as List?)?.join(',') ?? '',
            ),
            contentMode: EntityCodec.required(
              fields,
              WireFields.contentMode,
              (value) => value as String? ?? FeedContentModes.full,
            ),
            token: EntityCodec.required(
              fields,
              WireFields.token,
              (value) => value as String? ?? '',
            ),
            deletedAt: const Value(null),
          ),
        );
  }

  @override
  Future<void> markDeleted(HiwiskiDatabase db, String id, int version) =>
      (db.update(db.calendarFeeds)..where((row) => row.id.equals(id))).write(
        CalendarFeedsCompanion(
          deletedAt: Value(clock.now()),
          version: Value(version),
        ),
      );

  @override
  Future<void> purge(HiwiskiDatabase db, String id) =>
      (db.delete(db.calendarFeeds)..where((row) => row.id.equals(id))).go();

  /// Without its token: the server issues the address, and a new one is fine.
  @override
  Future<StoredItem?> stored(HiwiskiDatabase db, String id) async {
    final row = await (db.select(
      db.calendarFeeds,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return StoredItem(
      ownerId: row.ownerId,
      version: row.version,
      deleted: row.deletedAt != null,
      label: row.name,
      fields: {
        WireFields.name: row.name,
        WireFields.calendarIds: EntityCodec._ids(row.calendarIds),
        WireFields.contentMode: row.contentMode,
      },
    );
  }
}

// --- Wiki and comments ---------------------------------------------------

class WikiPageCodec extends EntityCodec {
  const WikiPageCodec();

  @override
  String get entityType => EntityTypes.wikiPage;

  @override
  TableInfo<Table, Object?> table(HiwiskiDatabase db) => db.wikiPages;

  /// The fields a page keeps in columns of its own; every other one is a property.
  static const _columns = {
    WireFields.parentId,
    WireFields.position,
    WireFields.kind,
    WireFields.title,
    WireFields.content,
    WireFields.tags,
    WireFields.archivedAt,
    WireFields.archivedBy,
  };

  static Map<String, Object?> _properties(Map<String, dynamic> fields) => {
    for (final MapEntry(:key, :value) in fields.entries)
      if (!_columns.contains(key)) key: value,
  };

  static Future<String> _storedProperties(
    HiwiskiDatabase db,
    String id,
  ) async =>
      (await (db.select(
        db.wikiPages,
      )..where((row) => row.id.equals(id))).getSingleOrNull())?.properties ??
      emptyProperties;

  @override
  Future<void> upsert(
    HiwiskiDatabase db, {
    required String id,
    required String ownerId,
    required int version,
    required String? containerId,
    required String? entityKey,
    required Map<String, dynamic> fields,
  }) async {
    await db
        .into(db.wikiPages)
        .insertOnConflictUpdate(
          WikiPagesCompanion.insert(
            id: id,
            ownerId: ownerId,
            version: Value(version),
            // A page's container is its parent page; `null` is the root.
            parentId: Value(containerId),
            position: EntityCodec.required(
              fields,
              WireFields.position,
              (value) => (value as num?)?.toInt() ?? 0,
            ),
            kind: EntityCodec.required(
              fields,
              WireFields.kind,
              (value) => value as String? ?? PageKinds.page,
            ),
            entityKey: entityKey == null
                ? const Value.absent()
                : Value(entityKey),
            title: EntityCodec.required(
              fields,
              WireFields.title,
              (value) => value as String? ?? '',
            ),
            content: EntityCodec.required(
              fields,
              WireFields.content,
              (value) => value as String? ?? '',
            ),
            tags: EntityCodec.required(
              fields,
              WireFields.tags,
              (value) => (value as List?)?.join(',') ?? '',
            ),
            // Whatever is not a column is a property of the page's kind — a
            // recipe's servings, or a field of a kind this app does not know yet,
            // kept for when it does.
            properties: switch (_properties(fields)) {
              final changes when changes.isEmpty => const Value.absent(),
              final changes => Value(
                mergeProperties(await _storedProperties(db, id), changes),
              ),
            },
            archivedAt: EntityCodec.optional(
              fields,
              WireFields.archivedAt,
              EntityCodec._date,
            ),
            archivedBy: EntityCodec.optional(
              fields,
              WireFields.archivedBy,
              (value) => value as String?,
            ),
            deletedAt: const Value(null),
          ),
        );
  }

  @override
  Future<String?> containerOf(HiwiskiDatabase db, String id) async =>
      (await (db.select(
        db.wikiPages,
      )..where((row) => row.id.equals(id))).getSingleOrNull())?.parentId;

  @override
  Future<void> markDeleted(HiwiskiDatabase db, String id, int version) =>
      (db.update(db.wikiPages)..where((row) => row.id.equals(id))).write(
        WikiPagesCompanion(
          deletedAt: Value(clock.now()),
          version: Value(version),
        ),
      );

  /// A branch that loses its share disappears **entirely** — with everything below it.
  @override
  Future<void> purge(HiwiskiDatabase db, String id) async {
    await db.transaction(() async {
      final children = await (db.select(
        db.wikiPages,
      )..where((row) => row.parentId.equals(id))).get();
      for (final child in children) {
        await const WikiPageCodec().purge(db, child.id);
      }
      await (db.delete(db.comments)..where(
            (row) =>
                row.itemType.equals(EntityTypes.wikiPage) &
                row.itemId.equals(id),
          ))
          .go();
      await (db.delete(db.wikiPages)..where((row) => row.id.equals(id))).go();
    });
  }

  @override
  Future<StoredItem?> stored(HiwiskiDatabase db, String id) async {
    final row = await (db.select(
      db.wikiPages,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return StoredItem(
      ownerId: row.ownerId,
      version: row.version,
      deleted: row.deletedAt != null,
      containerId: row.parentId,
      entityKey: row.entityKey,
      label: row.title,
      fields: {
        // The properties first: a column of the same name wins, as in [upsert].
        ...?(EntityCodec._json(row.properties) as Map<String, dynamic>?),
        WireFields.position: row.position,
        WireFields.kind: row.kind,
        WireFields.title: row.title,
        WireFields.content: row.content,
        WireFields.tags: EntityCodec._ids(row.tags),
        WireFields.archivedAt: EntityCodec._stamp(row.archivedAt),
        WireFields.archivedBy: row.archivedBy,
      },
    );
  }
}

class CommentCodec extends EntityCodec {
  const CommentCodec();

  @override
  String get entityType => EntityTypes.comment;

  @override
  TableInfo<Table, Object?> table(HiwiskiDatabase db) => db.comments;

  @override
  Future<void> upsert(
    HiwiskiDatabase db, {
    required String id,
    required String ownerId,
    required int version,
    required String? containerId,
    required String? entityKey,
    required Map<String, dynamic> fields,
  }) async {
    final row = CommentsCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      version: Value(version),
      // The owner is in every create mutation; an edit carries only the text — then
      // the owner stays as it was instead of becoming empty.
      itemType: EntityCodec.required(
        fields,
        WireFields.itemType,
        (value) => value as String? ?? '',
      ),
      itemId: EntityCodec.required(
        fields,
        WireFields.itemId,
        (value) => value as String? ?? '',
      ),
      body: EntityCodec.required(
        fields,
        WireFields.body,
        (value) => value as String? ?? '',
      ),
      deletedAt: const Value(null),
    );
    final updated = await (db.update(
      db.comments,
    )..where((c) => c.id.equals(id))).write(row);
    if (updated == 0) {
      await db
          .into(db.comments)
          .insert(
            row.copyWith(
              itemType: Value(fields[WireFields.itemType] as String? ?? ''),
              itemId: Value(fields[WireFields.itemId] as String? ?? ''),
            ),
          );
    }
  }

  @override
  Future<void> markDeleted(HiwiskiDatabase db, String id, int version) =>
      (db.update(db.comments)..where((row) => row.id.equals(id))).write(
        CommentsCompanion(
          deletedAt: Value(clock.now()),
          version: Value(version),
        ),
      );

  @override
  Future<void> purge(HiwiskiDatabase db, String id) =>
      (db.delete(db.comments)..where((row) => row.id.equals(id))).go();

  @override
  Future<StoredItem?> stored(HiwiskiDatabase db, String id) async {
    final row = await (db.select(
      db.comments,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return StoredItem(
      ownerId: row.ownerId,
      version: row.version,
      deleted: row.deletedAt != null,
      label: row.body,
      fields: {
        WireFields.itemType: row.itemType,
        WireFields.itemId: row.itemId,
        WireFields.body: row.body,
      },
    );
  }
}

// --- Boards ----------------------------------------------------------------

class BoardCodec extends EntityCodec {
  const BoardCodec();

  @override
  String get entityType => EntityTypes.board;

  @override
  TableInfo<Table, Object?> table(HiwiskiDatabase db) => db.boards;

  @override
  Future<void> upsert(
    HiwiskiDatabase db, {
    required String id,
    required String ownerId,
    required int version,
    required String? containerId,
    required String? entityKey,
    required Map<String, dynamic> fields,
  }) async {
    await db
        .into(db.boards)
        .insertOnConflictUpdate(
          BoardsCompanion.insert(
            id: id,
            ownerId: ownerId,
            version: Value(version),
            kind: EntityCodec.required(
              fields,
              WireFields.kind,
              (value) => value as String? ?? BoardKinds.start,
            ),
            name: EntityCodec.required(
              fields,
              WireFields.name,
              (value) => value as String? ?? '',
            ),
            layout: EntityCodec.required(
              fields,
              WireFields.layout,
              (value) => value as String? ?? BoardLayouts.flow,
            ),
            columns: EntityCodec.required(
              fields,
              WireFields.columns,
              (value) => (value as num?)?.toInt() ?? 4,
            ),
            token: EntityCodec.optional(
              fields,
              WireFields.token,
              (value) => value as String?,
            ),
            deletedAt: const Value(null),
          ),
        );
  }

  @override
  Future<void> markDeleted(HiwiskiDatabase db, String id, int version) =>
      (db.update(db.boards)..where((row) => row.id.equals(id))).write(
        BoardsCompanion(deletedAt: Value(clock.now()), version: Value(version)),
      );

  @override
  Future<void> purge(HiwiskiDatabase db, String id) async {
    await db.transaction(() async {
      await (db.delete(
        db.widgets,
      )..where((row) => row.boardId.equals(id))).go();
      await (db.delete(db.boards)..where((row) => row.id.equals(id))).go();
    });
  }

  /// Without its token: the server issues the wall tablet's address.
  @override
  Future<StoredItem?> stored(HiwiskiDatabase db, String id) async {
    final row = await (db.select(
      db.boards,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return StoredItem(
      ownerId: row.ownerId,
      version: row.version,
      deleted: row.deletedAt != null,
      label: row.name,
      fields: {
        WireFields.kind: row.kind,
        WireFields.name: row.name,
        WireFields.layout: row.layout,
        WireFields.columns: row.columns,
      },
    );
  }
}

class WidgetCodec extends EntityCodec {
  const WidgetCodec();

  @override
  String get entityType => EntityTypes.widget;

  @override
  TableInfo<Table, Object?> table(HiwiskiDatabase db) => db.widgets;

  @override
  Future<void> upsert(
    HiwiskiDatabase db, {
    required String id,
    required String ownerId,
    required int version,
    required String? containerId,
    required String? entityKey,
    required Map<String, dynamic> fields,
  }) async {
    final row = WidgetsCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      version: Value(version),
      // Kind and board only if they come along. A change that only concerns the
      // configuration or the size does not carry them — and this used to say
      // `?? ''`: every configured tile lost its kind and afterwards showed
      // "your app version does not know this".
      boardId: containerId == null ? const Value.absent() : Value(containerId),
      // An unknown value is **passed through**, not replaced. The UI shows a
      // placeholder for it; an installed app can be older than the server.
      kind: EntityCodec.required(
        fields,
        WireFields.kind,
        (value) => value as String? ?? '',
      ),
      config: EntityCodec.required(
        fields,
        WireFields.config,
        (value) => value == null ? '{}' : jsonEncode(value),
      ),
      gridX: EntityCodec.required(
        fields,
        WireFields.gridX,
        (value) => (value as num?)?.toInt() ?? 0,
      ),
      gridY: EntityCodec.required(
        fields,
        WireFields.gridY,
        (value) => (value as num?)?.toInt() ?? 0,
      ),
      gridW: EntityCodec.required(
        fields,
        WireFields.gridW,
        (value) => (value as num?)?.toInt() ?? 1,
      ),
      gridH: EntityCodec.required(
        fields,
        WireFields.gridH,
        (value) => (value as num?)?.toInt() ?? 1,
      ),
      position: EntityCodec.required(
        fields,
        WireFields.position,
        (value) => (value as num?)?.toInt() ?? 0,
      ),
      deletedAt: const Value(null),
    );
    // Update first, then insert: a change only carries what has changed, and Drift
    // does not accept a row without its required columns as an insert.
    final updated = await (db.update(
      db.widgets,
    )..where((w) => w.id.equals(id))).write(row);
    if (updated == 0) {
      await db
          .into(db.widgets)
          .insert(
            row.copyWith(
              kind: Value(fields[WireFields.kind] as String? ?? ''),
              boardId: Value(containerId ?? ''),
            ),
          );
    }
  }

  @override
  Future<String?> containerOf(HiwiskiDatabase db, String id) async =>
      (await (db.select(
        db.widgets,
      )..where((row) => row.id.equals(id))).getSingleOrNull())?.boardId;

  @override
  Future<void> markDeleted(HiwiskiDatabase db, String id, int version) =>
      (db.update(db.widgets)..where((row) => row.id.equals(id))).write(
        WidgetsCompanion(
          deletedAt: Value(clock.now()),
          version: Value(version),
        ),
      );

  @override
  Future<void> purge(HiwiskiDatabase db, String id) =>
      (db.delete(db.widgets)..where((row) => row.id.equals(id))).go();

  @override
  Future<StoredItem?> stored(HiwiskiDatabase db, String id) async {
    final row = await (db.select(
      db.widgets,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return StoredItem(
      ownerId: row.ownerId,
      version: row.version,
      deleted: row.deletedAt != null,
      containerId: row.boardId,
      label: row.kind,
      fields: {
        WireFields.kind: row.kind,
        WireFields.config: EntityCodec._json(row.config),
        WireFields.gridX: row.gridX,
        WireFields.gridY: row.gridY,
        WireFields.gridW: row.gridW,
        WireFields.gridH: row.gridH,
        WireFields.position: row.position,
      },
    );
  }
}

class TagCodec extends EntityCodec {
  const TagCodec();

  @override
  String get entityType => EntityTypes.tag;

  @override
  TableInfo<Table, Object?> table(HiwiskiDatabase db) => db.tags;

  @override
  Future<void> upsert(
    HiwiskiDatabase db, {
    required String id,
    required String ownerId,
    required int version,
    required String? containerId,
    required String? entityKey,
    required Map<String, dynamic> fields,
  }) async {
    await db
        .into(db.tags)
        .insertOnConflictUpdate(
          TagsCompanion.insert(
            id: id,
            ownerId: ownerId,
            version: Value(version),
            name: EntityCodec.required(
              fields,
              WireFields.name,
              (value) => value as String? ?? '',
            ),
            colorToken: EntityCodec.required(
              fields,
              WireFields.colorToken,
              (value) => value as String? ?? ColorTokens.blue,
            ),
            deletedAt: const Value(null),
          ),
        );
  }

  @override
  Future<void> markDeleted(HiwiskiDatabase db, String id, int version) =>
      (db.update(db.tags)..where((row) => row.id.equals(id))).write(
        TagsCompanion(deletedAt: Value(clock.now()), version: Value(version)),
      );

  @override
  Future<void> purge(HiwiskiDatabase db, String id) =>
      (db.delete(db.tags)..where((row) => row.id.equals(id))).go();

  @override
  Future<StoredItem?> stored(HiwiskiDatabase db, String id) async {
    final row = await (db.select(
      db.tags,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return StoredItem(
      ownerId: row.ownerId,
      version: row.version,
      deleted: row.deletedAt != null,
      label: row.name,
      fields: {
        WireFields.name: row.name,
        WireFields.colorToken: row.colorToken,
      },
    );
  }
}

class ListOrderCodec extends EntityCodec {
  const ListOrderCodec();

  @override
  String get entityType => EntityTypes.listOrder;

  @override
  TableInfo<Table, Object?> table(HiwiskiDatabase db) => db.listOrders;

  @override
  Future<void> upsert(
    HiwiskiDatabase db, {
    required String id,
    required String ownerId,
    required int version,
    required String? containerId,
    required String? entityKey,
    required Map<String, dynamic> fields,
  }) async {
    await db
        .into(db.listOrders)
        .insertOnConflictUpdate(
          ListOrdersCompanion.insert(
            id: id,
            ownerId: ownerId,
            version: Value(version),
            listIds: EntityCodec.required(
              fields,
              WireFields.listIds,
              (value) => jsonEncode(value ?? const <String>[]),
            ),
            deletedAt: const Value(null),
          ),
        );
  }

  @override
  Future<void> markDeleted(HiwiskiDatabase db, String id, int version) =>
      (db.update(db.listOrders)..where((row) => row.id.equals(id))).write(
        ListOrdersCompanion(
          deletedAt: Value(clock.now()),
          version: Value(version),
        ),
      );

  @override
  Future<void> purge(HiwiskiDatabase db, String id) =>
      (db.delete(db.listOrders)..where((row) => row.id.equals(id))).go();

  @override
  Future<StoredItem?> stored(HiwiskiDatabase db, String id) async {
    final row = await (db.select(
      db.listOrders,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return StoredItem(
      ownerId: row.ownerId,
      version: row.version,
      deleted: row.deletedAt != null,
      label: '',
      fields: {WireFields.listIds: EntityCodec._json(row.listIds)},
    );
  }
}

/// All known types.
///
/// **Whatever is missing here, the client skips** — and does a full resync once after
/// an update. That is the price of property 2, and it is low.
const entityCodecs = <EntityCodec>[
  TodoListCodec(),
  TodoCodec(),
  TodoOccurrenceCodec(),
  CalendarCodec(),
  EventCodec(),
  CalendarSubscriptionCodec(),
  CalendarFeedCodec(),
  WikiPageCodec(),
  CommentCodec(),
  BoardCodec(),
  WidgetCodec(),
  TagCodec(),
  ListOrderCodec(),
];
