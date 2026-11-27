import 'dart:async';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/api/generated/export.dart';
import '../../core/api/hiwiski_api.dart';
import '../../core/common/wire.dart';
import '../../core/db/hiwiski_database.dart';
import '../../core/common/ids.dart';
import '../../core/sync/local_writes.dart';
import '../../domain/wiki/comment.dart';
import '../../domain/wiki/markdown_editing.dart';
import '../../domain/wiki/wiki_page.dart';

/// Wiki pages and recipes — **always against the local database**.
///
/// Only the revisions and the recipe import go over REST: revisions never change, can
/// be arbitrarily long and are rarely needed, and an import fetches
/// a foreign page — something no device on the home network can do.
///
/// **References do not go over REST**: they live in the text of the mirrored items and
/// are derived from it (`core/links`). A call for them would be a second path to
/// something that is already here — and it would not work offline.
class WikiRepository {
  WikiRepository({
    required this._db,
    required this._writes,
    required this._api,
    required this._currentMemberId,
    Duration Function()? undoWindow,
  }) : _undoWindow = undoWindow ?? _defaultUndoWindow;

  /// How long "Undo" shows on this device (Account → Customize) — a deletion waits
  /// that long, and a little more, before it goes out.
  final Duration Function() _undoWindow;

  static Duration _defaultUndoWindow() => const .new(seconds: 8);

  final HiwiskiDatabase _db;
  final LocalWrites _writes;
  final HiwiskiApi _api;
  final String Function() _currentMemberId;

  String get _ownerId => _currentMemberId();

  // --- Reading -------------------------------------------------------------------

  Stream<List<WikiPage>> watchPages() =>
      (_db.select(_db.wikiPages)
            ..where((row) => row.deletedAt.isNull())
            ..orderBy([
              (row) => OrderingTerm.asc(row.position),
              (row) => OrderingTerm.asc(row.title),
            ]))
          .watch()
          .map((rows) => [for (final row in rows) row.toDomain()]);

  Stream<WikiPage?> watchPage(String pageId) =>
      (_db.select(_db.wikiPages)..where((row) => row.id.equals(pageId)))
          .watchSingleOrNull()
          .map((row) => row?.toDomain());

