import '../store.dart';

/// The list open next to the rows in the task overview's "as a list" view — kept
/// while the app runs, so that coming back to the tasks finds it open again.
class TodoSidebarStore extends Store<String?> {
  TodoSidebarStore() : super(null);

  void select(String? listId) => value = listId;
}
