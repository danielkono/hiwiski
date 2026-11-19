import '../../domain/tags/tag.dart';
import '../preferences/preferences_store.dart';
import '../store.dart';

/// Which tags are selected as a filter, per area ([TagFilterAreas]). An area without
/// an entry, or with an empty set, means "All".
///
/// Shared by several screens — calendar, tasks and wiki filter together — so it is
/// Model, not the state of one screen.
class TagFilterStore extends Store<Map<String, Set<String>>> {
  TagFilterStore(this._preferences) : super(const {});

  final PreferencesStore _preferences;

  Set<String> of(String area) => value[area] ?? const {};

  void toggle(String area, String id) {
    final current = of(area);
    final adding = !current.contains(id);
    _set(area, adding ? {...current, id} : ({...current}..remove(id)));
    if (adding) {
      // Only the ranking of the filter bar; a lost use costs nothing.
      _preferences.recordTagUses([id]).ignore();
    }
  }

  void clear(String area) {
    if (of(area).isEmpty) return;
    _set(area, const {});
  }

  /// The page that held this filter is gone: the filter goes with it — unless this
  /// device keeps filters (Account → Customize), then it holds in every area.
  void release(String area) {
    // The whole app went with the page: nothing is left to release.
    if (_disposed) return;
    if (!_preferences.value.keepFilters) clear(area);
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// A deleted tag leaves every filter: items keep its id, so a list stayed filtered
  /// by a tag that no chip showed any more — only "All" cleared it.
  void forget(String id) {
    if (!value.values.any((filter) => filter.contains(id))) return;
    value = {
      for (final MapEntry(:key, value: filter) in value.entries)
        key: {...filter}..remove(id),
    };
  }

  void _set(String area, Set<String> filter) =>
      value = {...value, area: Set.unmodifiable(filter)};
}
