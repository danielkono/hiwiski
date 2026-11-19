import 'package:flutter/material.dart';

import '../shell/breakpoints.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';
import '../theme/hiwiski_tokens.dart';
import 'pull_hint.dart';
import 'tap_target.dart';

/// The filter bar that pulls away.
///
/// **On the phone the content starts below it**, the bar comes into view when pulling
/// down; a small hint ("Pull for filters") says so and disappears once the bar has
/// been visible. After a few pulls the hint is learned and leaves for good, and the
/// content moves up into its line ([PullHint]); pulling still works. Scrolling back brings it back, scrolling on takes it away — it sticks
/// like a floating bar.
///
/// *Reason:* at 390 pixels wide a permanently visible filter row is a third of the
/// visible content, and filtering is rare. **On desktop it is always there.**
///
/// It reads the scroll events of the content below — overscroll at the top edge
/// (Android) as well as bouncing in (iOS). Content that does not scroll at all has
/// none; for it the hint itself is tappable.
class PullToRevealFilter extends StatefulWidget {
  const PullToRevealFilter({
    super.key,
    required this.filter,
    required this.child,
    required this.hint,
    this.padding = EdgeInsets.zero,
    this.forceShown = false,
  });

  final Widget filter;
  final Widget child;
  final String hint;
  final EdgeInsetsGeometry padding;

  /// Keeps the bar open — e.g. in the start screen's edit mode, where it carries the
  /// buttons for leaving it again.
  final bool forceShown;

  @override
  State<PullToRevealFilter> createState() => _PullToRevealFilterState();
}

class _PullToRevealFilterState extends State<PullToRevealFilter> {
  bool _shown = false;
  bool _everShown = false;

  void _set(bool value) {
    if (value == _shown) return;
    setState(() {
      _shown = value;
      _everShown |= value;
    });
  }

  /// The bar came into view by pulling while the hint was there: one more pull
  /// towards learning it. Tapping the hint does not count — whoever taps it has not
  /// found the gesture yet.
  void _pulled() {
    if (_shown || _everShown) return;
    PullHint.pulledIn(context);
  }

  /// How far the content moved in one direction since it last turned — positive
  /// onwards, negative back.
  double _travel = 0;

  /// Travel that counts as a decision to scroll on or back.
  static const _threshold = 24.0;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != .vertical) {
      return false;
    }
    switch (notification) {
      // Only a finger opens the bar. The bounce on iOS after a fling to the top, and the
      // glow that follows on Android, report overscroll and a position at or above 0
      // just the same — with no drag behind them. Opened by those, the bar jumped out
      // whenever the list was thrown to its top.
      case OverscrollNotification(:final overscroll, :final dragDetails)
          when overscroll < 0 && dragDetails != null:
        _travel = 0;
        _pulled();
        _set(true);
      case ScrollUpdateNotification(
        :final scrollDelta?,
        :final metrics,
        :final dragDetails,
      ):
        final dragged = dragDetails != null;
        // Summed up, not per update: a slow swipe on Android moves a few pixels per
        // frame, and a rule of "more than 6 at once" never let the bar go.
        if ((_travel > 0) != (scrollDelta > 0)) _travel = 0;
        _travel += scrollDelta;
        if (dragged && (metrics.pixels <= 0 || _travel < -_threshold)) {
          if (metrics.pixels <= 0) _pulled();
          _set(true);
        } else if (_travel > _threshold && metrics.pixels > _threshold) {
          _set(false);
        }
      default:
        break;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!Breakpoint.of(context).isCompact) {
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          Padding(padding: widget.padding, child: widget.filter),
          Expanded(child: widget.child),
        ],
      );
    }

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: switch ((
            _shown || widget.forceShown,
            PullHint.showsIn(context),
          )) {
            (true, _) => Padding(padding: widget.padding, child: widget.filter),
            // Once the bar has been out, its hint goes with it — and takes its line along:
            // faded to nothing it still held the height, an empty strip above the
            // content where the filters had been.
            (false, true) when !_everShown => _Hint(
              label: widget.hint,
              onTap: () => _set(true),
            ),
            // Learned, or the bar has been out: the line goes back to the content.
            _ => const SizedBox(width: .infinity),
          },
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            // Even short content has to be pullable — otherwise the bar would never
            // come into view with three entries.
            child: ScrollConfiguration(
              behavior: const _AlwaysScrollable(),
              child: widget.child,
            ),
          ),
        ),
      ],
    );
  }
}

/// "▾ Pull for filters" — small, on `sf2`, fades once the bar has been there.
class _Hint extends StatelessWidget {
  const _Hint({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = context.scheme.onSurfaceVariant;
    // The pill stays small; the tap area around it is as high as a finger needs.
    return Center(
      child: TapTarget(
        onTap: onTap,
        child: InkWell(
          onTap: onTap,
          borderRadius: const .all(.circular(HiwiskiMetrics.radiusPill)),
          child: Container(
            padding: const .fromLTRB(
              HiwiskiMetrics.space4,
              HiwiskiMetrics.hairline,
              HiwiskiMetrics.space8,
              HiwiskiMetrics.hairline,
            ),
            decoration: BoxDecoration(
              color: context.scheme.surfaceContainer,
              borderRadius: const .all(.circular(HiwiskiMetrics.radiusPill)),
            ),
            child: Row(
              mainAxisSize: .min,
              spacing: HiwiskiMetrics.space2,
              children: [
                Icon(
                  HiwiskiSymbols.expandMore,
                  size: HiwiskiMetrics.icon16,
                  color: muted,
                ),
                Flexible(
                  child: Text(
                    label,
                    style: context.texts.labelSmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AlwaysScrollable extends MaterialScrollBehavior {
  const _AlwaysScrollable();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      AlwaysScrollableScrollPhysics(parent: super.getScrollPhysics(context));
}
