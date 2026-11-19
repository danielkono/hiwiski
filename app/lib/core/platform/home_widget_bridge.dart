import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The channel to the native home screen widgets — `HomeWidgetBridge.swift` on iOS,
/// `HomeWidgetBridge.kt` on Android.
///
/// The widgets are native, not Flutter: a widget refreshes in a process of its own while
/// the app is closed, and only native code runs there. What the app hands over is
/// stored where the widget can read it (an App Group on iOS, the app's own storage on
/// Android); every write asks the system to redraw the widgets. What is stored where is
/// described in `docs/development/home-widgets.md`.
class HomeWidgetBridge {
  const HomeWidgetBridge();

  static const _channel = MethodChannel(
    'de.danielkononov.hiwiski/home_widgets',
  );

  static const _setConfig = 'setConfig';
  static const _setSnapshot = 'setSnapshot';
  static const _setCredentials = 'setCredentials';
  static const _clear = 'clear';

  static const _kindArgument = 'kind';
  static const _jsonArgument = 'json';
  static const _serverArgument = 'server';
  static const _tokenArgument = 'token';

  /// Only the phones' and tablets' home screens have these widgets.
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == .android || defaultTargetPlatform == .iOS);

  /// Which widget shows what, as a JSON document.
  Future<void> setConfig(String json) =>
      _call(_setConfig, {_jsonArgument: json});

  /// The app's own picture for [kind]; `null` removes it.
  Future<void> setSnapshot(String kind, String? json) =>
      _call(_setSnapshot, {_kindArgument: kind, _jsonArgument: json});

  /// Where and as whom the widgets ask the server themselves; `null` takes it away.
  /// Kept in the keychain (iOS) or encrypted with a key of the Android keystore.
  Future<void> setCredentials({String? server, String? token}) =>
      _call(_setCredentials, {_serverArgument: server, _tokenArgument: token});

  /// Everything the widgets hold — after a sign-out nothing of the member may stay on
  /// the home screen.
  Future<void> clear() => _call(_clear, const {});

  Future<void> _call(String method, Map<String, Object?> arguments) async {
    if (!supported) return;
    await _channel.invokeMethod<void>(method, arguments);
  }
}
