import '../../core/storage/local_settings.dart';
import '../../domain/preferences/preferences.dart';
import '../store.dart';

/// What this device remembers about how its member likes to see things: the theme,
/// the drawer, the calendar view, the tags used lately, whether filters are kept.
///
/// None of it is synced except the theme, which the session also sends to the server;
/// all of it survives a restart. Every change is in [value] at once and
/// written behind it.
class PreferencesStore extends Store<Preferences> {
  PreferencesStore(this._settings) : super(_read(_settings));

  final LocalSettings _settings;

  /// Enough history to tell often from rarely, little enough to forget old habits.
  static const _keepUses = 200;

  static Preferences _read(LocalSettings settings) => .new(
    themeMode: settings.themeMode,
    keepFilters: settings.keepFilters,
    drawerExpanded: settings.drawerExpanded,
    calendarView: settings.calendarView,
    calendarPinnedStrip: settings.calendarPinnedStrip,
    hiddenCalendars: settings.hiddenCalendars,
    tagUses: settings.tagUses,
    wipeOnAccessLost: settings.wipeOnAccessLost,
    todoView: settings.todoView,
    doneLast: settings.doneLast,
    keepAreas: settings.keepAreas,
    undoSeconds: settings.undoSeconds,
    pullHint: settings.pullHint,
    pullHintPulls: settings.pullHintPulls,
    formattedEditor: settings.formattedEditor,
  );

  /// Reads what another engine — the background sync — may have written meanwhile.
  Future<void> reload() async {
    await _settings.reload();
    value = _read(_settings);
  }

  Future<void> setThemeMode(ThemePreference mode) async {
    if (value.themeMode == mode) return;
    value = value.copyWith(themeMode: mode);
    await _settings.setThemeMode(mode);
  }

  Future<void> setKeepFilters(bool keep) async {
    if (value.keepFilters == keep) return;
    value = value.copyWith(keepFilters: keep);
    await _settings.setKeepFilters(keep);
  }

  Future<void> setDoneLast(bool doneLast) async {
    if (value.doneLast == doneLast) return;
    value = value.copyWith(doneLast: doneLast);
    await _settings.setDoneLast(doneLast);
  }

  Future<void> setUndoSeconds(int seconds) async {
    if (value.undoSeconds == seconds) return;
    value = value.copyWith(undoSeconds: seconds);
    await _settings.setUndoSeconds(seconds);
  }

  Future<void> setFormattedEditor(bool formatted) async {
    if (value.formattedEditor == formatted) return;
    value = value.copyWith(formattedEditor: formatted);
    await _settings.setFormattedEditor(formatted);
  }

  Future<void> setKeepAreas(bool keep) async {
    if (value.keepAreas == keep) return;
    value = value.copyWith(keepAreas: keep);
    await _settings.setKeepAreas(keep);
  }

  /// The member's choice: the hint always or never. Either is kept for good; the hint
  /// no longer goes away by itself.
  Future<void> setPullHint(bool show) async {
    if (value.pullHint == show) return;
    value = value.copyWith(pullHint: show);
    await _settings.setPullHint(show);
  }

  /// A filter bar was pulled down while its hint was showing. Counted only until the
  /// hint is learned, and not at all once the member has chosen.
  Future<void> recordPull() async {
    if (value.pullHint != null) return;
    if (value.pullHintPulls >= Preferences.pullHintLearned) return;
    value = value.copyWith(pullHintPulls: value.pullHintPulls + 1);
    await _settings.setPullHintPulls(value.pullHintPulls);
  }

  Future<void> setWipeOnAccessLost(bool wipe) async {
    if (value.wipeOnAccessLost == wipe) return;
    value = value.copyWith(wipeOnAccessLost: wipe);
    await _settings.setWipeOnAccessLost(wipe);
  }

  /// [view] as the settings store it: `TOGETHER`, `BY_KIND` or `SIDEBAR`.
  Future<void> setTodoView(String view) async {
    value = value.copyWith(todoView: view);
    await _settings.setTodoView(view);
  }

  Future<void> toggleDrawer() async {
    value = value.copyWith(drawerExpanded: !value.drawerExpanded);
    await _settings.setDrawerExpanded(value.drawerExpanded);
  }

  /// [view] as the settings store it: `MONTH`, `WEEK` or `LIST`.
  Future<void> setCalendarView(String view) async {
    value = value.copyWith(calendarView: view);
    await _settings.setCalendarView(view);
  }

  Future<void> setCalendarPinnedStrip(bool pinned) async {
    value = value.copyWith(calendarPinnedStrip: pinned);
    await _settings.setCalendarPinnedStrip(pinned);
  }

  Future<void> setHiddenCalendars(Set<String> hidden) async {
    value = value.copyWith(hiddenCalendars: Set.unmodifiable(hidden));
    await _settings.setHiddenCalendars(hidden);
  }

  /// These tags were just used — they move to the front of the ranking.
  Future<void> recordTagUses(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    final next = [...ids, ...value.tagUses].take(_keepUses).toList();
    value = value.copyWith(tagUses: next);
    await _settings.setTagUses(next);
  }
}
