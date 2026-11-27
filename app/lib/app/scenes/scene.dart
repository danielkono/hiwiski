import '../../core/routing/routes.dart';
import '../demo.dart';

/// A view of the app the website lets its visitors try on the demo's sample data,
/// under the name the page asks for it by.
///
/// Only the scenes that run live are here; the others are screenshots.
enum Scene {
  shoppingList('shopping-list'),
  taskList('task-list'),
  kanbanBoard('kanban-board'),
  calendarWeek('calendar-week'),
  wikiPage('wiki-page'),
  wikiEdit('wiki-edit'),
  recipe('recipe'),
  startBoard('start-board'),
  search('search'),
  pinboard('pinboard');

  const Scene(this.id);

  /// The name in the page's `{{< scene name="…" >}}`.
  final String id;

  static const _shopping = 'list:shopping';
  static const _chores = 'list:chores';
  static const _bathroom = 'list:bathroom';
  static const _router = 'page:router';
  static const _wifi = 'page:wifi';
  static const _spaetzle = 'page:spaetzle';
  static const _sardinia = 'page:sardinia';

  /// The scene named [id], or `null` for a name this build does not know.
  static Scene? byId(Object? id) {
    for (final scene in values) {
      if (scene.id == id) return scene;
    }
    return null;
  }

  /// Where the scene opens, once [demo] holds its sample data.
  String location(Demo demo) => switch (this) {
    shoppingList => _list(demo, _shopping),
    taskList => _list(demo, _chores),
    kanbanBoard => _list(demo, _bathroom),
    calendarWeek => const CalendarRoute().location,
    wikiPage => WikiRoute(pageId: demo.idOf(_router)).location,
    wikiEdit => WikiRoute(pageId: demo.idOf(_wifi)).location,
    recipe => WikiRoute(pageId: demo.idOf(_spaetzle)).location,
    startBoard => const HomeRoute().location,
    search => const SearchRoute().location,
    pinboard => PinboardRoute(pageId: demo.idOf(_sardinia) ?? '').location,
  };

  static String _list(Demo demo, String key) =>
      TodoListRoute(listId: demo.idOf(key) ?? '').location;
}
