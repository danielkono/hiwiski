import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import 'image_counter.dart';
import 'rich_image.dart';
import 'rich_text_keys.dart';

/// Opens a group of images large, at [initial] — the image grows out of the card it
/// was on (hero [heroTag]) into the place it takes on the screen, and flies back
/// there when closed.
///
/// [aspects] are the shapes known already, width over height, by image id: the large
/// view lays an image out at its shape from the first frame, so the flight ends where
/// the image is — not in the middle of an empty screen. [previewWidth] is the width
/// the card decoded at: the flight shows that version, already decoded, and the whole
/// image fades in over it once it is ready.
Future<void> showImageGallery(
  BuildContext context, {
  required List<String> imageIds,
  required int initial,
  required Object Function(String imageId) heroTag,
  required Map<String, double> aspects,
  required int previewWidth,
  required ValueChanged<int> onShown,
}) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, animation, _) => ImageGallery(
      imageIds: imageIds,
      initial: initial,
      heroTag: heroTag,
      aspects: aspects,
      previewWidth: previewWidth,
      animation: animation,
      onShown: onShown,
    ),
  ),
);

/// The images of a group large, one per page: swiped through, zoomed with two
/// fingers or the wheel, closed with the cross, "Escape", "Back" or a swipe down.
class ImageGallery extends StatefulWidget {
  const ImageGallery({
    super.key,
    required this.imageIds,
    required this.initial,
    required this.heroTag,
    required this.aspects,
    required this.previewWidth,
    required this.animation,
    required this.onShown,
  });

  final List<String> imageIds;
  final int initial;
  final Object Function(String imageId) heroTag;
  final Map<String, double> aspects;
  final int previewWidth;

  /// The route's: the dark background fades in with it while the image flies.
  final Animation<double> animation;

  /// The image now shown — the pile below turns along.
  final ValueChanged<int> onShown;

