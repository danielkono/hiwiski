import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import 'image_counter.dart';
import 'image_gallery.dart';
import 'rich_image.dart';
import 'rich_text_keys.dart';

/// Images in a text — a page's, a task's description, an event's note. One image stands alone;
/// a **group lies stacked** like a pile of cards: the front image whole, the next ones
/// peeking out behind it, slightly turned. A swipe — with a finger or the mouse, to
/// either side — or a click turns the pile: the front card flies off to the side it
/// was swiped to and slides in again at the back while the others move up, as a
/// pile of real cards does. The button in the corner — or a tap on a single image —
/// opens the images large: the front one grows out of its card into the screen, and
/// the others of the group follow by swiping there; closed, the one shown flies back
/// to the front of the pile.
///
/// **Every image is a card of its own** that keeps its image and only changes its
/// place — the images are not swapped between fixed places, which flickered as each
/// place loaded its next image. All of a group's cards are built at once, the ones
/// beyond the visible pile invisibly: their images are loaded before they come up.
class ImageStack extends StatefulWidget {
  const ImageStack({super.key, required this.imageIds});

  final List<String> imageIds;

  @override
  State<ImageStack> createState() => _ImageStackState();
}

/// A turn of the pile under way: the front card going to the back, and the side it
/// flies off to on its way.
class const _Turn(
  /// The card that goes from the front to the back.
  final String moving,

  /// `-1` off to the left, `1` off to the right — the way it was swiped.
  final int side,

  /// Where the front card stood when the turn began — a swipe let go mid-way.
  final double fromDrag,
);

/// Where a card stands: its shift, its turn and whether it shows.
class const _Pose(
  final double dx,
  final double dy,
  final double rotation,
  final double opacity,
) {
  /// The way from here to [to], [t] of it gone.
  _Pose towards(_Pose to, double t) => .new(
    dx + (to.dx - dx) * t,
    dy + (to.dy - dy) * t,
    rotation + (to.rotation - rotation) * t,
    opacity + (to.opacity - opacity) * t,
  );
}

class _ImageStackState extends State<ImageStack> with TickerProviderStateMixin {
  /// How many images show behind the front one.
  static const _behind = 2;

  /// The turn of an image behind the front one, in radians — a few degrees.
  static const _tilt = 0.05;

  /// The share of the width a swipe has to travel to count.
  static const _swipeShare = 0.25;
  static const _flingSpeed = 600.0;

  /// How far off to the side a card flies while it changes ends, as a share of the
  /// card's width.
  static const _flyOut = 0.85;

  int _front = 0;
  double _drag = 0;

  /// What sets this pile's flights apart from another's: the same image may stand in
  /// two places of a page, and a hero's tag must be unique.
  final _heroScope = Object();

  /// The images' shapes, width over height, as the cards decoded them — the large
  /// view lays an image out at its shape from its first frame.
  final _aspects = <String, double>{};

  /// The width the cards decode at — the large view's flight shows that version.
  int _decodeWidth = 0;

  Object _heroTag(String imageId) => (_heroScope, imageId);
  _Turn? _turning;

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(_settleStep);

  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  /// A swipe let go too early slides back.
  void _settleStep() =>
      setState(() => _drag = _settleFrom * (1 - _settle.value));

  double _settleFrom = 0;

  int get _count => widget.imageIds.length;

