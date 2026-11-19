import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/link_index.dart';
import '../../app/repositories.dart';
import '../../app/stores.dart';
import '../../domain/links/link_index.dart';
import '../common/command.dart';
import '../common/wire.dart';

part 'navigation_view_model.g.dart';

/// `locate`, run by a view: it shows the command running and reacts to how it ended.
final locateMutation = Mutation<ItemPlace?>(
  label: 'navigationViewModel.locate',
);

/// What jumping to an item needs to know beyond its address: the list a task sits on,
/// the day an event starts. Its state is the link index — what the device knows of
/// every item a link can point to.
@riverpod
class NavigationViewModel extends _$NavigationViewModel {
  @override
  LinkIndex build() => ref.watch(linkIndexProvider);

  /// Where an item is shown — `null` when it is gone. An event sets the calendar to
  /// its day on the way, so that "Back" from the event lands where it sits in the
  /// calendar.
  @command
  Future<ItemPlace?> locate({
    required String itemType,
    required String itemId,
    String? containerId,
  }) async {
    switch (itemType) {
      case EntityTypes.todo:
        final listId =
            containerId ??
            await ref.read(todoRepositoryProvider).listOf(itemId);
        return listId == null
            ? null
            : ItemPlace(itemType: itemType, itemId: itemId, listId: listId);
      case EntityTypes.event:
        // Taken before the wait: nothing watches this ViewModel, it may be gone
        // after it.
        final calendarDay = ref.read(calendarDayStoreProvider);
        final day = await ref
            .read(calendarRepositoryProvider)
            .startDayOf(itemId);
        if (day != null) calendarDay.select(day);
    }
    return ItemPlace(itemType: itemType, itemId: itemId);
  }
}

/// Where an item is shown: the item — and, for a task, the list it sits on.
class const ItemPlace({
  required final String itemType,
  required final String itemId,
  final String? listId,
});
