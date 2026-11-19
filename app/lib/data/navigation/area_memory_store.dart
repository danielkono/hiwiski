import '../store.dart';

/// Where each of the four areas was left — its address with the page open there, by
/// the area's index. Kept while the app runs: switching from a wiki page to a list and
/// back lands on the page again, and back on the list after that.
class AreaMemoryStore extends Store<Map<int, String>> {
  AreaMemoryStore() : super(const {});

  void remember(int area, String location) =>
      value = Map.unmodifiable({...value, area: location});

  void forget(int area) => value = Map.unmodifiable({...value}..remove(area));
}
