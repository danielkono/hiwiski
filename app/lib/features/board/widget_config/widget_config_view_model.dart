import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../core/common/wire.dart';
import '../../../domain/board/board_items.dart';
import '../../../domain/board/widget_kinds.dart';
import '../../../domain/calendar/calendar_items.dart';
import '../../../domain/todo/kanban.dart';
import '../../../domain/todo/todo_models.dart';
import '../../../domain/wiki/wiki_page.dart';

part 'widget_config_view_model.g.dart';

/// What a tile can be set to show: the calendars, the lists and boards, the pages and
/// recipes that are not archived.
@immutable
class WidgetConfigState {
  const WidgetConfigState({
    required this.calendars,
    required this.lists,
    required this.pages,
  });

  final List<Calendar> calendars;
  final List<TodoListSummary> lists;
  final List<WikiPage> pages;

  List<TodoListSummary> get shoppingLists => [
    for (final summary in lists)
      if (summary.list.kind == ListKinds.shopping) summary,
  ];

  List<TodoListSummary> get boards => [
    for (final summary in lists)
      if (summary.list.kind == kindKanban) summary,
  ];

  List<WikiPage> get recipes => [
    for (final page in pages)
      if (page.kind == PageKinds.recipe) page,
  ];

  List<WikiPage> get plainPages => [
    for (final page in pages)
      if (page.kind != PageKinds.recipe) page,
  ];
}

@riverpod
Stream<List<Calendar>> _calendars(Ref ref) =>
    ref.watch(calendarRepositoryProvider).watchCalendars();

@riverpod
Stream<List<TodoListSummary>> _lists(Ref ref) =>
    ref.watch(todoRepositoryProvider).watchLists();

@riverpod
Stream<List<WikiPage>> _pages(Ref ref) =>
    ref.watch(wikiRepositoryProvider).watchPages();

@riverpod
class WidgetConfigViewModel extends _$WidgetConfigViewModel {
  @override
  Future<WidgetConfigState> build() async {
    final calendars = ref.watch(_calendarsProvider.future);
    final lists = ref.watch(_listsProvider.future);
    final pages = ref.watch(_pagesProvider.future);
    return WidgetConfigState(
      calendars: await calendars,
      lists: await lists,
      pages: [
        for (final page in await pages)
          if (page.archivedAt == null) page,
      ],
    );
  }

  Future<void> configure(BoardWidget widget, WidgetConfig config) =>
      ref.read(boardRepositoryProvider).configureWidget(widget, config);
}