  @override
  State<ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<ImageGallery>
    with SingleTickerProviderStateMixin {
  /// Until an image is decoded and says otherwise — the cards' shape.
  static const _defaultAspect = 4 / 3;

  /// The share of the screen's height a swipe down has to travel to close.
  static const _closeShare = 0.15;

  /// How fast a shorter swipe down has to be to close, in pixels per second.
  static const _closeVelocity = 700.0;

  /// How much smaller the image gets while pulled down half the screen.
  static const _pulledShrink = 0.2;

  /// How far the image is pulled down, in pixels — the background fades with it.
  double _pulled = 0;

  /// Brings a pull that was let go too early back up.
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  double _settleFrom = 0;

  late final _pages = PageController(initialPage: widget.initial);
  late int _shown = widget.initial;
  late final _aspects = {...widget.aspects};

  /// While an image is zoomed in, a swipe moves it instead of turning the page.
  bool _zoomed = false;

  int get _count => widget.imageIds.length;

  @override
  void initState() {
    super.initState();
    _settle.addListener(_settling);
  }

  void _settling() => setState(
    () => _pulled =
        _settleFrom * (1 - Curves.easeOutCubic.transform(_settle.value)),
  );

  @override
  void dispose() {
    _pages.dispose();
    _settle
      ..removeListener(_settling)
      ..dispose();
    super.dispose();
  }

  void _pull(DragUpdateDetails details) {
    _settle.stop();
    setState(
      () => _pulled = (_pulled + details.delta.dy).clamp(0, double.infinity),
    );
  }

  /// Far or fast enough, the gallery closes from where the image is: the flight back
  /// to its card starts there. Otherwise it springs back.
  void _letGo(DragEndDetails details, double height) {
    final velocity = details.primaryVelocity ?? 0;
    if (_pulled > height * _closeShare || velocity > _closeVelocity) {
      Navigator.of(context).pop();
      return;
    }
    _settleFrom = _pulled;
    // An animation's future only ends — it fails only with a disposed ticker.
    _settle.forward(from: 0).ignore();
  }

  void _go(int delta) {
    final target = _shown + delta;
    if (target < 0 || target >= _count) return;
    // An animation's future only ends — it fails only with a disposed controller.
    _pages
        .animateToPage(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        )
        .ignore();
  }

  void _aspectOf(String id, double aspect) {
    if (_aspects[id] == aspect) return;
    setState(() => _aspects[id] = aspect);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;
    final several = _count > 1;
    final height = MediaQuery.sizeOf(context).height;
    // 0 at rest, 1 pulled down half the screen.
    final pulled = (_pulled / (height / 2)).clamp(0.0, 1.0);
    final shown = 1 - pulled;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: FadeTransition(
                opacity: widget.animation,
                child: ColoredBox(
                  color: scheme.scrim.withValues(alpha: scheme.scrim.a * shown),
                ),
              ),
            ),
            // A swipe down closes: the image follows the finger and shrinks a little,
            // the background fades. Zoomed in, the swipe moves the image instead.
            GestureDetector(
              onVerticalDragUpdate: _zoomed ? null : _pull,
              onVerticalDragEnd: _zoomed
                  ? null
                  : (details) => _letGo(details, height),
              child: Transform.translate(
                offset: Offset(0, _pulled),
                child: Transform.scale(
                  scale: 1 - _pulledShrink * pulled,
                  // With the mouse too: in the browser a page view turns by touch only.
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context)
                        .copyWith(dragDevices: {...PointerDeviceKind.values}),
                    child: PageView.builder(
                      key: RichTextKeys.imageGallery,
                      controller: _pages,
                      physics: _zoomed
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      itemCount: _count,
                      onPageChanged: (index) {
                        setState(() {
                          _shown = index;
                          _zoomed = false;
                        });
                        widget.onShown(index);
                      },
                      itemBuilder: (context, index) {
                        final id = widget.imageIds[index];
                        return _ZoomablePage(
                          onZoomed: (zoomed) {
                            if (zoomed != _zoomed) {
                              setState(() => _zoomed = zoomed);
                            }
                          },
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              // Exactly the place the image takes — the hero's rect, so
                              // the flight lands on the image and not on the screen.
                              final aspect = _aspects[id] ?? _defaultAspect;
                              final height = constraints.maxHeight;
                              final size = applyBoxFit(
                                .contain,
                                Size(aspect * height, height),
                                constraints.biggest,
                              ).destination;
                              return Center(
                                child: SizedBox.fromSize(
                                  size: size,
                                  child: Hero(
                                    tag: widget.heroTag(id),
                                    flightShuttleBuilder: _flight,
                                    child: _GalleryImage(
                                      imageId: id,
                                      previewWidth: widget.previewWidth,
                                      onAspect: (aspect) =>
                                          _aspectOf(id, aspect),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: HiwiskiMetrics.space8,
              right: HiwiskiMetrics.space8,
              child: SafeArea(
                child: FadeTransition(
                  opacity: widget.animation,
                  child: Opacity(
                    opacity: shown,
                    child: IconButton.filledTonal(
                      key: RichTextKeys.imageGalleryClose,
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      icon: const Icon(HiwiskiSymbols.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
            ),
            if (several)
              Positioned(
                left: 0,
                right: 0,
                bottom: HiwiskiMetrics.space16,
                child: SafeArea(
                  child: FadeTransition(
                    opacity: widget.animation,
                    child: Opacity(
                      opacity: shown,
                      child: Row(
                        mainAxisAlignment: .center,
                        spacing: HiwiskiMetrics.space12,
                        children: [
                          IconButton.filledTonal(
                            tooltip: l.wikiImagePrevious,
                            icon: const Icon(HiwiskiSymbols.chevronLeft),
                            onPressed: _shown > 0 ? () => _go(-1) : null,
                          ),
                          ImageCounter(text: '${_shown + 1}/$_count'),
                          IconButton.filledTonal(
                            tooltip: l.wikiImageNext,
                            icon: const Icon(HiwiskiSymbols.chevronRight),
                            onPressed: _shown < _count - 1
                                ? () => _go(1)
                                : null,
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
}

/// What flies between the card and the large view, both ways: the large view's
/// image, **filling** the flying rect — at the start that is exactly the card's cut,
/// at the end the whole image, as the rect turns from the card's shape into the
/// image's. The corners round off as it leaves the card and come back as it returns.
// Flutter's hero API: the shuttle is built by a function.
// ignore: many_lints/avoid_returning_widgets
Widget _flight(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final large =
      (direction == .push ? toHeroContext : fromHeroContext).widget as Hero;
  return AnimatedBuilder(
    animation: animation,
    builder: (context, child) => ClipRRect(
      borderRadius: .circular(
        lerpDouble(HiwiskiMetrics.radiusCard, 0, animation.value) ?? 0,
      ),
      child: child,
    ),
    child: large.child,
  );
}

/// In the browser the whole image is decoded at most at twice the screen's width —
/// room to zoom in, but no 24 megapixel texture: Safari on the iPhone gives a page
/// little of it, and a few of them left the page without images.
int _browserWidth(BuildContext context) =>
    (MediaQuery.sizeOf(context).width *
            MediaQuery.devicePixelRatioOf(context) *
            2)
        .round();

/// An image in the large view: the version the card decoded first — in the cache
/// already, so there from the first frame of the flight — and the whole image over
/// it once that is decoded. Both fill the rect, which has the image's shape.
class _GalleryImage extends StatelessWidget {
  const _GalleryImage({
    required this.imageId,
    required this.previewWidth,
    required this.onAspect,
  });

  final String imageId;
  final int previewWidth;
  final ValueChanged<double> onAspect;

  @override
  Widget build(BuildContext context) => Stack(
    fit: .expand,
    children: [
      RichImage(
        imageId: imageId,
        fit: .cover,
        decodeWidth: previewWidth,
        onAspect: onAspect,
        preview: true,
      ),
      RichImage(
        imageId: imageId,
        fit: .cover,
        decodeWidth: kIsWeb ? _browserWidth(context) : null,
        placeholder: false,
      ),
    ],
  );
}

/// One image of the large view, zoomed with two fingers or the wheel. Says when it
/// is zoomed in: then a swipe moves the image, not the pages.
class _ZoomablePage extends StatefulWidget {
  const _ZoomablePage({required this.onZoomed, required this.child});

  final ValueChanged<bool> onZoomed;
  final Widget child;

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  /// Above this the image counts as zoomed in.
  static const _zoomedScale = 1.01;

  final _transform = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_changed);
  }

  void _changed() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > _zoomedScale;
    if (zoomed == _zoomed) return;
    setState(() => _zoomed = zoomed);
    widget.onZoomed(zoomed);
  }

  @override
  void dispose() {
    _transform
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InteractiveViewer(
    transformationController: _transform,
    maxScale: 5,
    // Not zoomed, a one-finger swipe belongs to the pages.
    panEnabled: _zoomed,
    child: widget.child,
  );
}
