import 'package:drift/drift.dart';

import '../../core/api/hiwiski_api.dart';
import '../../core/api/hiwiski_failure.dart';
import '../../core/common/wire.dart';
import '../../core/db/hiwiski_database.dart';
import '../../domain/calendar/calendar_tags.dart';
import '../../domain/search/search_models.dart';

/// Search — **online via the server, offline via the device**.
///
/// "On the server, search runs over a maintained index, on the client over FTS5.
/// **Both halves must answer the same question the same way**; in an earlier version the device
/// did not find 'Termin' when you typed 'Termine', the server did."
///
/// That is why the local half also searches with **prefix and word part**: "kin" hits
/// while typing, "kinder" finds "Kinderarzt". What remains is inflection — SQLite has
/// no German stemmer, and a word list of our own would be a second truth about the
/// German language. The difference is accepted.
///
/// **Without a server** the device's half is the whole search — and no
/// "offline" note: there is nothing else it could find.
class SearchRepository {
  SearchRepository({
    required this._db,
    required this._api,
    required this._serverless,
  });

  final HiwiskiDatabase _db;
  final HiwiskiApi _api;
  final bool _serverless;

  /// Searches — first on the server, on the device if the server is unreachable.
  ///
  /// The archive is left out unless [includeArchived] — on both halves alike.
  Future<SearchOutcome> search(
    String query, {
    Set<String> types = const {},
    bool includeArchived = false,
  }) async {
    final term = query.trim();
    if (term.isEmpty) return const SearchOutcome(hits: [], offline: false);
    if (_serverless) {
      return SearchOutcome(
        hits: await _local(term, types, includeArchived),
        offline: false,
      );
    }

    try {
      final result = await HiwiskiApi.run(
        () => _api.search.search(
          q: term,
          types: types.isEmpty ? null : types.toList(),
          includeArchived: includeArchived,
        ),
      );
      return SearchOutcome(
        hits: [for (final hit in result.hits) SearchHitView.fromApi(hit)],
        jumpTo: switch (result.jumpTo) {
          null => null,
          final jumpTo => SearchHitView.fromApi(jumpTo),
        },
        offline: false,
      );
    } on HiwiskiFailure catch (failure) {
      if (!failure.isNetwork) rethrow;
      // **Offline the client searches what is on the device** — with an honest note
      // saying so. An empty result then means "not found here"
      // and not "does not exist".
      return SearchOutcome(
        hits: await _local(term, types, includeArchived),
        offline: true,
      );
    }
  }

  /// Tags and kind of the hits, from the local mirror.
  ///
  /// For the tag chips and for "Recipes" as a type of its own in the filter bar: the
  /// server knows recipes as wiki pages, the UI separates them.
  Future<Map<String, ({String tags, bool recipe})>> facts(
    List<SearchHitView> hits,
  ) async {
    final ids = hits.map((hit) => hit.itemId).toSet().toList();
    if (ids.isEmpty) return const {};
    final result = <String, ({String tags, bool recipe})>{};
    final todos = await (_db.select(
      _db.todos,
    )..where((r) => r.id.isIn(ids))).get();
    final listTags = {
      for (final list
          in await (_db.select(_db.todoLists)..where(
                (r) => r.id.isIn({for (final todo in todos) todo.listId}),
              ))
              .get())
        list.id: list.tags,
    };
    for (final row in todos) {
      // Its list's tags count too, as on the Tasks screen — as an event's calendar's
      // do. Without them a "Work" filter dropped every task of the "Office" list.
      result[row.id] = (
        tags: combinedEventTags(row.tags, listTags[row.listId]),
        recipe: false,
      );
    }
    for (final row in await (_db.select(
      _db.todoLists,
    )..where((r) => r.id.isIn(ids))).get()) {
      result[row.id] = (tags: row.tags, recipe: false);
    }
    final calendars = {
      for (final calendar in await _db.select(_db.calendars).get())
        calendar.id: calendar,
    };
    for (final row in await (_db.select(
      _db.events,
    )..where((r) => r.id.isIn(ids))).get()) {
      // Its calendar's tags count too (calendar_tags.dart).
      result[row.id] = (
        tags: combinedEventTags(row.tags, calendars[row.calendarId]?.tags),
        recipe: false,
      );
    }
    for (final row in await (_db.select(
      _db.wikiPages,
    )..where((r) => r.id.isIn(ids))).get()) {
      result[row.id] = (tags: row.tags, recipe: row.kind == PageKinds.recipe);
    }
    return result;
  }

