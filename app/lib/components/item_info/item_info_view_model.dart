import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/repositories.dart';
import '../../app/stores.dart';
import '../../core/common/wire.dart';
import '../../domain/access/access_rules.dart';
import '../../domain/calendar/calendar_items.dart';
import '../../domain/common/item_ref.dart';
import '../../domain/tags/tag.dart';
import '../../domain/todo/todo_items.dart';
import '../../domain/wiki/wiki_page.dart';

part 'item_info_view_model.g.dart';

/// What every item's info area shows besides the screen's own properties.
@immutable
class const ItemInfoState({
  /// `null` where the kind of item has no assignees (a page).
  final List<String>? assignees,

  /// Whether the reader may change [assignees] at all, on top of the screen's
  /// level: a list's assignees get *write* on it, so only its owner assigns.
  final bool assignable = true,

  /// The item's own tags, comma-separated; `null` where the item is gone.
  final String? tags,

  /// Tags that come from elsewhere — an event's calendar.
  final String inheritedTags = '',

  /// Where [inheritedTags] come from.
  final String? inheritedFrom,

  /// Whether links from and to the item are shown — a list's are on its tasks.
  final bool references = true,
});

@riverpod
Stream<Todo?> _todo(Ref ref, String id) =>
    ref.watch(todoRepositoryProvider).watchTodo(id);

@riverpod
Stream<TodoList?> _list(Ref ref, String id) =>
    ref.watch(todoRepositoryProvider).watchList(id);

@riverpod
Stream<CalendarEvent?> _event(Ref ref, String id) =>
    ref.watch(calendarRepositoryProvider).watchEvent(id);

@riverpod
Stream<List<Calendar>> _calendars(Ref ref) =>
    ref.watch(calendarRepositoryProvider).watchCalendars();

@riverpod
Stream<WikiPage?> _page(Ref ref, String id) =>
    ref.watch(wikiRepositoryProvider).watchPage(id);

/// Reads and changes what the info area shows, by the item's type — in one place,
/// so no screen has to.
@riverpod
class ItemInfoViewModel extends _$ItemInfoViewModel {
  @override
  Future<ItemInfoState> build(ItemRef item) async => switch (item.type) {
    EntityTypes.todo => switch (await ref.watch(
      _todoProvider(item.id).future,
    )) {
      final todo? => ItemInfoState(
        assignees: tagIdsOf(todo.assignees),
        tags: todo.tags,
      ),
      null => const ItemInfoState(),
    },
    EntityTypes.todoList => switch (await ref.watch(
      _listProvider(item.id).future,
    )) {
      final list? => ItemInfoState(
        assignees: tagIdsOf(list.assignees),
        assignable: ownsItem(
          list.ownerId,
          ref.watch(sessionProvider.select((s) => s.member?.id)),
        ),
        tags: list.tags,
        references: false,
      ),
      null => const ItemInfoState(references: false),
    },
    EntityTypes.event => switch (await ref.watch(
      _eventProvider(item.id).future,
    )) {
      final event? => await _event(event),
      null => const ItemInfoState(),
    },
    EntityTypes.wikiPage => ItemInfoState(
      tags: (await ref.watch(_pageProvider(item.id).future))?.tags,
    ),
    _ => const ItemInfoState(),
  };

  Future<ItemInfoState> _event(CalendarEvent event) async {
    final calendar = (await ref.watch(_calendarsProvider.future))
        .where((candidate) => candidate.id == event.calendarId)
        .firstOrNull;
    return ItemInfoState(
      assignees: tagIdsOf(event.attendees),
      tags: event.tags,
      inheritedTags: calendar?.tags ?? '',
      inheritedFrom: calendar?.name,
    );
  }

  Future<void> setAssignees(Set<String> assignees) async {
    final next = assignees.toList();
    switch (item.type) {
      case EntityTypes.todo:
        if (await ref.read(_todoProvider(item.id).future) case final todo?) {
          await ref
              .read(todoRepositoryProvider)
              .updateTodo(todo, assignees: next);
        }
      case EntityTypes.todoList:
        if (await ref.read(_listProvider(item.id).future) case final list?) {
          await ref
              .read(todoRepositoryProvider)
              .updateList(list, assignees: next);
        }
      case EntityTypes.event:
        if (await ref.read(_eventProvider(item.id).future) case final event?) {
          await ref
              .read(calendarRepositoryProvider)
              .setEventAttendees(event, next);
        }
    }
  }

  Future<void> setTags(List<String> tags) async {
    switch (item.type) {
      case EntityTypes.todo:
        if (await ref.read(_todoProvider(item.id).future) case final todo?) {
          await ref.read(todoRepositoryProvider).updateTodo(todo, tags: tags);
        }
      case EntityTypes.todoList:
        if (await ref.read(_listProvider(item.id).future) case final list?) {
          await ref.read(todoRepositoryProvider).updateList(list, tags: tags);
        }
      case EntityTypes.event:
        if (await ref.read(_eventProvider(item.id).future) case final event?) {
          await ref.read(calendarRepositoryProvider).setEventTags(event, tags);
        }
      case EntityTypes.wikiPage:
        if (await ref.read(_pageProvider(item.id).future) case final page?) {
          await ref.read(wikiRepositoryProvider).updatePage(page, tags: tags);
        }
    }
  }
}
