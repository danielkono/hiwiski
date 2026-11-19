import '../../core/api/generated/export.dart';
import '../../core/api/hiwiski_api.dart';
import '../../domain/common/item_ref.dart';
import '../query.dart';

/// The history of an item.
///
/// **Only over REST, not mirrored**: it only lives as long as the log anyway, and
/// mirroring it to every device would be the most expensive way to almost never look at
/// it. So it does not exist offline — and the UI says so instead of showing an empty
/// list.
class HistoryRepository {
  HistoryRepository(this._api);

  final HiwiskiApi _api;

  late final _history = Query<ItemRef, History>(of);

  Future<History> of(ItemRef item) => HiwiskiApi.run(
    () => _api.search.getHistory(itemType: item.type, itemId: item.id),
  );

  /// The history of [item] while it is shown — one request for every section that
  /// shows it, fetched afresh whenever it is shown again.
  Stream<History> watch(ItemRef item) => _history.watch(item);

  /// **After every sync**: the history is created on the server. Without this, after
  /// a change only "created" kept showing — the new version only arrived with a
  /// restart. Until the new answer arrives the old one stays in place.
  void refresh() => _history.refresh();
}
