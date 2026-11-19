import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// The kinds of home screen widget: what each one shows. Their names are the keys the
/// native widgets read (`docs/development/home-widgets.md`).
enum HomeWidgetKind {
  /// The coming events of the chosen calendars.
  agenda,

  /// A shopping list's open entries.
  shopping,

  /// A task list's open entries.
  tasks,

  /// The cards in one column of a Kanban board.
  kanban,
}

/// What one kind of widget is set to show. The fields it does not use stay `null`.
@immutable
class HomeWidgetConfig {
  const HomeWidgetConfig({
    this.calendarIds = const [],
    this.days = defaultDays,
    this.listId,
    this.columnId,
  });

  /// How far ahead the agenda looks, today included, unless chosen otherwise.
  static const defaultDays = 7;

  /// The days on offer — the same as the start board's calendar tile.
  static const dayChoices = [1, 2, 3, 7, 14];

  /// The agenda's calendars; empty means every calendar, as on the start board.
  final List<String> calendarIds;
  final int days;

  /// The list of a shopping, task or Kanban widget.
  final String? listId;

  /// The column of a Kanban widget.
  final String? columnId;

  static const _calendarIdsKey = 'calendarIds';
  static const _daysKey = 'days';
  static const _listIdKey = 'listId';
  static const _columnIdKey = 'columnId';

  /// Whether [kind] has what it needs to show anything. An agenda always has: no
  /// calendar chosen means all of them.
  bool completeFor(HomeWidgetKind kind) => switch (kind) {
    .agenda => true,
    .shopping || .tasks => listId != null,
    .kanban => listId != null && columnId != null,
  };

  /// Only what [kind] uses: the native widget compares the configuration a picture was
  /// made for with the current one, and a stale field would make them differ.
  Map<String, Object?> toJsonFor(HomeWidgetKind kind) => switch (kind) {
    .agenda => {_calendarIdsKey: calendarIds, _daysKey: days},
    .shopping || .tasks => {_listIdKey: listId},
    .kanban => {_listIdKey: listId, _columnIdKey: columnId},
  };

  factory HomeWidgetConfig.fromJson(Map<String, Object?> json) {
    final ids = json[_calendarIdsKey];
    final days = json[_daysKey];
    return HomeWidgetConfig(
      calendarIds: ids is List ? [for (final id in ids) '$id'] : const [],
      days: days is num ? days.toInt() : defaultDays,
      listId: json[_listIdKey] as String?,
      columnId: json[_columnIdKey] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HomeWidgetConfig &&
      const ListEquality<String>().equals(other.calendarIds, calendarIds) &&
      other.days == days &&
      other.listId == listId &&
      other.columnId == columnId;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(calendarIds), days, listId, columnId);
}

/// The home screen widgets of this device. Not synced: a home screen belongs to the
/// device, and the phone's shopping list is not the tablet's.
@immutable
class HomeWidgetSettings {
  const HomeWidgetSettings([this.configs = const {}]);

  final Map<HomeWidgetKind, HomeWidgetConfig> configs;

  /// The configuration of [kind], `null` while it is not set up.
  HomeWidgetConfig? of(HomeWidgetKind kind) {
    final config = configs[kind];
    return config != null && config.completeFor(kind) ? config : null;
  }

  HomeWidgetSettings withConfig(
    HomeWidgetKind kind,
    HomeWidgetConfig? config,
  ) => .new({
    for (final MapEntry(:key, :value) in configs.entries)
      if (key != kind) key: value,
    if (config != null && config.completeFor(kind)) kind: config,
  });

  /// The document the native widgets read: one entry per kind that is set up.
  Map<String, Object?> toJson() => {
    for (final kind in HomeWidgetKind.values)
      if (of(kind) case final config?) kind.name: config.toJsonFor(kind),
  };

  /// Tolerant: an unknown kind or a broken entry costs that widget its settings,
  /// not the others.
  factory HomeWidgetSettings.fromJson(Map<String, Object?> json) => .new({
    for (final kind in HomeWidgetKind.values)
      if (json[kind.name] case final Map<String, Object?> entry)
        kind: HomeWidgetConfig.fromJson(entry),
  });

  @override
  bool operator ==(Object other) =>
      other is HomeWidgetSettings &&
      const MapEquality<HomeWidgetKind, HomeWidgetConfig>().equals(
        other.configs,
        configs,
      );

  @override
  int get hashCode =>
      const MapEquality<HomeWidgetKind, HomeWidgetConfig>().hash(configs);
}