  @override
  void didUpdateWidget(ImageStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_front >= _count) _front = 0;
  }

  @override
  void dispose() {
    _settle.dispose();
    _turn.dispose();
    super.dispose();
  }

  /// Turns the pile by one: the front card goes to the back, flying off to [side]
  /// first (`-1` left, `1` right), and the next image comes up.
  Future<void> _step({int side = -1, double fromDrag = 0}) async {
    if (_count < 2) return;
    // A turn still under way ends where it was going.
    _turn.value = 1;
    final moving = widget.imageIds[_front];
    setState(() {
      _front = (_front + 1) % _count;
      _drag = 0;
      _turning = _Turn(moving, side, fromDrag);
    });
    await _turn.forward(from: 0);
    if (mounted) setState(() => _turning = null);
  }

  /// A click: the next image to the front.
  void _next() {
    // An animation's future only ends — it fails only with a disposed ticker.
    _step().ignore();
  }

  void _release(double width, double velocity) {
    final far = _drag.abs() > width * _swipeShare;
    final fast = velocity.abs() > _flingSpeed;
    if (far || fast) {
      // Either way the next one comes up — like a pile of cards, the top one
      // goes where it was swiped.
      // An animation's future only ends — it fails only with a disposed ticker.
      _step(
        side: (far ? _drag : velocity) < 0 ? -1 : 1,
        fromDrag: _drag,
      ).ignore();
      return;
    }
    _settleFrom = _drag;
    // An animation's future only ends — it fails only with a disposed ticker.
    _settle.forward(from: 0).ignore();
  }

  /// A card's place [depth] steps behind the front, at rest.
  _Pose _poseAt(int depth, double width, {double drag = 0}) {
    final shown = math.min(depth, _behind);
    return _Pose(
      drag + shown * HiwiskiMetrics.imageStackStep,
      -shown * HiwiskiMetrics.imageStackStep / 2,
      switch (shown) {
        0 => drag / width * _tilt * 2,
        _ when shown.isOdd => _tilt,
        _ => -_tilt,
      },
      depth > _behind ? 0 : 1,
    );
  }

  /// Whether a card [depth] steps behind the front is built: the visible pile, the
  /// card that comes up next (one behind the pile) and the one turning. Built means
  /// loaded — so the next is ready before it shows; the rest of a long group waits
  /// until it is one turn away.
  bool _built(int depth, String id) =>
      depth <= _behind + 1 || id == _turning?.moving;

  /// Every card with where it stands now and how high it lies — the higher, the
  /// later it is painted.
  List<({String id, _Pose pose, double z})> _cards(double width) {
    final turning = _turning;
    final t = Curves.easeInOutCubic.transform(_turn.value);
    final last = _count - 1;
    return [
      for (final (index, id) in widget.imageIds.indexed)
        if (_built((index - _front + _count) % _count, id))
          () {
            final depth = (index - _front + _count) % _count;
            if (turning == null) {
              return (
                id: id,
                pose: _poseAt(depth, width, drag: depth == 0 ? _drag : 0),
                z: -depth.toDouble(),
              );
            }
            if (id == turning.moving) {
              // Off to the side first, on top; then in at the back, below the
              // others.
              final out = _Pose(
                turning.side * width * _flyOut,
                -HiwiskiMetrics.imageStackStep,
                turning.side * _tilt * 3,
                1,
              );
              final from = _poseAt(0, width, drag: turning.fromDrag);
              final firstHalf = t < 0.5;
              return (
                id: id,
                pose: firstHalf
                    ? from.towards(out, t * 2)
                    : out.towards(_poseAt(last, width), t * 2 - 1),
                z: firstHalf ? 1.0 : -_count.toDouble(),
              );
            }
            // The others move one place up.
            final before = depth + 1;
            return (
              id: id,
              pose: _poseAt(
                before,
                width,
                drag: before == 0 ? turning.fromDrag : 0,
              ).towards(_poseAt(depth, width), t),
              z: -depth.toDouble(),
            );
          }(),
    ]..sort((a, b) => a.z.compareTo(b.z));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    if (_count == 0) return const SizedBox.shrink();
    final single = _count == 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          constraints.maxWidth -
              (single ? 0 : _behind * HiwiskiMetrics.imageStackStep),
          HiwiskiMetrics.pageImageMaxWidth,
        );
        final height = width * 3 / 4;
        final front = widget.imageIds[_front];
        // Cards decode at the size they show, not at the photo's: a phone's 4000 px
        // picture in a 440 px card cost memory and every frame of a turn. A third
        // more than the width: filling the card, a wide image needs it.
        _decodeWidth = (width * MediaQuery.devicePixelRatioOf(context) * 4 / 3)
            .round();

        final stack = SizedBox(
          width: width + (single ? 0 : _behind * HiwiskiMetrics.imageStackStep),
          height: height + (single ? 0 : HiwiskiMetrics.imageStackStep),
          child: AnimatedBuilder(
            animation: _turn,
            builder: (context, _) => Stack(
              clipBehavior: .none,
              alignment: Alignment.bottomLeft,
              children: [
                for (final card in _cards(width))
                  _StackCard(
                    key: ValueKey(card.id),
                    imageId: card.id,
                    pose: card.pose,
                    width: width,
                    height: height,
                    shadow: !single,
                    decodeWidth: _decodeWidth,
                    front: card.id == front,
                    onAspect: (aspect) => _aspects[card.id] = aspect,
                    // Only the front card flies into the large view and back.
                    heroTag: card.id == front && _turning == null
                        ? _heroTag(card.id)
                        : null,
                  ),
                Positioned(
                  top:
                      HiwiskiMetrics.space8 +
                      (single ? 0 : HiwiskiMetrics.imageStackStep),
                  left:
                      width -
                      HiwiskiMetrics.iconButtonSize -
                      HiwiskiMetrics.space8,
                  child: IconButton.filledTonal(
                    tooltip: l.wikiImageOpen,
                    icon: const Icon(HiwiskiSymbols.openInFull),
                    onPressed: _showLarge,
                  ),
                ),
                if (!single)
                  Positioned(
                    left: HiwiskiMetrics.space8,
                    bottom: HiwiskiMetrics.space8,
                    child: ImageCounter(text: '${_front + 1}/$_count'),
                  ),
              ],
            ),
          ),
        );

        return Padding(
          padding: const .symmetric(vertical: HiwiskiMetrics.space8),
          // Only as wide as the pictures: set into a line, the line places them
          // ([FlowingText]); on a page they stand at its start either way.
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: single
                ? GestureDetector(onTap: _showLarge, child: stack)
                : MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      key: RichTextKeys.imageStack,
                      onTap: _next,
                      onHorizontalDragStart: (_) => _settle.stop(),
                      onHorizontalDragUpdate: (details) =>
                          setState(() => _drag += details.delta.dx),
                      onHorizontalDragEnd: (details) =>
                          _release(width, details.velocity.pixelsPerSecond.dx),
                      child: Semantics(
                        label: l.wikiImageGroup(_front + 1, _count),
                        child: stack,
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }

  /// Opens the group large, at the front image. Swiping there turns the pile along,
  /// so that closing flies the image shown back to the front card.
  Future<void> _showLarge() => showImageGallery(
    context,
    imageIds: widget.imageIds,
    initial: _front,
    heroTag: _heroTag,
    aspects: _aspects,
    previewWidth: _decodeWidth,
    onShown: (index) {
      if (mounted && index != _front) setState(() => _front = index);
    },
  );
}

