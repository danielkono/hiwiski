import 'package:flutter/widgets.dart';

import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../domain/wiki/mindmap.dart';

/// Where the canvas looks: the scale, and where the map's origin lies on screen. A
/// point of the map at `p` is drawn at `origin + p * scale`.
///
/// Moves made by hand change it at once; [show] glides there, so a jump to a search
/// hit is followed by the eye.
class MindmapCamera extends ChangeNotifier {
  static const minScale = 0.1;
  static const maxScale = 4.0;

  double _scale = 1;
  Offset _origin = .zero;
  Size _viewport = .zero;
  AnimationController? _glide;
  bool _placed = false;

  double get scale => _scale;
  Offset get origin => _origin;
  Size get viewport => _viewport;

  /// Whether it has been pointed at the map once — before that the first layout
  /// fits the map in.
  bool get placed => _placed;

  /// The part of the map in view, in the map's units.
  Rect get visible => .fromLTWH(
    -_origin.dx / _scale,
    -_origin.dy / _scale,
    _viewport.width / _scale,
    _viewport.height / _scale,
  );

  /// What the canvas builds: the part in view and a screen's worth around it. An
  /// element is built before it comes into view while the map is moved or zoomed —
  /// its pictures are loaded by then, not shown blank for a moment at the edge.
  Rect get nearby {
    final view = visible;
    return view.inflate(view.longestSide);
  }

  /// The point of the map under [local], a point of the canvas.
  Offset toScene(Offset local) => (local - _origin) / _scale;

  /// The canvas point that shows [scene].
  Offset toLocal(Offset scene) => _origin + scene * _scale;

  /// Lets [show] glide — the canvas's ticker. A glide under way on the one before
  /// ends where it is.
  void attach(TickerProvider vsync) {
    _endGlide();
    _glide?.dispose();
    _glide = AnimationController(vsync: vsync, duration: _glideDuration);
    _vsync = vsync;
  }

  /// Lets go of [vsync]'s ticker as the canvas goes — before the screen around it
  /// lets go of the camera: a glide still under way would leave the ticker running,
  /// which the canvas may not be disposed with. Until the next [attach], the camera
  /// jumps instead of gliding.
  void detach(TickerProvider vsync) {
    if (!identical(vsync, _vsync)) return;
    _endGlide();
    _glide?.dispose();
    _glide = null;
    _vsync = null;
  }

  TickerProvider? _vsync;

  void resize(Size viewport) {
    if (viewport == _viewport) return;
    // The centre stays where it was: a phone turned shows the same place.
    final centre = _viewport.isEmpty
        ? null
        : toScene(_viewport.center(Offset.zero));
    _viewport = viewport;
    if (centre != null) {
      _origin = viewport.center(Offset.zero) - centre * _scale;
    }
  }

  void set(double scale, Offset origin) {
    _endGlide();
    _scale = scale.clamp(minScale, maxScale);
    _origin = origin;
    _placed = true;
    notifyListeners();
  }

  void panBy(Offset delta) => set(_scale, _origin + delta);

  /// Zooms by [factor] around [focal], a point of the canvas that stays put.
  void zoomAt(Offset focal, double factor) {
    final scale = (_scale * factor).clamp(minScale, maxScale);
    set(scale, focal - (focal - _origin) * (scale / _scale));
  }

  /// What lies over the canvas at its edges — the header, the bars, the phone's
  /// notch and home indicator. The canvas runs under them; what is fitted or shown is
  /// placed in the free part between.
  EdgeInsets padding = .zero;

  /// Fits [content] — the whole map, if `null` its middle — into view.
  void fit(Rect? content, {bool glide = false}) {
    if (_viewport.isEmpty) return;
    final camera = _into(content ?? .zero, margin: _margin, maxScale: 1);
    glide
        ? _glideTo(camera.scale, camera.origin)
        : set(camera.scale, camera.origin);
  }

  /// [fitInto] the free part of the view.
  ({double scale, Offset origin}) _into(
    Rect content, {
    required double margin,
    required double maxScale,
  }) {
    final free = padding.deflateSize(_viewport);
    final usable = free.isEmpty ? _viewport : free;
    final camera = fitInto(
      content,
      usable,
      margin: margin,
      maxScale: maxScale,
      minScale: minScale,
    );
    return (
      scale: camera.scale,
      origin: camera.origin + (free.isEmpty ? Offset.zero : padding.topLeft),
    );
  }

  /// Brings [rect] into the middle of the view, close enough to read.
  void show(Rect rect) {
    if (_viewport.isEmpty) return;
    final camera = _into(
      rect,
      margin: _margin * 2,
      maxScale: _scale < 1 ? 1 : _scale,
    );
    _glideTo(camera.scale, camera.origin);
  }

  void _glideTo(double scale, Offset origin) {
    final glide = _glide;
    if (glide == null) {
      set(scale, origin);
      return;
    }
    _endGlide();
    final fromScale = _scale;
    final fromOrigin = _origin;
    final curve = CurvedAnimation(parent: glide, curve: Curves.easeInOut);
    void step() {
      final t = curve.value;
      _scale = fromScale + (scale - fromScale) * t;
      _origin = Offset.lerp(fromOrigin, origin, t) ?? origin;
      _placed = true;
      notifyListeners();
    }

    curve.addListener(step);
    _curve = curve;
    _step = step;
    // Stopped by a hand on the canvas, or by the canvas going away, a glide just
    // ends where it is: nothing waits for it, and there is nothing to report.
    glide.forward(from: 0).ignore();
  }

  /// A glide under way stops where it is — a hand on the canvas takes over.
  void _endGlide() {
    _glide?.stop();
    final step = _step;
    if (step != null) _curve?.removeListener(step);
    _curve?.dispose();
    _curve = null;
    _step = null;
  }

  CurvedAnimation? _curve;
  VoidCallback? _step;

  @override
  void dispose() {
    _endGlide();
    _glide?.dispose();
    super.dispose();
  }

  static const _margin = HiwiskiMetrics.minTapTarget;
  static const _glideDuration = Duration(milliseconds: 320);
}
