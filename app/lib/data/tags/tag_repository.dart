import 'package:drift/drift.dart';

import '../../core/common/wire.dart';
import '../../core/db/hiwiski_database.dart';
import '../../core/common/ids.dart';
import '../../core/sync/local_writes.dart';
import '../../domain/tags/tag.dart';
import 'tag_filter_store.dart';

/// Tags — an item of their own with an owner and shares.
///
/// Like every item: the app writes to the local database, the outbox carries it to the
/// server.
class TagRepository {
  TagRepository({
    required this._db,
    required this._writes,
    required this._currentMemberId,
    required this._filters,
  });

  final HiwiskiDatabase _db;
  final LocalWrites _writes;
  final String Function() _currentMemberId;
  final TagFilterStore _filters;

  String get _ownerId => _currentMemberId();

  Stream<List<Tag>> watchTags() =>
      (_db.select(_db.tags)
            ..where((row) => row.deletedAt.isNull())
            ..orderBy([(row) => OrderingTerm.asc(row.name)]))
          .watch()
          .map((rows) => [for (final row in rows) row.toDomain()]);

  /// The most recently used tags.
  ///
  /// Items carry no modification time; the order in which tasks and lists arrived
  /// here (`rowid`) comes closest to it, and it is local — just as "recently used" is
  /// meant to be.
  Stream<List<String>> watchRecent() {
    const query = '''
    SELECT tags FROM (
      SELECT tags, rowid AS r, 1 AS s FROM todos WHERE deleted_at IS NULL AND tags <> ''
      UNION ALL
      SELECT tags, rowid AS r, 0 AS s FROM todo_lists WHERE deleted_at IS NULL AND tags <> ''
    ) ORDER BY s DESC, r DESC LIMIT 40
  ''';
    return _db
        .customSelect(query, readsFrom: {_db.todos, _db.todoLists})
        .watch()
        .map((rows) {
          final seen = <String>{};
          for (final row in rows) {
            seen.addAll(tagIdsOf(row.read<String>(_db.todos.tags.name)));
            if (seen.length >= 6) break;
          }
          return seen.take(6).toList();
        });
  }

  static const _idColumn = 'id';
  static const _countColumn = 'n';

  /// How often each tag is attached to an item that lives on this device.
  Stream<Map<String, int>> watchUsage() {
    // Comma-separated ids: a row counts once per tag. What is counted is what is
    // mirrored here — which is everything the reader is allowed to see.
    const query =
        '''
    SELECT t.id AS $_idColumn, (
      (SELECT COUNT(*) FROM todo_lists x WHERE x.deleted_at IS NULL AND (',' || x.tags || ',') LIKE ('%,' || t.id || ',%')) +
      (SELECT COUNT(*) FROM todos x WHERE x.deleted_at IS NULL AND (',' || x.tags || ',') LIKE ('%,' || t.id || ',%')) +
      (SELECT COUNT(*) FROM events x WHERE x.deleted_at IS NULL AND (',' || x.tags || ',') LIKE ('%,' || t.id || ',%')) +
      (SELECT COUNT(*) FROM wiki_pages x WHERE x.deleted_at IS NULL AND (',' || x.tags || ',') LIKE ('%,' || t.id || ',%')) +
      (SELECT COUNT(*) FROM calendars x WHERE x.deleted_at IS NULL AND (',' || x.tags || ',') LIKE ('%,' || t.id || ',%'))
    ) AS $_countColumn
    FROM tags t WHERE t.deleted_at IS NULL
  ''';
    return _db
        .customSelect(
          query,
          readsFrom: {
            _db.tags,
            _db.todoLists,
            _db.todos,
            _db.events,
            _db.wikiPages,
            // A calendar's tags apply to all its events: a tag set only there is
            // in use, though no item carries it itself.
            _db.calendars,
          },
        )
        .watch()
        .map(
          (rows) => {
            for (final row in rows)
              row.read<String>(_idColumn): row.read<int>(_countColumn),
          },
        );
  }

  Future<String> createTag(
    String name, {
    String colorToken = ColorTokens.blue,
  }) async {
    final id = newId();
    await _writes.run(
      (write) => write.create(
        _db.tags,
        TagsCompanion.insert(
          id: id,
          ownerId: _ownerId,
          name: Value(name),
          colorToken: Value(colorToken),
        ),
        fields: {WireFields.name: name, WireFields.colorToken: colorToken},
        label: name,
      ),
    );
    return id;
  }

  Future<void> updateTag(Tag tag, {String? name, String? colorToken}) async {
    final fields = <String, dynamic>{
      WireFields.name: ?name,
      WireFields.colorToken: ?colorToken,
    };
    if (fields.isEmpty) return;
    await _writes.run(
      (write) => write.change(
        _db.tags,
        TagsCompanion(
          name: name == null ? const Value.absent() : Value(name),
          colorToken: colorToken == null
              ? const Value.absent()
              : Value(colorToken),
        ),
        id: tag.id,
        version: tag.version,
        fields: fields,
        label: tag.name,
      ),
    );
  }

  /// "Deleting removes the tag everywhere; the items stay." The id stays on the items
  /// and is skipped — no rewriting of other people's items, which one would not even
  /// have the share for. It leaves every filter too.
  Future<void> deleteTag(Tag tag) async {
    await _writes.run(
      (write) => write.delete(
        _db.tags,
        id: tag.id,
        version: tag.version,
        label: tag.name,
      ),
    );
    _filters.forget(tag.id);
  }
}

extension on TagRow {
  Tag toDomain() => .new(
    id: id,
    ownerId: ownerId,
    version: version,
    deletedAt: deletedAt,
    name: name,
    colorToken: colorToken,
  );
}
