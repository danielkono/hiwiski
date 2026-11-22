import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../common/app_names.dart';
import '../common/build_flavor.dart';
import '../common/ids.dart';
import '../common/theme_preference.dart';

/// What lives on the device and survives a restart.
///
/// The theme belongs to the member and is synced along; it is also kept locally so
/// the first frame after startup is already right.
class LocalSettings {
  LocalSettings(this._preferences);

  final SharedPreferences _preferences;

  static const _serverKey = 'hiwiski.server.address';
  static const _themeKey = 'hiwiski.theme.mode';
  static const _light = 'LIGHT';
  static const _dark = 'DARK';
  static const _system = 'SYSTEM';
  static const _drawerKey = 'hiwiski.drawer.expanded';
  static const _calendarViewKey = 'hiwiski.calendar.view';
  static const _hiddenCalendarsKey = 'hiwiski.calendar.hidden';
  static const _pinnedStripKey = 'hiwiski.calendar.pinned';
  static const _pendingSharesKey = 'hiwiski.shares.pending';
  static const _shareSheetsKey = 'hiwiski.shares.sheets';
  static const _tagUsesKey = 'hiwiski.tags.uses';
  static const _keepFiltersKey = 'hiwiski.filters.keep';
  static const _lastSessionKey = 'hiwiski.session.last';
  static const _appearancePendingKey = 'hiwiski.appearance.pending';
  static const _installationKey = 'hiwiski.installation.id';
  static const _wipeOnAccessLostKey = 'hiwiski.access_lost.wipe';
  static const _lostSessionKey = 'hiwiski.session.lost';
  static const _todoViewKey = 'hiwiski.todo.view';
  static const _doneLastKey = 'hiwiski.todo.done_last';
  static const _keepAreasKey = 'hiwiski.navigation.keep_areas';
  static const _undoSecondsKey = 'hiwiski.undo.seconds';
  static const _pullHintKey = 'hiwiski.pull_hint.mode';
  static const _pullHintPullsKey = 'hiwiski.pull_hint.pulls';
  static const _formattedEditorKey = 'hiwiski.editor.formatted';
  static const _localMemberKey = 'hiwiski.local.member';
  static const _catalogCarryoverKey = 'hiwiski.local.catalog_carryover';
  static const _homeWidgetsKey = 'hiwiski.home_widgets';
  static const _mindmapSnapKey = 'hiwiski.mindmap.snap';
  static const _mindmapGridKey = 'hiwiski.mindmap.grid';
  static const _mindmapSizesKey = 'hiwiski.mindmap.sizes';

  static Future<LocalSettings> open() async =>
      LocalSettings(await SharedPreferences.getInstance());

  /// Reads what another engine wrote — the background sync keeps the
  /// shares that still wait here, and this instance holds a copy from its start.
  Future<void> reload() => _preferences.reload();

  /// The home server. In the browser it is where the page came from: the server serves
  /// the web app itself, so asking for its address is a question with only one answer.
  /// For development against a server on another port: `--dart-define=HIWISKI_SERVER=…`.
  ///
  /// The demo has none, whatever page it came from.
  String? get serverAddress => switch ((BuildFlavor.demo, kIsWeb)) {
    (true, _) => null,
    (_, true) => webServerAddress(),
    _ => _preferences.getString(_serverKey),
  };

  Future<void> setServerAddress(String? value) async {
    if (value == null) {
      await _preferences.remove(_serverKey);
    } else {
      await _preferences.setString(_serverKey, value);
    }
  }

  ThemePreference get themeMode => switch (_preferences.getString(_themeKey)) {
    _light => ThemePreference.light,
    _dark => ThemePreference.dark,
    _ => ThemePreference.system,
  };

  Future<void> setThemeMode(ThemePreference mode) =>
      _preferences.setString(_themeKey, switch (mode) {
        .light => _light,
        .dark => _dark,
        .system => _system,
      });

  /// Whether the tag filters of calendar, tasks and wiki survive leaving the area.
  /// Off by default: a filter set an hour ago should not silently hide things.
  /// A theme chosen offline that the server has not heard of yet — it wins over the
  /// server's value until it has gone out.
  bool get appearancePending =>
      _preferences.getBool(_appearancePendingKey) ?? false;

  Future<void> setAppearancePending(bool value) =>
      _preferences.setBool(_appearancePendingKey, value);

  bool get keepFilters => _preferences.getBool(_keepFiltersKey) ?? false;

  /// Names this installation of the app towards the server, the same across sign-ins
  /// and sign-outs: a new sign-in retires the devices it registered before. Made on
  /// first use, never cleared.
  Future<String> installationId() async {
    final known = _preferences.getString(_installationKey);
    if (known != null) return known;
    final id = newId();
    await _preferences.setString(_installationKey, id);
    return id;
  }

