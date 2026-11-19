import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../core/api/generated/export.dart';
import '../../../core/common/wire.dart';
import '../../../domain/calendar/calendar_items.dart';
import '../../../domain/todo/todo_models.dart';
import '../../../domain/wiki/wiki_page.dart';

part 'trash_view_model.g.dart';

/// The trash, as the server sees it — fetched again whenever it is shown.
@immutable
class const TrashState({
  required final TrashList trash,
  required final Map<String, Member> members,
});

/// A container an item can go back to when its own is gone.
typedef RestoreTarget = ({String id, String name});

@riverpod
Stream<TrashList> _trash(Ref ref) =>
    ref.watch(adminRepositoryProvider).watchTrash();

@riverpod
Stream<List<Member>> _members(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchMembers();

@riverpod
Stream<List<TodoListSummary>> _lists(Ref ref) =>
    ref.watch(todoRepositoryProvider).watchLists();

@riverpod
Stream<List<Calendar>> _calendars(Ref ref) =>
    ref.watch(calendarRepositoryProvider).watchCalendars();

@riverpod
Stream<List<WikiPage>> _pages(Ref ref) =>
    ref.watch(wikiRepositoryProvider).watchPages();

@riverpod
class TrashViewModel extends _$TrashViewModel {
  /// The trash is what the screen is about: it is waited for, even from the server
  /// — offline the screen says so. The names are not.
  @override
  Future<TrashState> build() async {
    final members = ref.watch(_membersProvider).value ?? const <Member>[];
    return TrashState(
      trash: await ref.watch(_trashProvider.future),
      members: {for (final member in members) member.id: member},
    );
  }

  /// Asks the server again — after the trash could not be fetched.
  void retry() => ref.invalidate(_trashProvider);

  /// Restores an item — it comes back to the device the normal way, through sync.
  /// [targetContainerId] is where it goes when its old container is gone.
  Future<void> restore(TrashEntry entry, {String? targetContainerId}) async {
    final sync = ref.read(syncRepositoryProvider);
    await ref
        .read(adminRepositoryProvider)
        .restoreFromTrash(
          entry.itemType,
          entry.itemId,
          targetContainerId: targetContainerId,
        );
    // The restore is done; the sync that brings it reports its own failure. Awaited,
    // a 503 there turned a successful restore into an error on the screen.
    sync.syncNow().ignore();
  }
}

/// The containers "Restore to …" offers for an item of [itemType]: lists for a task,
/// the family's own calendars for an event, the pages for a page.
@riverpod
class RestoreTargetsViewModel extends _$RestoreTargetsViewModel {
  @override
  Future<List<RestoreTarget>> build(String itemType) async =>
      switch (itemType) {
        EntityTypes.todo => [
          for (final summary in await ref.watch(_listsProvider.future))
            (id: summary.list.id, name: summary.list.name),
        ],
        EntityTypes.event => [
          for (final calendar in await ref.watch(_calendarsProvider.future))
            if (calendar.kind == CalendarKinds.local)
              (id: calendar.id, name: calendar.name),
        ],
        EntityTypes.wikiPage => [
          for (final page in await ref.watch(_pagesProvider.future))
            if (page.archivedAt == null) (id: page.id, name: page.title),
        ],
        _ => const [],
      };
}
