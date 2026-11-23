import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/common/wire.dart';
import '../domain/calendar/calendar_items.dart';
import '../domain/links/link_index.dart';
import '../domain/wiki/wiki_page.dart';
import 'repositories.dart';

part 'link_index.g.dart';

// The link index: derived from several repositories, so it is composed here, in the
// composition root. The ViewModels read
// [linkIndexProvider] like any store's value.
//
// One stream per table instead of one query across all of them: each kind of item
// brings its own, and a hand-written `UNION` would be exactly the enumeration that the
// module inversion avoids on the server. Riverpod pauses the streams while nothing
// shows the index.

@Riverpod(keepAlive: true)
Stream<List<LinkItem>> _linkTodos(Ref ref) {
  final repository = ref.watch(todoRepositoryProvider);
  // A task is archived with its list and carries no flag itself.
  final archivedLists = ref.watch(_archivedListIdsProvider).value ?? const {};
  return repository.watchAllTodos().map(
    (todos) => [
      for (final todo in todos)
        LinkItem(
          itemType: EntityTypes.todo,
          itemId: todo.id,
          title: todo.title,
          entityKey: todo.entityKey,
          text: todo.description,
          containerId: todo.listId,
          archived: archivedLists.contains(todo.listId),
        ),
    ],
  );
}

@Riverpod(keepAlive: true)
Stream<Set<String>> _archivedListIds(Ref ref) =>
    ref.watch(todoRepositoryProvider).watchArchivedListIds();

@Riverpod(keepAlive: true)
Stream<List<WikiPage>> _pages(Ref ref) =>
    ref.watch(wikiRepositoryProvider).watchPages();

@Riverpod(keepAlive: true)
List<LinkItem> _linkPages(Ref ref) => [
  for (final page in ref.watch(_pagesProvider).value ?? const <WikiPage>[])
    LinkItem(
      itemType: EntityTypes.wikiPage,
      itemId: page.id,
      title: page.title,
      entityKey: page.entityKey,
      text: page.content,
      containerId: page.parentId,
      archived: page.archivedAt != null,
    ),
];

@Riverpod(keepAlive: true)
Stream<List<CalendarEvent>> _events(Ref ref) =>
    ref.watch(calendarRepositoryProvider).watchEvents();

@Riverpod(keepAlive: true)
List<LinkItem> _linkEvents(Ref ref) => [
  for (final event
      in ref.watch(_eventsProvider).value ?? const <CalendarEvent>[])
    LinkItem(
      itemType: EntityTypes.event,
      itemId: event.id,
      title: event.title,
      entityKey: event.entityKey,
      text: event.description,
      containerId: event.calendarId,
    ),
];

/// Lists by their address or their number (`#LST-3`).
@Riverpod(keepAlive: true)
Stream<List<LinkItem>> _linkLists(Ref ref) => ref
    .watch(todoRepositoryProvider)
    .watchAllLists()
    .map(
      (lists) => [
        for (final list in lists)
          LinkItem(
            itemType: EntityTypes.todoList,
            itemId: list.id,
            title: list.name,
            entityKey: list.entityKey,
            text: list.description,
            archived: list.archivedAt != null,
          ),
      ],
    );

/// Comments speak for the item they are on.
@Riverpod(keepAlive: true)
Stream<List<AttachedText>> _linkComments(Ref ref) => ref
    .watch(wikiRepositoryProvider)
    .watchAllComments()
    .map(
      (comments) => [
        for (final comment in comments)
          AttachedText(
            itemType: comment.itemType,
            itemId: comment.itemId,
            text: comment.body,
          ),
      ],
    );

/// A mind map speaks for its page: a link on the canvas is one from the page, as on the
/// server — a note's text, and the address a link element points to. Not the member
/// an element shows: no item the page links to.
@Riverpod(keepAlive: true)
Stream<List<AttachedText>> _linkMindmaps(Ref ref) => ref
    .watch(mindmapRepositoryProvider)
    .watchAllNodes()
    .map(
      (nodes) => [
        for (final node in nodes)
          if (node.text.isNotEmpty || node.kind == MindmapKinds.link)
            AttachedText(
              itemType: EntityTypes.wikiPage,
              itemId: node.pageId,
              text: [
                node.text,
                if (node.kind == MindmapKinds.link) ?node.target,
              ].join('\n'),
            ),
      ],
    );

/// A connection's label speaks for its page as well — the server counts it as one of
/// the page's texts, and a link written there showed at its target only once the
/// server's links were asked for.
@Riverpod(keepAlive: true)
Stream<List<AttachedText>> _linkMindmapLabels(Ref ref) => ref
    .watch(mindmapRepositoryProvider)
    .watchAllLabelledEdges()
    .map(
      (edges) => [
        for (final edge in edges)
          AttachedText(
            itemType: EntityTypes.wikiPage,
            itemId: edge.pageId,
            text: edge.text,
          ),
      ],
    );

/// What the texts reference, kept across rebuilds of [linkIndex] (see [ReferenceCache]).
@Riverpod(keepAlive: true)
ReferenceCache _references(Ref ref) => .new();

@Riverpod(keepAlive: true)
LinkIndex linkIndex(Ref ref) => .from(
  [
    ...?ref.watch(_linkTodosProvider).value,
    ...?ref.watch(_linkListsProvider).value,
    ...ref.watch(_linkPagesProvider),
    ...ref.watch(_linkEventsProvider),
  ],
  attached: [
    ...?ref.watch(_linkCommentsProvider).value,
    ...?ref.watch(_linkMindmapsProvider).value,
    ...?ref.watch(_linkMindmapLabelsProvider).value,
  ],
  references: ref.read(_referencesProvider),
);