  /// What happens when this device loses its access by itself — signed out on
  /// another device, a session that ended. Off (the default), the device is locked:
  /// nothing is deleted, and whoever signs in again keeps their changes. On, it is
  /// cleared at once — for a device that may be lost. A matter of the device: it is
  /// about what stays on it.
  bool get wipeOnAccessLost =>
      _preferences.getBool(_wipeOnAccessLostKey) ?? false;

  Future<void> setWipeOnAccessLost(bool value) =>
      _preferences.setBool(_wipeOnAccessLostKey, value);

  /// The session this device lost its access to, as JSON — the lock screen names
  /// whom it belongs to, after a restart too. `null` while the device has access.
  String? get lostSession => _preferences.getString(_lostSessionKey);

  Future<void> setLostSession(String? value) async {
    if (value == null) {
      await _preferences.remove(_lostSessionKey);
    } else {
      await _preferences.setString(_lostSessionKey, value);
    }
  }

  /// How the task overview shows its lists: `TOGETHER`, `BY_KIND` or `SIDEBAR`.
  String? get todoView => _preferences.getString(_todoViewKey);

  Future<void> setTodoView(String value) =>
      _preferences.setString(_todoViewKey, value);

  /// Whether ticked-off rows of a task or shopping list move to its bottom. On by
  /// default; off, a row stays where it was.
  bool get doneLast => _preferences.getBool(_doneLastKey) ?? true;

  Future<void> setDoneLast(bool value) =>
      _preferences.setBool(_doneLastKey, value);

  /// Whether texts — a page, a description, a note — open formatted for writing, or as
  /// their Markdown. On by default: most of a family writes without knowing Markdown.
  /// Either way the editor switches at any time.
  bool get formattedEditor => _preferences.getBool(_formattedEditorKey) ?? true;

  Future<void> setFormattedEditor(bool value) =>
      _preferences.setBool(_formattedEditorKey, value);

  /// Whether each area keeps the page it was left on — switching back returns there.
  /// On by default; off, an area always opens at its start.
  bool get keepAreas => _preferences.getBool(_keepAreasKey) ?? true;

  Future<void> setKeepAreas(bool value) =>
      _preferences.setBool(_keepAreasKey, value);

  /// How many seconds "Undo" is offered after a deletion — and how long the
  /// deletion waits for it. 8 by default.
  int get undoSeconds => _preferences.getInt(_undoSecondsKey) ?? 8;

  Future<void> setUndoSeconds(int value) =>
      _preferences.setInt(_undoSecondsKey, value);

  Future<void> setKeepFilters(bool value) =>
      _preferences.setBool(_keepFiltersKey, value);

  /// Whether the hint above a filter bar on the phone ("Pull for filters") shows:
  /// `null` until the member decides (it goes away once learned), `true` always,
  /// `false` never.
  bool? get pullHint => _preferences.getBool(_pullHintKey);

  Future<void> setPullHint(bool show) =>
      _preferences.setBool(_pullHintKey, show);

  /// How often a filter bar was pulled down while its hint was showing.
  int get pullHintPulls => _preferences.getInt(_pullHintPullsKey) ?? 0;

  Future<void> setPullHintPulls(int value) =>
      _preferences.setInt(_pullHintPullsKey, value);

  /// The drawer remembers its state.
  bool get drawerExpanded => _preferences.getBool(_drawerKey) ?? true;

  Future<void> setDrawerExpanded(bool value) =>
      _preferences.setBool(_drawerKey, value);

  /// "List / month as a radio group. **The choice survives a restart.**"
  String? get calendarView => _preferences.getString(_calendarViewKey);

  Future<void> setCalendarView(String value) =>
      _preferences.setString(_calendarViewKey, value);

  /// Whether all-day events stand in a strip above the list and below the month —
  /// a matter of the device, like the view.
  bool get calendarPinnedStrip => _preferences.getBool(_pinnedStripKey) ?? true;

  Future<void> setCalendarPinnedStrip(bool value) =>
      _preferences.setBool(_pinnedStripKey, value);

  /// Which calendars are hidden — a matter of view and so a matter of the device, not
  /// the member. Whoever hides the work calendar on the wall tablet still wants to see
  /// it on the phone.
  Set<String> get hiddenCalendars =>
      (_preferences.getStringList(_hiddenCalendarsKey) ?? const []).toSet();

  Future<void> setHiddenCalendars(Set<String> value) =>
      _preferences.setStringList(_hiddenCalendarsKey, value.toList());

  /// Shares chosen at creation that are still waiting for the server — as JSON per
  /// item. They survive a restart like the outbox whose item they follow.
  List<String> get pendingShares =>
      _preferences.getStringList(_pendingSharesKey) ?? const [];

  Future<void> setPendingShares(List<String> value) =>
      _preferences.setStringList(_pendingSharesKey, value);