/// A card of the pile where [pose] puts it. Keyed by its image: the same card moves,
/// its image stays loaded.
class _StackCard extends StatelessWidget {
  const _StackCard({
    super.key,
    required this.imageId,
    required this.pose,
    required this.width,
    required this.height,
    required this.shadow,
    required this.decodeWidth,
    required this.front,
    required this.onAspect,
    this.heroTag,
  });

  final String imageId;
  final _Pose pose;
  final double width;
  final double height;
  final bool shadow;
  final int decodeWidth;
  final bool front;
  final ValueChanged<double> onAspect;

  /// Set on the front card: it grows into the large view and back.
  final Object? heroTag;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: pose.opacity,
    child: Transform(
      alignment: Alignment.bottomCenter,
      transform: Matrix4.identity()
        ..translateByDouble(pose.dx, pose.dy, 0, 1)
        ..rotateZ(pose.rotation),
      // A layer of its own: a turn moves and turns the painted card — image and
      // shadow are not painted again in every frame.
      child: RepaintBoundary(
        child: switch (heroTag) {
          final tag? => Hero(
            tag: tag,
            child: _StackImage(
              imageId: imageId,
              width: width,
              height: height,
              shadow: shadow,
              decodeWidth: decodeWidth,
              front: front,
              onAspect: onAspect,
            ),
          ),
          null => _StackImage(
            imageId: imageId,
            width: width,
            height: height,
            shadow: shadow,
            decodeWidth: decodeWidth,
            front: front,
            onAspect: onAspect,
          ),
        },
      ),
    ),
  );
}

const _corner = Radius.circular(HiwiskiMetrics.radiusCard);

/// One image of the stack: rounded, filling its card, with a shadow where others lie
/// below it.
///
/// Every card shows the server's preview; only the [front] one lays the original
/// over it, at the card's size — one large photo decoded at a time, not one per
/// card.
///
/// In the browser not even that one: Safari decodes every photo at full size before
/// it is scaled down, and after a round through seven of them the page had used up
/// what Safari grants it — on the next round the images were gone. The preview is
/// what the browser shows in a card.
class _StackImage extends StatelessWidget {
  const _StackImage({
    required this.imageId,
    required this.width,
    required this.height,
    required this.shadow,
    required this.decodeWidth,
    required this.front,
    required this.onAspect,
  });

  final String imageId;
  final double width;
  final double height;
  final bool shadow;
  final int decodeWidth;
  final bool front;
  final ValueChanged<double> onAspect;

  @override
  Widget build(BuildContext context) => Material(
    elevation: shadow ? HiwiskiMetrics.elevationMenu : 0,
    borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
    // The image rounds its own corners (RichImage.radius): a clip on a turned card
    // was cut out in every frame, and the pile stuttered in Safari on the iPhone.
    color: context.scheme.surfaceContainerHigh,
    child: SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: .expand,
        children: [
          RichImage(
            imageId: imageId,
            fit: .cover,
            decodeWidth: decodeWidth,
            onAspect: onAspect,
            preview: true,
            radius: _corner,
          ),
          if (front && !kIsWeb)
            RichImage(
              imageId: imageId,
              fit: .cover,
              decodeWidth: decodeWidth,
              placeholder: false,
              radius: _corner,
            ),
        ],
      ),
    ),
  );
}
