import 'package:flutter/widgets.dart';

import '../theme/hiwiski_metrics.dart';

/// The three width classes: compact (phone), medium (tablet, small window) and
/// expanded (desktop).
///
/// **1024 instead of Material 3's 840**: from here on three columns fit side by side —
/// content up to 680 plus info bar 260 plus margins. At 840 the info bar would be a
/// strip. The deviation is deliberate.
enum Breakpoint {
  /// < 600 — tab bar at the bottom, one column, page margin 16. The main case.
  compact,

  /// 600–1023 — navigation rail on the left, one column, the card grid kicks in.
  medium,

  /// ≥ 1024 — two columns: content plus info bar, where the content keeps its
  /// reading width beside it (`InfoBar.besideContent`). The navigation stays the rail
  /// up to 1199 and becomes the drawer from 1200 (`HiwiskiMetrics.breakpointDrawer`).
  wide;

  static Breakpoint of(BuildContext context) =>
      forWidth(MediaQuery.sizeOf(context).width);

  static Breakpoint forWidth(double width) {
    if (width >= HiwiskiMetrics.breakpointWide) return .wide;
    if (width >= HiwiskiMetrics.breakpointMedium) return .medium;
    return .compact;
  }

  bool get isCompact => this == .compact;

  bool get isWide => this == .wide;

  /// Page margin 16 when compact, 32 when wide.
  EdgeInsets get pagePadding => isCompact
      ? HiwiskiMetrics.pagePaddingCompact
      : HiwiskiMetrics.pagePaddingWide;
}