  Stream<List<Comment>> watchComments(String itemType, String itemId) =>
      (_db.select(_db.comments)
            ..where(
              (row) =>
                  row.itemType.equals(itemType) &
                  row.itemId.equals(itemId) &
                  row.deletedAt.isNull(),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.id)]))
          .watch()
          .map((rows) => [for (final row in rows) row.toDomain()]);

  /// Every comment on the device, whatever it is on — for the link index.
  Stream<List<Comment>> watchAllComments() =>
      (_db.select(_db.comments)..where((row) => row.deletedAt.isNull()))
          .watch()
          .map((rows) => [for (final row in rows) row.toDomain()]);

  // --- Writing -------------------------------------------------------------------

  /// Creates a page — at the start of its siblings unless [position] says where: an
  /// import puts its pages in the order they were exported in.
  Future<String> createPage({
    required String title,
    String? parentId,
    String kind = PageKinds.page,
    int? position,
  }) async {
    final id = newId();
    final fields = <String, dynamic>{
      WireFields.title: title,
      WireFields.kind: kind,
      WireFields.content: '',
      WireFields.position: ?position,
    };

    await _writes.run(
      (write) => write.create(
        _db.wikiPages,
        WikiPagesCompanion.insert(
          id: id,
          ownerId: _ownerId,
          parentId: Value(parentId),
          kind: Value(kind),
          title: Value(title),
          position: position == null ? const Value.absent() : Value(position),
        ),
        fields: fields,
        containerType: parentId == null ? null : EntityTypes.wikiPage,
        containerId: parentId,
        // A subpage in a page created offline must not go through if the parent page
        // fails permanently.
        after: parentId,
        label: title,
      ),
    );
    return id;
  }

  /// Changes a page of any kind — each field only if given. [properties] are what
  /// the page's kind adds, by their names on the wire, `null` clearing one;
  /// each goes out as a field of its own. The parent changes through
  /// [movePage].
  Future<void> updatePage(
    WikiPage page, {
    String? title,
    String? content,
    Map<String, Object?> properties = const {},
    List<String>? tags,
  }) {
    final fields = <String, dynamic>{
      WireFields.title: ?title,
      WireFields.content: ?content,
      ...properties,
      WireFields.tags: ?tags,
    };
    return fields.isEmpty
        ? Future.value()
        : _writes.run((write) => _writePage(write, page, fields));
  }

  /// Ticks or unticks the [index]-th box of the page **as it is now** — read in the
  /// same transaction as the write. Two quick taps both started from the content the
  /// screen had shown, and the second write took the first one back.
  Future<void> toggleTaskAt(WikiPage page, int index) =>
      _writes.run((write) async {
        final current = await (_db.select(
          _db.wikiPages,
        )..where((row) => row.id.equals(page.id))).getSingleOrNull();
        final content = current?.content ?? page.content;
        await _writePage(write, page, {
          WireFields.content: toggleTask(content, index),
        });
      });

  /// The fields a page keeps in columns; every other one is a property of its kind.
  static const _columnFields = {
    WireFields.title,
    WireFields.content,
    WireFields.position,
    WireFields.parentId,
    WireFields.tags,
    WireFields.kind,
    WireFields.archivedAt,
    WireFields.archivedBy,
  };

  Future<void> _writePage(
    LocalWrite write,
    WikiPage page,
    Map<String, dynamic> fields,
  ) async {
    final properties = {
      for (final MapEntry(:key, :value) in fields.entries)
        if (!_columnFields.contains(key)) key: value,
    };
    // Laid over the properties **as they are now**, read in the same transaction —
    // another field changed meanwhile stays.
    final stored = properties.isEmpty
        ? null
        : (await (_db.select(
                    _db.wikiPages,
                  )..where((row) => row.id.equals(page.id))).getSingleOrNull())
                  ?.properties ??
              page.properties;
    await write.change(
      _db.wikiPages,
      WikiPagesCompanion(
        title: _string(fields, WireFields.title),
        content: _string(fields, WireFields.content),
        position: switch (fields[WireFields.position]) {
          final int position => Value(position),
          _ => const Value.absent(),
        },
        parentId: fields.containsKey(WireFields.parentId)
            ? Value(fields[WireFields.parentId] as String?)
            : const Value.absent(),
        tags: fields.containsKey(WireFields.tags)
            ? Value((fields[WireFields.tags] as List?)?.join(',') ?? '')
            : const Value.absent(),
        properties: stored == null
            ? const Value.absent()
            : Value(mergeProperties(stored, properties)),
      ),
      id: page.id,
      version: page.version,
      fields: fields,
      containerType: page.parentId == null ? null : EntityTypes.wikiPage,
      containerId: page.parentId,
      label: page.title,
    );
  }

  /// Moves a branch.
  ///
  /// The shares realign afterwards: an **own** share survives the move, an inherited
  /// one comes from the new place. The server computes that — here only
  /// the pointer moves.
  Future<void> movePage(WikiPage page, String? newParentId) async {
    if (newParentId == page.id) return;
    await _writes.run(
      (write) => write.change(
        _db.wikiPages,
        WikiPagesCompanion(parentId: Value(newParentId)),
        id: page.id,
        version: page.version,
        fields: {WireFields.parentId: newParentId},
        containerType: newParentId == null ? null : EntityTypes.wikiPage,
        containerId: newParentId,
        label: page.title,
      ),
    );
  }

  /// A page dragged in the tree: under [parentId] (`null`: the root) if that differs
  /// from where it is, and the positions given — page id → position, the moved page
  /// and the siblings that had to make room. In one go, so the row never shows half
  /// moved.
  ///
  /// A new parent goes out like [movePage]: the shares realign on the server.
  Future<void> arrangePages({
    required WikiPage moved,
    required String? parentId,
    required Map<String, int> positions,
    required List<WikiPage> siblings,
  }) => _writes.run((write) async {
    final reparent = parentId != moved.parentId;
    final position = positions[moved.id];
    if (reparent) {
      await write.change(
        _db.wikiPages,
        WikiPagesCompanion(
          parentId: Value(parentId),
          position: position == null ? const Value.absent() : Value(position),
        ),
        id: moved.id,
        version: moved.version,
        fields: {WireFields.parentId: parentId, WireFields.position: ?position},
        containerType: parentId == null ? null : EntityTypes.wikiPage,
        containerId: parentId,
        label: moved.title,
      );
    } else if (position != null) {
      await _writePage(write, moved, {WireFields.position: position});
    }
    for (final page in siblings) {
      if (page.id == moved.id) continue;
      if (positions[page.id] case final position?) {
        await _writePage(write, page, {WireFields.position: position});
      }
    }
  });

  /// The pages below [page], at any depth — for "with its subpages".
  Future<List<WikiPage>> _subtree(WikiPage page) async {
    final below = <WikiPage>[];
    final seen = <String>{page.id};
    Future<void> collect(String id) async {
      final children =
          await (_db.select(_db.wikiPages)..where(
                (row) => row.parentId.equals(id) & row.deletedAt.isNull(),
              ))
              .get();
      for (final child in children) {
        // The cycle guard as in [breadcrumbOf]: offline moves can build one.
        if (!seen.add(child.id)) continue;
        below.add(child.toDomain());
        await collect(child.id);
      }
    }

    await collect(page.id);
    return below;
  }

  /// Archives the page — alone, or with every subpage that is not archived yet.
  ///
  /// Per page, not inherited: the flag is written on each page, so "only this page" is
  /// expressible and a subpage left active keeps its place under its parent.
  ///
  /// Returns the pages it archived — for "Undo", which must bring back exactly these
  /// and not a subpage someone archived on its own before.
  Future<List<WikiPage>> archivePage(
    WikiPage page, {
    bool withSubpages = false,
  }) async {
    final pages = [
      page,
      if (withSubpages)
        ...(await _subtree(page)).where((row) => row.archivedAt == null),
    ];
    await _setArchived(pages, archived: true);
    return pages;
  }

  /// Restores exactly these pages — the "Undo" after [archivePage].
  Future<void> restorePages(List<WikiPage> pages) =>
      _setArchived(pages, archived: false);

  /// Restores the page — alone, or with its archived subpages.
  Future<void> restorePage(WikiPage page, {bool withSubpages = false}) async {
    final pages = [
      page,
      if (withSubpages)
        ...(await _subtree(page)).where((row) => row.archivedAt != null),
    ];
    await _setArchived(pages, archived: false);
  }

  Future<void> _setArchived(
    List<WikiPage> pages, {
    required bool archived,
  }) async {
    final at = archived ? clock.now() : null;
    final by = archived ? _ownerId : null;
    await _writes.run((write) async {
      for (final page in pages) {
        await write.change(
          _db.wikiPages,
          WikiPagesCompanion(archivedAt: Value(at), archivedBy: Value(by)),
          id: page.id,
          version: page.version,
          fields: {
            WireFields.archivedAt: at?.toUtc().toIso8601String(),
            WireFields.archivedBy: by,
          },
          containerType: page.parentId == null ? null : EntityTypes.wikiPage,
          containerId: page.parentId,
          label: page.title,
        );
      }
    });
  }

  /// A deleted branch takes everything below it along — recursively. Only the page
  /// itself goes out; the server deletes the branch below it the same way.
  Future<void> deletePage(WikiPage page) async {
    final now = clock.now();
    await _writes.run((write) async {
      final deleted = await write.delete(
        _db.wikiPages,
        id: page.id,
        version: page.version,
        label: page.title,
        at: now,
      );
      // Each page once: two devices moving pages in opposite directions offline can
      // build a parent cycle, and the walk then recursed until the stack overflowed —
      // inside the transaction, so the delete never happened.
      final seen = <String>{};
      final queue = <String>[page.id];
      while (queue.isNotEmpty) {
        final id = queue.removeLast();
        if (!seen.add(id)) continue;
        if (id != page.id) {
          await write.cascade(
            deleted,
            _db.wikiPages,
            WikiPagesCompanion(deletedAt: Value(now)),
            where: (row) => row.id.equals(id),
          );
        }
        // A pinboard goes with its page — and comes back with it from the trash.
        await write.cascade(
          deleted,
          _db.pinboardEdges,
          PinboardEdgesCompanion(deletedAt: Value(now)),
          where: (row) => row.pageId.equals(id) & row.deletedAt.isNull(),
        );
        await write.cascade(
          deleted,
          _db.pinboardNodes,
          PinboardNodesCompanion(deletedAt: Value(now)),
          where: (row) => row.pageId.equals(id) & row.deletedAt.isNull(),
        );
        final children = await (_db.select(
          _db.wikiPages,
        )..where((row) => row.parentId.equals(id))).get();
        queue.addAll(children.map((child) => child.id));
      }
    });
  }

  // --- Comments ------------------------------------------------------------------

  Future<void> addComment({
    required String itemType,
    required String itemId,
    required String body,
  }) async {
    final id = newId();
    await _writes.run(
      (write) => write.create(
        _db.comments,
        CommentsCompanion.insert(
          id: id,
          ownerId: _ownerId,
          itemType: itemType,
          itemId: itemId,
          body: Value(body),
        ),
        fields: {
          WireFields.itemType: itemType,
          WireFields.itemId: itemId,
          WireFields.body: body,
        },
        // The carrier as container: the server uses it to check whether whoever tries
        // may comment — whoever may read may comment.
        containerType: itemType,
        containerId: itemId,
        label: body,
      ),
    );
  }

  /// One's own comment, with a new [body].
  Future<void> updateComment(Comment comment, {required String body}) async {
    await _writes.run(
      (write) => write.change(
        _db.comments,
        CommentsCompanion(body: Value(body)),
        id: comment.id,
        version: comment.version,
        fields: {WireFields.body: body},
        containerType: comment.itemType,
        containerId: comment.itemId,
        label: body,
      ),
    );
  }

  /// Comments deleted a moment ago, still to be taken back: id → the timer that
  /// deletes them for good — as with a task deleted from its row.
  final _pendingCommentDeletes = <String, Timer>{};
  final _pendingCommentChanges = StreamController<Set<String>>.broadcast();

  /// How long a deleted comment can be taken back — as long as a task.
  Duration get deleteGrace => _undoWindow() + _graceBeyondUndo;

  /// A little longer than "Undo" shows: tapped in its last moment, it still works.
  static const _graceBeyondUndo = Duration(milliseconds: 500);

  /// The comments deleted but still to be taken back — what the lists leave out.
  Stream<Set<String>> watchPendingCommentDeletes() async* {
    yield {..._pendingCommentDeletes.keys};
    yield* _pendingCommentChanges.stream;
  }

  void _pendingCommentsChanged() =>
      _pendingCommentChanges.add({..._pendingCommentDeletes.keys});

  /// Deletes [comment] after [deleteGrace] unless [undoDeleteComment] comes first.
  /// The timer lives here, not with the screen: leaving the page does not keep it.
  void deleteCommentSoon(Comment comment) {
    _pendingCommentDeletes[comment.id]?.cancel();
    _pendingCommentDeletes[comment.id] = Timer(
      deleteGrace,
      () => unawaited(_deleteCommentNow(comment.id)),
    );
    _pendingCommentsChanged();
  }

  /// The moment has passed: deletes the comment as it is now. Runs on a timer: a
  /// failure is logged, not thrown.
  Future<void> _deleteCommentNow(String commentId) async {
    _pendingCommentDeletes.remove(commentId);
    try {
      final current = await (_db.select(
        _db.comments,
      )..where((row) => row.id.equals(commentId))).getSingleOrNull();
      if (current != null && current.deletedAt == null) {
        await deleteComment(current.toDomain());
      }
    } catch (error) {
      debugPrint('hiwiski: deleting a comment failed: $error');
    } finally {
      _pendingCommentsChanged();
    }
  }

  /// Takes a comment's deletion back while it can be.
  void undoDeleteComment(String commentId) {
    _pendingCommentDeletes.remove(commentId)?.cancel();
    _pendingCommentsChanged();
  }

  Future<void> deleteComment(Comment comment) async {
    await _writes.run(
      (write) => write.delete(
        _db.comments,
        id: comment.id,
        version: comment.version,
        label: comment.body,
      ),
    );
  }

  // --- Over REST -----------------------------------------------------------------

  Future<List<Revision>> revisions(String pageId) async {
    final result = await HiwiskiApi.run(
      () => _api.wiki.listRevisions(pageId: pageId),
    );
    return result.revisions;
  }

  Future<Revision> revision(String pageId, String revisionId) => HiwiskiApi.run(
    () => _api.wiki.getRevision(pageId: pageId, revisionId: revisionId),
  );

  Future<ParsedRecipe> importRecipe(String url) => HiwiskiApi.run(
    () => _api.wiki.importRecipe(body: ImportRecipeRequest(url: url)),
  );

  Future<List<Product>> products({String? query}) async {
    final result = await HiwiskiApi.run(
      () => _api.catalog.listProducts(query: query),
    );
    return result.products;
  }

  static Value<String> _string(Map<String, dynamic> fields, String name) =>
      fields.containsKey(name)
      ? .new(fields[name] as String? ?? '')
      : const .absent();
}

extension on WikiPageRow {
  WikiPage toDomain() => .new(
    id: id,
    ownerId: ownerId,
    version: version,
    deletedAt: deletedAt,
    parentId: parentId,
    position: position,
    kind: kind,
    entityKey: entityKey,
    title: title,
    content: content,
    tags: tags,
    properties: properties,
    archivedAt: archivedAt,
    archivedBy: archivedBy,
  );
}

extension on CommentRow {
  Comment toDomain() => .new(
    id: id,
    ownerId: ownerId,
    version: version,
    deletedAt: deletedAt,
    itemType: itemType,
    itemId: itemId,
    body: body,
  );
}
