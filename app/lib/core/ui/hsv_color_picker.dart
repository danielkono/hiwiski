import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/hiwiski_metrics.dart';

/// A colour picked by eye, not by its code: a field — saturation across, brightness
/// up — a strip of hues below it and, where [opacity], one of how much the colour
/// covers what lies under it, each dragged or tapped.
///
/// A screen reader works them as sliders: the field makes the colour brighter or
/// darker, the strips turn the hue and make the colour more or less see-through.
class HsvColorPicker extends StatelessWidget {
  const HsvColorPicker({
    super.key,
    required this.color,
    required this.onChanged,
    this.opacity = false,
  });

  final HSVColor color;
  final ValueChanged<HSVColor> onChanged;

  /// Whether the colour's alpha is picked too.
  final bool opacity;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final outline = Theme.of(context).colorScheme.outline;
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: [
        Semantics(
          slider: true,
          label: l.mindmapColorBrightness,
          value: _percent(color.value),
          increasedValue: _percent((color.value + _step).clamp(0, 1)),
          decreasedValue: _percent((color.value - _step).clamp(0, 1)),
          onIncrease: () =>
              onChanged(color.withValue((color.value + _step).clamp(0, 1))),
          onDecrease: () =>
              onChanged(color.withValue((color.value - _step).clamp(0, 1))),
          child: SizedBox(
            height: HiwiskiMetrics.colorFieldHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                void pick(Offset at) => onChanged(
                  color
                      .withSaturation((at.dx / size.width).clamp(0, 1))
                      .withValue(1 - (at.dy / size.height).clamp(0, 1)),
                );
                return GestureDetector(
                  excludeFromSemantics: true,
                  onPanDown: (details) => pick(details.localPosition),
                  onPanUpdate: (details) => pick(details.localPosition),
                  child: ClipRRect(
                    borderRadius: const .all(
                      .circular(HiwiskiMetrics.radiusChip),
                    ),
                    child: CustomPaint(
                      size: size,
                      painter: _FieldPainter(color: color, ring: outline),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space12),
        Semantics(
          slider: true,
          label: l.mindmapColorHue,
          value: '${color.hue.round()}°',
          increasedValue: '${((color.hue + _hueStep) % _circle).round()}°',
          decreasedValue: '${((color.hue - _hueStep) % _circle).round()}°',
          onIncrease: () =>
              onChanged(color.withHue((color.hue + _hueStep) % _circle)),
          onDecrease: () =>
              onChanged(color.withHue((color.hue - _hueStep) % _circle)),
          child: SizedBox(
            height: HiwiskiMetrics.hueStripHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                void pick(Offset at) => onChanged(
                  color.withHue((at.dx / width).clamp(0, 1) * (_circle - 1)),
                );
                return GestureDetector(
                  excludeFromSemantics: true,
                  onPanDown: (details) => pick(details.localPosition),
                  onPanUpdate: (details) => pick(details.localPosition),
                  child: CustomPaint(
                    size: constraints.biggest,
                    painter: _HuePainter(hue: color.hue, ring: outline),
                  ),
                );
              },
            ),
          ),
        ),
        if (opacity) ...[
          const SizedBox(height: HiwiskiMetrics.space12),
          Semantics(
            slider: true,
            label: l.mindmapColorOpacity,
            value: _percent(color.alpha),
            increasedValue: _percent((color.alpha + _step).clamp(0, 1)),
            decreasedValue: _percent((color.alpha - _step).clamp(0, 1)),
            onIncrease: () =>
                onChanged(color.withAlpha((color.alpha + _step).clamp(0, 1))),
            onDecrease: () =>
                onChanged(color.withAlpha((color.alpha - _step).clamp(0, 1))),
            child: SizedBox(
              height: HiwiskiMetrics.hueStripHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  void pick(Offset at) =>
                      onChanged(color.withAlpha((at.dx / width).clamp(0, 1)));
                  return GestureDetector(
                    excludeFromSemantics: true,
                    onPanDown: (details) => pick(details.localPosition),
                    onPanUpdate: (details) => pick(details.localPosition),
                    child: CustomPaint(
                      size: constraints.biggest,
                      painter: _AlphaPainter(color: color, ring: outline),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _percent(double share) => '${(share * 100).round()} %';

  static const _step = 0.05;
  static const _hueStep = 10.0;
  static const _circle = 360.0;
}

/// The ring marking the picked point: light inside a dark line, visible on any colour.
void _paintThumb(Canvas canvas, Offset at, Color ring) {
  canvas
    ..drawCircle(
      at,
      HiwiskiMetrics.colorThumb / 2,
      Paint()
        ..style = .stroke
        ..strokeWidth = HiwiskiMetrics.strokeBold * 2
        ..color = _white,
    )
    ..drawCircle(
      at,
      HiwiskiMetrics.colorThumb / 2 + HiwiskiMetrics.strokeBold,
      Paint()
        ..style = .stroke
        ..strokeWidth = HiwiskiMetrics.hairline
        ..color = ring,
    );
}

/// White and black as colours of the HSV space itself: the field fades to them.
final _white = const HSVColor.fromAHSV(1, 0, 0, 1).toColor();
final _black = const HSVColor.fromAHSV(1, 0, 0, 0).toColor();
final _clear = const HSVColor.fromAHSV(0, 0, 0, 0).toColor();

class _FieldPainter extends CustomPainter {
  _FieldPainter({required this.color, required this.ring});

  final HSVColor color;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final pure = HSVColor.fromAHSV(1, color.hue, 1, 1).toColor();
    canvas
      ..drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(colors: [_white, pure]).createShader(rect),
      )
      ..drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: .topCenter,
            end: .bottomCenter,
            colors: [_clear, _black],
          ).createShader(rect),
      );
    _paintThumb(
      canvas,
      Offset(color.saturation * size.width, (1 - color.value) * size.height),
      ring,
    );
  }

  @override
  bool shouldRepaint(_FieldPainter old) =>
      old.color != color || old.ring != ring;
}

/// Squares behind what may be see-through, so that it shows how much is.
void paintChecks(Canvas canvas, RRect area, {required double square}) {
  canvas
    ..save()
    ..clipRRect(area)
    ..drawRRect(area, Paint()..color = _white);
  final grey = Paint()..color = _checkGrey;
  final rect = area.outerRect;
  for (double y = rect.top; y < rect.bottom; y += square) {
    final odd = ((y - rect.top) / square).round().isOdd;
    for (
      double x = rect.left + (odd ? square : 0);
      x < rect.right;
      x += square * 2
    ) {
      canvas.drawRect(Rect.fromLTWH(x, y, square, square), grey);
    }
  }
  canvas.restore();
}

final _checkGrey = const HSVColor.fromAHSV(1, 0, 0, 0.8).toColor();

/// The colour from see-through to covering, over the squares.
class _AlphaPainter extends CustomPainter {
  _AlphaPainter({required this.color, required this.ring});

  final HSVColor color;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final strip = RRect.fromRectAndRadius(rect, .circular(size.height / 2));
    paintChecks(canvas, strip, square: size.height / 2);
    canvas.drawRRect(
      strip,
      Paint()
        ..shader = LinearGradient(
          colors: [color.withAlpha(0).toColor(), color.withAlpha(1).toColor()],
        ).createShader(rect),
    );
    _paintThumb(
      canvas,
      Offset(color.alpha * size.width, size.height / 2),
      ring,
    );
  }

  @override
  bool shouldRepaint(_AlphaPainter old) =>
      old.color != color || old.ring != ring;
}

class _HuePainter extends CustomPainter {
  _HuePainter({required this.hue, required this.ring});

  final double hue;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, .circular(size.height / 2)),
      Paint()
        ..shader = LinearGradient(
          colors: [
            for (int degree = 0; degree <= _circle; degree += _span)
              HSVColor.fromAHSV(
                1,
                (degree % _circle).toDouble(),
                1,
                1,
              ).toColor(),
          ],
        ).createShader(rect),
    );
    _paintThumb(
      canvas,
      Offset(hue / _circle * size.width, size.height / 2),
      ring,
    );
  }

  static const _circle = 360;
  static const _span = 60;

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue || old.ring != ring;
}
