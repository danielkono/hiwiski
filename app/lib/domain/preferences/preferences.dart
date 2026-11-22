import '../../core/common/theme_preference.dart';

export '../../core/common/theme_preference.dart';

/// What this device remembers about how its member likes to see things.
class Preferences {
  const Preferences({
    required this.themeMode,
    required this.keepFilters,
    required this.drawerExpanded,
    required this.calendarView,
    required this.calendarPinnedStrip,
    required this.hiddenCalendars,
    required this.tagUses,
    required this.wipeOnAccessLost,
    required this.todoView,
    this.doneLast = true,
    this.keepAreas = true,
    this.undoSeconds = 8,
    this.pullHint,
    this.pullHintPulls = 0,
    this.formattedEditor = true,
    this.mindmapSnap = true,
    this.mindmapGrid = false,
    this.mindmapSizes = const {},
  });

  /// After this many pulls the hint has done its job: the member knows the bar is
  /// there, and the line it takes goes back to the content.
  static const pullHintLearned = 5;

  final ThemePreference themeMode;

  /// Whether the tag filters stay set when leaving calendar, tasks or wiki
  /// (Account → Customize).
  final bool keepFilters;

  /// Whether the drawer on a wide screen shows its labels.
  final bool drawerExpanded;

  /// The calendar's view as the settings store it: `MONTH`, `WEEK` or `LIST`.
  final String? calendarView;

  final bool calendarPinnedStrip;

  final Set<String> hiddenCalendars;

  /// The tags used last, newest first.
  final List<String> tagUses;

  /// Whether losing access clears the device at once instead of locking it (Account →
  /// Customize).
  final bool wipeOnAccessLost;

  /// The task overview's view as the settings store it: `TOGETHER`, `BY_KIND` or
  /// `SIDEBAR`.
  final String? todoView;

  /// Whether ticked-off rows of a task or shopping list move to its bottom (Account →
  /// Customize); off, they keep their place.
  final bool doneLast;

  /// Whether each area keeps the page it was left on (Account → Customize).
  final bool keepAreas;

  /// How many seconds "Undo" is offered after a deletion (Account → Customize) —
  /// and how long the deletion waits for it.
  final int undoSeconds;

  Duration get undoWindow => .new(seconds: undoSeconds);

  /// The member's choice about the hint above a filter bar (Account → Customize):
  /// `true` always, `false` never, `null` not made — then it shows until learned.
  final bool? pullHint;

  /// How often a filter bar was pulled down while its hint was showing.
  final int pullHintPulls;

  /// Whether texts open formatted for writing rather than as Markdown (Account →
  /// Customize); the editor switches either way.
  final bool formattedEditor;

  /// Whether a mind map's elements snap to one another, and whether its grid shows
  /// and is snapped to (the map's Tools).
  final bool mindmapSnap;
  final bool mindmapGrid;

  /// The size an element was placed or resized at last, by [mindmapSizeKey] of its
  /// page and kind — a new one of the kind takes it.
  final Map<String, ({int width, int height})> mindmapSizes;

  static String mindmapSizeKey(String pageId, String kind) => '$pageId $kind';

  /// Whether the hint ("Pull for filters") shows above a filter bar on the phone.
  bool get showsPullHint => pullHint ?? pullHintPulls < pullHintLearned;

  Preferences copyWith({
    ThemePreference? themeMode,
    bool? keepFilters,
    bool? drawerExpanded,
    String? calendarView,
    bool? calendarPinnedStrip,
    Set<String>? hiddenCalendars,
    List<String>? tagUses,
    bool? wipeOnAccessLost,
    String? todoView,
    bool? doneLast,
    bool? keepAreas,
    int? undoSeconds,
    bool? pullHint,
    int? pullHintPulls,
    bool? formattedEditor,
    bool? mindmapSnap,
    bool? mindmapGrid,
    Map<String, ({int width, int height})>? mindmapSizes,
  }) => .new(
    themeMode: themeMode ?? this.themeMode,
    keepFilters: keepFilters ?? this.keepFilters,
    drawerExpanded: drawerExpanded ?? this.drawerExpanded,
    calendarView: calendarView ?? this.calendarView,
    calendarPinnedStrip: calendarPinnedStrip ?? this.calendarPinnedStrip,
    hiddenCalendars: hiddenCalendars ?? this.hiddenCalendars,
    tagUses: tagUses ?? this.tagUses,
    wipeOnAccessLost: wipeOnAccessLost ?? this.wipeOnAccessLost,
    todoView: todoView ?? this.todoView,
    doneLast: doneLast ?? this.doneLast,
    keepAreas: keepAreas ?? this.keepAreas,
    undoSeconds: undoSeconds ?? this.undoSeconds,
    pullHint: pullHint ?? this.pullHint,
    pullHintPulls: pullHintPulls ?? this.pullHintPulls,
    formattedEditor: formattedEditor ?? this.formattedEditor,
    mindmapSnap: mindmapSnap ?? this.mindmapSnap,
    mindmapGrid: mindmapGrid ?? this.mindmapGrid,
    mindmapSizes: mindmapSizes ?? this.mindmapSizes,
  );
}