  /// The local half.
  ///
  /// Over the mirrored tables instead of a separate FTS index: the data on the device is
  /// small — one family, not an archive — and a second index would be a second place
  /// that has to be kept up to date on every sync and at some point would not
  /// be.
  Future<List<SearchHitView>> _local(
    String term,
    Set<String> types,
    bool includeArchived,
  ) async {
    // Compared in Dart, not with SQLite's `lower()`: that folds ASCII only, so
    // "Übung" never matched "übung" here while the server found it. The device holds
    // one family's data — reading the live rows is cheap. `%` and `_` are plain text.
    final needle = term.toLowerCase();
    bool matches(String? text) =>
        text != null && text.toLowerCase().contains(needle);
    final hits = <SearchHitView>[];

    bool wanted(String type) => types.isEmpty || types.contains(type);

    if (wanted(EntityTypes.todo)) {
      // A task is archived with its list — it carries no flag of its own.
      final archivedLists = {
        for (final list in await (_db.select(
          _db.todoLists,
        )..where((row) => row.archivedAt.isNotNull())).get())
          list.id,
      };
      final rows = await (_db.select(
        _db.todos,
      )..where((row) => row.deletedAt.isNull())).get();
      for (final row in rows) {
        if (!matches(row.title)) continue;
        final archived = archivedLists.contains(row.listId);
        if (archived && !includeArchived) continue;
        hits.add(
          SearchHitView(
            itemType: EntityTypes.todo,
            itemId: row.id,
            title: row.title,
            entityKey: row.entityKey,
            snippet: row.description,
            archived: archived,
          ),
        );
      }
    }

    if (wanted(EntityTypes.todoList)) {
      final rows =
          await (_db.select(_db.todoLists)
                ..where((row) => row.deletedAt.isNull())
                ..where(
                  (row) => includeArchived
                      ? const Constant(true)
                      : row.archivedAt.isNull(),
                ))
              .get();
      for (final row in rows) {
        if (!matches(row.name)) continue;
        hits.add(
          SearchHitView(
            itemType: EntityTypes.todoList,
            itemId: row.id,
            title: row.name,
            snippet: row.description,
            archived: row.archivedAt != null,
          ),
        );
      }
    }

    if (wanted(EntityTypes.event)) {
      final rows = await (_db.select(
        _db.events,
      )..where((row) => row.deletedAt.isNull())).get();
      for (final row in rows) {
        if (!matches(row.title)) continue;
        hits.add(
          SearchHitView(
            itemType: EntityTypes.event,
            itemId: row.id,
            title: row.title,
            entityKey: row.entityKey,
            snippet: row.location,
          ),
        );
      }
    }

    if (wanted(EntityTypes.wikiPage)) {
      final rows =
          await (_db.select(_db.wikiPages)
                ..where((row) => row.deletedAt.isNull())
                ..where(
                  (row) => includeArchived
                      ? const Constant(true)
                      : row.archivedAt.isNull(),
                ))
              .get();
      for (final row in rows) {
        if (!matches(row.title) && !matches(row.content)) continue;
        hits.add(
          SearchHitView(
            itemType: EntityTypes.wikiPage,
            itemId: row.id,
            title: row.title,
            entityKey: row.entityKey,
            snippet: _snippet(row.content, term),
            archived: row.archivedAt != null,
          ),
        );
      }
    }

    hits.sort((a, b) => a.title.compareTo(b.title));
    return hits;
  }

  /// The snippet: the sentence around the match.
  static String? _snippet(String body, String term) {
    if (body.trim().isEmpty) return null;
    final at = body.toLowerCase().indexOf(term.toLowerCase());
    if (at < 0) return body.length <= 160 ? body : '${body.substring(0, 160)}…';
    final from = (at - 40).clamp(0, body.length);
    final to = (at + term.length + 80).clamp(0, body.length);
    return '${from > 0 ? '…' : ''}${body.substring(from, to)}${to < body.length ? '…' : ''}';
  }
}
