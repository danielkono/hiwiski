import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'store_style.dart';
import 'store_texts.dart';

// The store pictures as designed: a label, a headline, a line below it and the app's
// screen in a device frame, on the app's pale green. Every measure is a share of the
// picture's width W (the status bar's of the screen's width S), so one design covers
// every size the stores ask for. The numbers in the comments are the pixels of the
// design's reference pictures: 1320 wide for phones, 2064 for tablets.

/// The design's measures for one kind of device, as shares of the picture's width —
/// the status bar's as shares of the screen's.
class const StoreTokens({
  required final double pillTop,
  required final double pillHeight,
  required final double pillPadding,
  required final double pillRadius,
  required final double pillBorder,
  required final double dot,
  required final double pillGap,
  required final double pillFont,
  required final double headlineTop,
  required final double headlineFont,
  required final double headlineInset,
  required final double sublineTop,
  required final double sublineFont,
  required final double sublineInset,
  required final double frameTop,
  required final double frameBottom,
  required final double frameMaxWidth,
  required final double frameBorder,
  required final double frameRadius,
  required final double frameEdge,
  required final double shadowY,
  required final double shadowBlur,
  required final double statusHeight,
  required final double statusFont,
  required final double statusLeft,
  required final double statusRight,
  required final double statusTop,
  required final double statusIcons,
});

/// iPhone and Android phone (reference 1320 × 2868).
const phoneTokens = StoreTokens(
  pillTop: 120 / 1320,
  pillHeight: 74 / 1320,
  pillPadding: 30 / 1320,
  pillRadius: 15 / 1320,
  pillBorder: 2 / 1320,
  dot: 20 / 1320,
  pillGap: 16 / 1320,
  pillFont: 38 / 1320,
  headlineTop: 234 / 1320,
  headlineFont: 84 / 1320,
  headlineInset: 80 / 1320,
  sublineTop: 450 / 1320,
  sublineFont: 42 / 1320,
  sublineInset: 120 / 1320,
  frameTop: 640 / 1320,
  frameBottom: 122 / 1320,
  frameMaxWidth: 992 / 1320,
  frameBorder: 21 / 1320,
  frameRadius: 108 / 1320,
  frameEdge: 3 / 1320,
  shadowY: 48 / 1320,
  shadowBlur: 96 / 1320,
  statusHeight: 114 / 950,
  statusFont: 40 / 950,
  statusLeft: 84 / 950,
  statusRight: 72 / 950,
  statusTop: 18 / 950,
  statusIcons: 30 / 950,
);

/// iPad and Android tablet (reference 2064 × 2752).
const tabletTokens = StoreTokens(
  pillTop: 150 / 2064,
  pillHeight: 84 / 2064,
  pillPadding: 36 / 2064,
  pillRadius: 17 / 2064,
  pillBorder: 3 / 2064,
  dot: 24 / 2064,
  pillGap: 18 / 2064,
  pillFont: 44 / 2064,
  headlineTop: 278 / 2064,
  headlineFont: 104 / 2064,
  headlineInset: 160 / 2064,
  sublineTop: 543 / 2064,
  sublineFont: 52 / 2064,
  sublineInset: 260 / 2064,
  frameTop: 700 / 2064,
  frameBottom: 140 / 2064,
  frameMaxWidth: 1447 / 2064,
  frameBorder: 26 / 2064,
  frameRadius: 96 / 2064,
  frameEdge: 3 / 2064,
  shadowY: 64 / 2064,
  shadowBlur: 128 / 2064,
  statusHeight: 70 / 1395,
  statusFont: 34 / 1395,
  statusLeft: 64 / 1395,
  statusRight: 56 / 1395,
  statusTop: 10 / 1395,
  statusIcons: 25 / 1395,
);

