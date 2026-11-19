import 'package:meta/meta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/repositories.dart';
import '../../app/stores.dart';
import '../../core/api/generated/export.dart';
import '../../core/common/wire.dart';
import '../../domain/common/history_rows.dart';
import '../../domain/common/item_ref.dart';

part 'history_view_model.g.dart';

/// An item's history, with the names its entries point to.
@immutable
class const HistoryState({
  /// `null` when it cannot be had: it is not on the device, and offline the
  /// sections say so. "Created" still comes from the id and the owner.
  required final History? history,
  required final List<Member> members,

  /// The owner from the share sheet — who created the item when the history no
  /// longer reaches back that far.
  final String? ownerId,

  /// Whether there is a history at all: it is kept on the server, and without one
  /// the section is left out instead of saying "not available".
  final bool available = true,

  /// What the sections list: the changes, on a page together with its versions
  /// ([historyRows]).
  final List<HistoryRow> rows = const [],
});

@riverpod
Stream<History> _history(Ref ref, ItemRef item) =>
    ref.watch(historyRepositoryProvider).watch(item);

/// A page's versions, fetched again whenever its history changes: a save leaves a
/// version, and the row that opens it should not wait for the next visit.
@riverpod
Future<List<Revision>> _revisions(Ref ref, ItemRef item) {
  ref.watch(_historyProvider(item).select((history) => history.value));
  return ref.watch(wikiRepositoryProvider).revisions(item.id);
}

@riverpod
Stream<ShareSheet> _sheet(Ref ref, ItemRef item) =>
    ref.watch(accessRepositoryProvider).watchShareSheet(item);

@riverpod
Stream<List<Member>> _members(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchMembers();

@riverpod
class HistoryViewModel extends _$HistoryViewModel {
  /// The history is waited for the first time; names and owner are not.
  @override
  Future<HistoryState> build(ItemRef item) async {
    if (!ref.watch(sessionProvider.select((s) => s.hasServer))) {
      return const HistoryState(history: null, members: [], available: false);
    }
    final members = ref.watch(_membersProvider).value ?? const <Member>[];
    final ownerId = ref.watch(_sheetProvider(item)).value?.ownerId;
    // Decorating: without them the changes are still all there.
    final revisions = item.type == EntityTypes.wikiPage
        ? ref.watch(_revisionsProvider(item)).value ?? const <Revision>[]
        : const <Revision>[];
    final history = await _history(item);
    return HistoryState(
      history: history,
      members: members,
      ownerId: ownerId,
      rows: history == null
          ? const []
          : historyRows(history.entries, revisions),
    );
  }

  /// A failed refetch after a sync keeps the previous answer, which used to give way
  /// to "not available offline"; without any answer a failure is "not available".
  Future<History?> _history(ItemRef item) async {
    final loaded = ref.watch(_historyProvider(item));
    if (loaded.hasValue || loaded.hasError) return loaded.value;
    try {
      return await ref.watch(_historyProvider(item).future);
    } catch (_) {
      return null;
    }
  }
}
