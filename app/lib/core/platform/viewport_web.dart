import 'dart:js_interop';

import 'package:web/web.dart' as web;

const _viewportSelector = 'meta[name="viewport"]';
const _viewportName = 'viewport';
const _noFocusZoom = 'width=device-width, initial-scale=1.0, maximum-scale=1.0';

/// No zoom when a text field takes the focus.
///
/// The engine sets `maximum-scale=5.0`. Safari on the iPhone then zooms in on every
/// focused field with text smaller than 16 px — in the page editor whenever the cursor
/// reached the bottom, and the page stayed zoomed and could no longer be used. Capped
/// at 1, Safari keeps out of it; pinching still zooms, because Safari has ignored the
/// cap for gestures since iOS 10, so nobody loses zoom for reading.
void keepInputsFromZooming() {
  final document = web.document;
  web.HTMLMetaElement? meta =
      document.querySelector(_viewportSelector) as web.HTMLMetaElement?;
  if (meta == null) {
    meta = web.HTMLMetaElement()..name = _viewportName;
    document.head?.append(meta);
  }
  meta.content = _noFocusZoom;
}

/// The page stays where it is while the keyboard is open.
///
/// Safari on the iPhone scrolls the document to bring the focused field into view —
/// Flutter's hidden text field, which sits at the cursor. Flutter's picture moves with
/// it, but its idea of the screen does not: it measures the keyboard from the visible
/// height alone, not from where the visible part now starts. The page jumped, and
/// the bar docked above the keyboard (the editor's toolbar) ended up behind Safari's
/// own bar with the arrows and "Done", out of reach. Scrolled straight back, the
/// picture stays put; bringing the cursor into view is Flutter's own business.
///
/// Safari's bar itself cannot be switched off from a page.
void keepPageInPlace() {
  final viewport = web.window.visualViewport;
  if (viewport == null) return;
  void reset(web.Event _) {
    if (web.window.scrollX != 0 || web.window.scrollY != 0) {
      web.window.scrollTo(0.toJS, 0);
    }
  }

  final listener = reset.toJS;
  viewport
    ..addEventListener(_scrollEvent, listener)
    ..addEventListener(_resizeEvent, listener);
  web.window.addEventListener(_scrollEvent, listener);
}

const _scrollEvent = 'scroll';
const _resizeEvent = 'resize';

/// What Safari's bar above the keyboard — the arrows and "Done" — covers of the
/// visible page, in logical pixels.
///
/// On the iPhone since iOS 26 that bar floats over the page instead of sitting above
/// it: the visible height Safari reports, and with it Flutter's keyboard inset, ends
/// at the keyboard, and whatever was docked there (the editor's toolbar) lay under
/// the bar, out of reach. No browser API reports the bar, so its height is a
/// constant, measured on an iPhone.
///
/// An older iOS put the bar outside the visible page and needs no room. Since iOS 26
/// the user agent freezes the system version at 18, so the system version only tells
/// an iOS below 18 apart; Safari's own version (absent in other browsers and in a web
/// app on the home screen) still counts on. Only such a browser on a real iOS 18
/// cannot be told from iOS 26 and keeps the room.
double keyboardBarOverlap() {
  final agent = web.window.navigator.userAgent;
  if (!agent.contains(_iPhone)) return 0;
  final safari = _major(_safariVersion, agent);
  if (safari != null) {
    return safari < _floatingBarSince ? 0 : _floatingBarHeight;
  }
  final system = _major(_systemVersion, agent);
  if (system != null && system < _frozenSystemVersion) return 0;
  return _floatingBarHeight;
}

int? _major(RegExp version, String agent) {
  final digits = version.firstMatch(agent)?.group(1);
  return digits == null ? null : int.tryParse(digits);
}

const _iPhone = 'iPhone';
final _safariVersion = RegExp(r'Version/(\d+)');
final _systemVersion = RegExp(r'iPhone OS (\d+)_');
const _floatingBarSince = 26;
const _frozenSystemVersion = 18;

/// From the top of the bar to the keyboard, with a little air.
const _floatingBarHeight = 60.0;
