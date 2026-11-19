import 'dart:convert';

import '../../core/storage/local_settings.dart';
import '../../domain/home_widgets/home_widget_settings.dart';
import '../store.dart';

/// What the home screen widgets of this device show — kept on the device, never
/// synced: the home screen belongs to the device.
///
/// It names the member's lists and calendars, so it goes with the member: a sign-out
/// clears it along with the rest of their data (`LocalSettings.clearMemberData`).
class HomeWidgetStore extends Store<HomeWidgetSettings> {
  HomeWidgetStore(this._settings) : super(_read(_settings));

  final LocalSettings _settings;

  static HomeWidgetSettings _read(LocalSettings settings) {
    final raw = settings.homeWidgets;
    if (raw == null || raw.isEmpty) return const HomeWidgetSettings();
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?>
          ? HomeWidgetSettings.fromJson(decoded)
          : const HomeWidgetSettings();
    } on FormatException {
      // A broken entry costs the widgets their settings, not the app its start.
      return const HomeWidgetSettings();
    }
  }

  /// [config] `null` takes the widget's settings away; it then asks to be set up.
  Future<void> configure(HomeWidgetKind kind, HomeWidgetConfig? config) async {
    final next = value.withConfig(kind, config);
    if (next == value) return;
    value = next;
    await _settings.setHomeWidgets(jsonEncode(next.toJson()));
  }

  /// Reads the settings again — a change of member may have cleared them underneath.
  void reload() => value = _read(_settings);

  /// The member left: their lists and calendars are no business of whoever comes next.
  Future<void> forget() async {
    value = const HomeWidgetSettings();
    await _settings.setHomeWidgets(null);
  }
}