/// Where the device frame goes in a picture [size] big, for a screen [screen] big
/// (the raw screenshot's pixels; only its proportions count).
///
/// The size rule of the design: the frame is as wide as allowed, unless the height
/// left between its top and the margin below is too little — then that decides. The
/// screen is only ever scaled, never stretched or cut.
Rect frameRect(Size size, StoreTokens tokens, Size screen) {
  final width = size.width;
  final border = tokens.frameBorder * width;
  final top = tokens.frameTop * width;
  final available = size.height - top - tokens.frameBottom * width;
  final aspect = screen.height / screen.width;
  final screenWidth = math.min(
    tokens.frameMaxWidth * width - 2 * border,
    (available - 2 * border) / aspect,
  );
  final frameWidth = screenWidth + 2 * border;
  return Rect.fromLTWH(
    (width - frameWidth) / 2,
    top,
    frameWidth,
    screenWidth * aspect + 2 * border,
  );
}

/// One store picture: label, headline, the line below it and [screen] in its frame.
class StoreShot extends StatelessWidget {
  const StoreShot({
    super.key,
    required this.size,
    required this.tokens,
    required this.text,
    required this.accent,
    required this.screen,
  });

  /// The picture's size: its pixels, laid out at a pixel ratio of 1.
  final Size size;
  final StoreTokens tokens;
  final StoreText text;
  final Color accent;

  /// The app's screen as rendered for the device.
  final ui.Image screen;

