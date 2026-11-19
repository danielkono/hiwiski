import '../store.dart';

/// Which pages of the wiki tree are expanded — kept while the app runs.
///
/// The tree used to keep it itself, so every way back to the wiki — a tap on "Wiki"
/// below, a link, a page closed on the phone — found it collapsed, and pages deep in
/// it had to be opened again one level at a time. A matter of this device and this
/// run, not of the family: not synced, not stored.
class WikiTreeStore extends Store<Set<String>> {
  WikiTreeStore() : super(const {});

  void set(Set<String> expanded) => value = Set.unmodifiable(expanded);
}
