import 'dart:ui';

import 'package:web/web.dart' as web;

/// The meta tag the Flutter engine maintains.
const _themeMetaId = 'flutterweb-theme';
const _themeMetaName = 'theme-color';

/// Paints the page behind the canvas and sets `theme-color` to the app's surface.
///
/// Safari takes the colour of its bars (and of the area behind the notch) from these
/// two — before iOS 26 from `theme-color`, since then from the page itself. Chrome on
/// Android uses `theme-color`. The meta tag is the one the engine maintains
/// (`#flutterweb-theme`), so `MaterialApp.color` and this never fight over two tags.
void setPageBackground(Color color) {
  final css = _css(color);
  final document = web.document;
  (document.documentElement as web.HTMLElement?)?.style.backgroundColor = css;
  document.body?.style.backgroundColor = css;

  web.HTMLMetaElement? meta =
      document.querySelector('#$_themeMetaId') as web.HTMLMetaElement?;
  if (meta == null) {
    meta = web.HTMLMetaElement()
      ..id = _themeMetaId
      ..name = _themeMetaName;
    document.head?.append(meta);
  }
  meta.content = css;
}

String _css(Color color) {
  String channel(double value) =>
      (value * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${channel(color.r)}${channel(color.g)}${channel(color.b)}';
}