  /// The share sheets last seen, as JSON per item (`TYPE/id`) — so the sheet opens
  /// and can be changed offline.
  Map<String, String> get shareSheets {
    final raw = _preferences.getString(_shareSheetsKey);
    if (raw == null) return const {};
    return (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
  }

  Future<void> setShareSheets(Map<String, String> value) =>
      _preferences.setString(_shareSheetsKey, jsonEncode(value));

  /// The tags used last, newest first — filtering by one or putting one on an item.
  /// Repeated: a tag used often appears often. The filter bar ranks by it.
  /// Whether a mind map's elements snap to one another while they are moved or
  /// resized. On by default.
  bool get mindmapSnap => _preferences.getBool(_mindmapSnapKey) ?? true;

  Future<void> setMindmapSnap(bool value) =>
      _preferences.setBool(_mindmapSnapKey, value);

  /// Whether a mind map shows its grid, and what is moved snaps to it. Off by
  /// default.
  bool get mindmapGrid => _preferences.getBool(_mindmapGridKey) ?? false;

  Future<void> setMindmapGrid(bool value) =>
      _preferences.setBool(_mindmapGridKey, value);

  /// The size an element of each kind was placed or resized at last, by mind map,
  /// newest first: `<page> <kind> <width> <height>`.
  List<String> get mindmapSizes =>
      _preferences.getStringList(_mindmapSizesKey) ?? const [];

  Future<void> setMindmapSizes(List<String> value) =>
      _preferences.setStringList(_mindmapSizesKey, value);

  List<String> get tagUses =>
      _preferences.getStringList(_tagUsesKey) ?? const [];

  Future<void> setTagUses(List<String> value) =>
      _preferences.setStringList(_tagUsesKey, value);

  /// The last session the server confirmed, with its handshake — as JSON. The app
  /// starts on it instead of on the sign-in screen: offline after a force quit the
  /// server cannot confirm anything, and the device token alone says nothing about
  /// who is signed in. The server still has the last word as soon as it answers.
  String? get lastSession => _preferences.getString(_lastSessionKey);

  Future<void> setLastSession(String? value) async {
    if (value == null) {
      await _preferences.remove(_lastSessionKey);
    } else {
      await _preferences.setString(_lastSessionKey, value);
    }
  }

  /// The member this device made for itself when it was started without a server,
  /// as JSON — `null` once it is on a server, or never was.
  ///
  /// It stays while the device connects: until the server has taken the member over,
  /// the data is still theirs, and a connection broken off halfway goes on from here.
  String? get localMember => _preferences.getString(_localMemberKey);

  Future<void> setLocalMember(String? value) async {
    if (value == null) {
      await _preferences.remove(_localMemberKey);
    } else {
      await _preferences.setString(_localMemberKey, value);
    }
  }

  /// Whether the shopping categories made without a server still have to go to the
  /// server the device connected to. Set when it connects, cleared once they are
  /// there.
  bool get catalogCarryover =>
      _preferences.getBool(_catalogCarryoverKey) ?? false;

  Future<void> setCatalogCarryover(bool value) =>
      _preferences.setBool(_catalogCarryoverKey, value);

  /// What the home screen widgets of this device show, as the JSON document of
  /// `HomeWidgetSettings`.
  String? get homeWidgets => _preferences.getString(_homeWidgetsKey);

  Future<void> setHomeWidgets(String? value) async {
    if (value == null) {
      await _preferences.remove(_homeWidgetsKey);
    } else {
      await _preferences.setString(_homeWidgetsKey, value);
    }
  }

  /// What belongs to a member and must not stay behind on a switch: which calendars
  /// they have hidden (those are their calendar IDs), shares still waiting for the
  /// server, the share sheets last seen, the lists and calendars the home screen
  /// widgets show, and the remembered session. Theme, drawer and calendar view are a matter
  /// of the device and stay.
  Future<void> clearMemberData() async {
    await _preferences.remove(_homeWidgetsKey);
    await _preferences.remove(_lastSessionKey);
    await _preferences.remove(_lostSessionKey);
    await _preferences.remove(_appearancePendingKey);
    await _preferences.remove(_hiddenCalendarsKey);
    await _preferences.remove(_pendingSharesKey);
    await _preferences.remove(_shareSheetsKey);
    await _preferences.remove(_tagUsesKey);
    // Named by the pages they were used on.
    await _preferences.remove(_mindmapSizesKey);
  }
}

/// The server in the browser: the build-time override, otherwise the page's origin.
String? webServerAddress() {
  const override = String.fromEnvironment('HIWISKI_SERVER');
  if (override.isNotEmpty) return override;
  final origin = Uri.base;
  if (!origin.scheme.startsWith(UriSchemes.http) || origin.host.isEmpty) {
    return null;
  }
  return origin.origin;
}
