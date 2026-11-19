import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../app/stores.dart';
import '../../../core/common/wire.dart';
import '../../../domain/calendar/calendar_items.dart';
import '../../../domain/home_widgets/home_widget_settings.dart';
import '../../../domain/todo/kanban.dart';
import '../../../domain/todo/todo_models.dart';

part 'home_widgets_view_model.g.dart';

/// What one kind of widget is set to, as its row names it.
@immutable
class const HomeWidgetSummary({
  /// `null` while the widget is not set up.
  required final HomeWidgetConfig? config,

  /// The calendars' or the list's name; empty for "all calendars".
  final List<String> names = const [],

  /// The column of a Kanban widget.
  final String? column,

  /// The list or column it names is gone — it has to be set up again.
  final bool missing = false,
});

/// Account → Widgets: what the home screen widgets of this device show. Nothing here is
/// synced — a home screen belongs to the device.
@immutable
class const HomeWidgetsState({
  required final Map<HomeWidgetKind, HomeWidgetSummary> summaries,
  required final List<Calendar> calendars,

  /// The lists that are not archived, by kind.
  required final List<TodoListSummary> shoppingLists,
  required final List<TodoListSummary> taskLists,
  required final List<TodoListSummary> boards,
});

@riverpod
Stream<List<Calendar>> _calendars(Ref ref) =>
    ref.watch(calendarRepositoryProvider).watchCalendars();

@riverpod
Stream<List<TodoListSummary>> _lists(Ref ref) =>
    ref.watch(todoRepositoryProvider).watchLists();

@riverpod
class HomeWidgetsViewModel extends _$HomeWidgetsViewModel {
  @override
  Future<HomeWidgetsState> build() async {
    final settings = ref.watch(homeWidgetSettingsProvider);
    final calendarsSource = ref.watch(_calendarsProvider.future);
    final listsSource = ref.watch(_listsProvider.future);
    final calendars = await calendarsSource;
    final lists = await listsSource;
    final byId = {for (final summary in lists) summary.list.id: summary.list};
    final calendarNames = {
      for (final calendar in calendars) calendar.id: calendar.name,
    };

    HomeWidgetSummary summaryOf(HomeWidgetKind kind) {
      final config = settings.of(kind);
      if (config == null) return const HomeWidgetSummary(config: null);
      if (kind == .agenda) {
        return HomeWidgetSummary(
          config: config,
          names: [for (final id in config.calendarIds) ?calendarNames[id]],
        );
      }
      final list = byId[config.listId];
      if (list == null) {
        return HomeWidgetSummary(config: config, missing: true);
      }
      final column = kind == .kanban
          ? parseColumns(list.columns)
                .where((c) => c.id == config.columnId)
                .firstOrNull
          : null;
      return HomeWidgetSummary(
        config: config,
        names: [list.name],
        column: column?.name,
        missing: kind == .kanban && column == null,
      );
    }

    List<TodoListSummary> ofKind(String kind) => [
      for (final summary in lists)
        if (summary.list.kind == kind) summary,
    ];

    return HomeWidgetsState(
      summaries: {
        for (final kind in HomeWidgetKind.values) kind: summaryOf(kind),
      },
      calendars: calendars,
      shoppingLists: ofKind(ListKinds.shopping),
      taskLists: ofKind(ListKinds.standard),
      boards: ofKind(kindKanban),
    );
  }

  /// [config] `null` takes the widget's settings away; it then asks to be set up.
  Future<void> configure(HomeWidgetKind kind, HomeWidgetConfig? config) =>
      ref.read(homeWidgetStoreProvider).configure(kind, config);
}