  @override
  Widget build(BuildContext context) {
    final w = size.width;
    final frame = frameRect(
      size,
      tokens,
      Size(screen.width.toDouble(), screen.height.toDouble()),
    );
    final border = tokens.frameBorder * w;
    final screenWidth = frame.width - 2 * border;
    final screenRadius = (tokens.frameRadius - tokens.frameBorder) * w;
    final sublineStyle = roboto(
      tokens.sublineFont * w,
      .w400,
      storeSubline,
      height: 1.35,
    );
    final sublineWidth = w - 2 * tokens.sublineInset * w;

    return SizedBox.fromSize(
      size: size,
      child: ColoredBox(
        color: storeBackground,
        child: Stack(
          children: [
            Positioned(
              top: tokens.pillTop * w,
              left: 0,
              right: 0,
              child: Center(child: _pill(w)),
            ),
            Positioned(
              top: tokens.headlineTop * w,
              left: tokens.headlineInset * w,
              right: tokens.headlineInset * w,
              child: Text(
                text.headline,
                textAlign: .center,
                style: roboto(
                  tokens.headlineFont * w,
                  .w700,
                  storeInk,
                  height: 1.12,
                  letterSpacing: -0.006 * tokens.headlineFont * w,
                ),
              ),
            ),
            Positioned(
              top: tokens.sublineTop * w,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: _balanced(text.subline, sublineStyle, sublineWidth),
                  child: Text(
                    text.subline,
                    textAlign: .center,
                    maxLines: 2,
                    style: sublineStyle,
                  ),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: frame,
              child: Container(
                padding: .all(border),
                decoration: BoxDecoration(
                  color: storeFrame,
                  borderRadius: .circular(tokens.frameRadius * w),
                  boxShadow: [
                    BoxShadow(
                      color: storeShadow.withValues(alpha: 0.20),
                      offset: Offset(0, tokens.shadowY * w),
                      blurRadius: cssBlur(tokens.shadowBlur * w),
                    ),
                    BoxShadow(
                      color: storeShadow.withValues(alpha: 0.12),
                      offset: Offset(0, tokens.shadowY * w / 4),
                      blurRadius: cssBlur(tokens.shadowBlur * w / 4),
                    ),
                  ],
                ),
                // The light edge just inside the frame's outline.
                foregroundDecoration: BoxDecoration(
                  border: .fromBorderSide(
                    BorderSide(
                      color: storeFrameEdge,
                      width: tokens.frameEdge * w,
                    ),
                  ),
                  borderRadius: .circular(tokens.frameRadius * w),
                ),
                child: ClipRRect(
                  borderRadius: .circular(screenRadius),
                  child: ColoredBox(
                    color: storeSurface,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: RawImage(
                            image: screen,
                            fit: .fill,
                            filterQuality: .medium,
                          ),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: _StatusBar(tokens: tokens, width: screenWidth),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(double w) => Container(
    height: tokens.pillHeight * w,
    padding: .symmetric(horizontal: tokens.pillPadding * w),
    decoration: BoxDecoration(
      color: storeSurface,
      borderRadius: .circular(tokens.pillRadius * w),
      border: .fromBorderSide(
        BorderSide(color: storePillBorder, width: tokens.pillBorder * w),
      ),
    ),
    child: Row(
      mainAxisSize: .min,
      spacing: tokens.pillGap * w,
      children: [
        Container(
          width: tokens.dot * w,
          height: tokens.dot * w,
          decoration: BoxDecoration(color: accent, shape: .circle),
        ),
        Text(
          text.pill,
          style: roboto(tokens.pillFont * w, .w500, storePillInk),
        ),
      ],
    ),
  );
}

/// The narrowest width that keeps [text] on as few lines as [maxWidth] allows: the
/// lines come out about equally long, as CSS's `text-wrap: balance` makes them.
double _balanced(String text, TextStyle style, double maxWidth) {
  TextPainter laidOut(double width) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: .ltr,
    textAlign: .center,
  )..layout(maxWidth: width);

  final lines = laidOut(maxWidth).computeLineMetrics().length;
  if (lines < 2) return maxWidth;
  double low = maxWidth / lines;
  double high = maxWidth;
  while (high - low > 1) {
    final middle = (low + high) / 2;
    if (laidOut(middle).computeLineMetrics().length > lines) {
      low = middle;
    } else {
      high = middle;
    }
  }
  return high;
}

/// The status bar over the top of the screen: "9:41" on the left, signal, Wi-Fi and
/// battery on the right; no background, no camera cut-out.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.tokens, required this.width});

  final StoreTokens tokens;

  /// The screen's width S, which the bar's measures are shares of.
  final double width;

  @override
  Widget build(BuildContext context) {
    final iconHeight = tokens.statusIcons * width;
    return Container(
      height: tokens.statusHeight * width,
      padding: .only(
        left: tokens.statusLeft * width,
        top: tokens.statusTop * width,
        right: tokens.statusRight * width,
      ),
      child: Row(
        mainAxisAlignment: .spaceBetween,
        children: [
          Text(
            '9:41',
            style: roboto(
              tokens.statusFont * width,
              .w600,
              storeInk,
              height: 1,
            ),
          ),
          CustomPaint(
            size: Size(iconHeight * 5, iconHeight),
            painter: const _StatusIcons(),
          ),
        ],
      ),
    );
  }
}

/// Signal, Wi-Fi and battery, drawn on a grid of 150 × 30 units.
class _StatusIcons extends CustomPainter {
  const _StatusIcons();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.height / 30);
    final fill = Paint()..color = storeInk;
    RRect rounded(double x, double y, double w, double h, double r) =>
        .fromLTRBR(x, y, x + w, y + h, .circular(r));

    // Four bars, 10 to 28 high, standing on the bottom edge.
    for (final (index, height) in const [10.0, 16.0, 22.0, 28.0].indexed) {
      canvas.drawRRect(rounded(index * 10.0, 30 - height, 7, height, 2), fill);
    }
    // Wi-Fi: a fan with its point at the bottom.
    canvas.drawPath(
      Path()
        ..moveTo(70, 29)
        ..lineTo(52, 9)
        ..arcToPoint(const Offset(88, 9), radius: const .circular(27))
        ..close(),
      fill,
    );
    // Battery: outline, charge and pole.
    canvas
      ..drawRRect(rounded(104, 8, 30, 14, 3), fill)
      ..drawRRect(rounded(144, 11, 4, 8, 1.5), fill)
      ..drawRRect(
        rounded(100.5, 4.5, 41, 21, 6),
        Paint()
          ..color = storeInk
          ..style = .stroke
          ..strokeWidth = 2.5,
      );
  }

  @override
  bool shouldRepaint(_StatusIcons oldDelegate) => false;
}
