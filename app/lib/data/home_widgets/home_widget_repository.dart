import 'dart:convert';

import 'package:clock/clock.dart';

import '../../core/api/generated/export.dart';
import '../../core/platform/home_widget_bridge.dart';
import '../../domain/home_widgets/home_widget_settings.dart';

/// Hands the home screen widgets what they show: the settings, the app's own picture
/// of each widget's content, and the session they ask the server with.
///
/// The widgets refresh themselves while the app is closed, from the server. What the
/// app hands over is the picture of its own database — the one that also holds the
/// changes not yet sent. The widget keeps whichever is newer and the app's while it
/// still waits to send something (`docs/development/home-widgets.md`).
class HomeWidgetRepository {
  const HomeWidgetRepository(this._bridge);

  final HomeWidgetBridge _bridge;

  static const _sourceKey = 'source';
  static const _sourceApp = 'app';
  static const _savedAtKey = 'savedAt';
  static const _pendingKey = 'pending';
  static const _configKey = 'config';
  static const _agendaKey = 'agenda';
  static const _listKey = 'list';
  static const _itemsKey = 'items';
  static const _dueDateKey = 'dueDate';

  /// `yyyy-MM-dd` — the length of a date at the start of an ISO timestamp.
  static const _dateLength = 10;

  bool get supported => _bridge.supported;

  Future<void> publishConfig(HomeWidgetSettings settings) =>
      _bridge.setConfig(jsonEncode(settings.toJson()));

  /// [pending]: the device still waits to send a change to these calendars — until it
  /// has, the server's answer would show the old state.
  Future<void> publishAgenda(
    HomeWidgetConfig config,
    Agenda agenda, {
    required bool pending,
  }) => _bridge.setSnapshot(
    HomeWidgetKind.agenda.name,
    jsonEncode(
      _envelope(HomeWidgetKind.agenda, config, pending: pending)
        ..[_agendaKey] = agenda.toJson(),
    ),
  );

  Future<void> publishList(
    HomeWidgetKind kind,
    HomeWidgetConfig config,
    ListSummary summary, {
    required bool pending,
  }) => _bridge.setSnapshot(
    kind.name,
    jsonEncode(
      _envelope(kind, config, pending: pending)
        ..[_listKey] = _listJson(summary),
    ),
  );

  /// The app has no picture for [kind]: it is not set up, or its list is gone. The
  /// widget then asks to be set up — or shows what it fetched itself.
  Future<void> forget(HomeWidgetKind kind) =>
      _bridge.setSnapshot(kind.name, null);

  Future<void> publishCredentials({String? server, String? token}) =>
      _bridge.setCredentials(server: server, token: token);

  Future<void> clear() => _bridge.clear();

  Map<String, Object?> _envelope(
    HomeWidgetKind kind,
    HomeWidgetConfig config, {
    required bool pending,
  }) => {
    _sourceKey: _sourceApp,
    _savedAtKey: clock.now().toUtc().toIso8601String(),
    _pendingKey: pending,
    _configKey: config.toJsonFor(kind),
  };

  /// As the server writes it: a due date is a date, `yyyy-MM-dd`, not a timestamp —
  /// the widgets' generated clients read it as one.
  static Map<String, Object?> _listJson(ListSummary summary) {
    final json =
        jsonDecode(jsonEncode(summary.toJson())) as Map<String, Object?>;
    for (final item in (json[_itemsKey] as List? ?? const [])) {
      if (item case {_dueDateKey: final String due}) {
        (item as Map<String, Object?>)[_dueDateKey] = due.substring(
          0,
          _dateLength,
        );
      }
    }
    return json;
  }
}
