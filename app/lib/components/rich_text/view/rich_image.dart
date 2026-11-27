import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/bounded_image.dart';
import '../rich_text_view_model.dart';
import 'still_images.dart';

/// An image of the media store as it arrives — from the device's cache or the server —
/// filling its space as [fit] says.
///
/// Decoded at [decodeWidth] where given: the same image at the same width is decoded
/// once and then taken from Flutter's image cache — which is what lets the large view
/// fly out of a card without a frame of nothing while it decodes.
class RichImage extends ConsumerWidget {
  const RichImage({
    super.key,
    required this.imageId,
    this.fit = .contain,
    this.decodeWidth,
    this.onAspect,
    this.placeholder = true,
    this.preview = false,
    this.radius,
  });

  final String imageId;
  final BoxFit fit;

  /// The server's preview (longest edge 640) instead of the original — for what is
  /// shown small or behind something. A phone's photo is up to 24 megapixels, and
  /// a few of them decoded at once took the browser's memory: on the iPhone a page
  /// with seven of them showed some, or none.
  final bool preview;

  /// Rounded corners, painted with the image rather than cut out of it. A card that
  /// clipped its image was cut out anew in every frame once it was turned: Safari on
  /// the iPhone took about 100 ms to draw a frame with the pile, 8 ms without the
  /// clip.
  final Radius? radius;

  /// The width to decode to, in pixels; `null` decodes the whole image, up to
  /// [maxDecodeEdge] on either side.
  final int? decodeWidth;

  /// Width over height, once the image is decoded — where the large view has to know
  /// the shape of what it shows.
  final ValueChanged<double>? onAspect;

  /// Whether loading and failing show — not for a layer that lies over another
  /// version of the same image.
  final bool placeholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _RichImageBody(image: this);
}

/// The image, and once the original turns out too large to decode here, the
/// server's preview in its place.
class _RichImageBody extends ConsumerStatefulWidget {
  const _RichImageBody({required this.image});

  final RichImage image;

  @override
  ConsumerState<_RichImageBody> createState() => _RichImageBodyState();
}

class _RichImageBodyState extends ConsumerState<_RichImageBody> {
  /// The original was refused by [checkDecodable]: the preview stands in.
  bool _tooLarge = false;

  /// The drawing this image is part of, if it is drawn into a file.
  StillImages? _still;

  @override
  void didUpdateWidget(_RichImageBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.imageId != widget.image.imageId) _tooLarge = false;
  }

  @override
  void dispose() {
    _still?.mark(this, waiting: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    final preview = image.preview || _tooLarge;
    final fetched = ref.watch(
      richImageViewModelProvider(image.imageId, preview),
    );
    // Once fetched — or failed — it no longer holds a drawing up; while it is
    // decoded, [_Decoded] does.
    _still = StillImageScope.of(context)
      ?..mark(this, waiting: !fetched.hasValue && !fetched.hasError);
    return fetched.when(
      skipLoadingOnReload: true,
      // Drawn into a file, a spinner would stay there as it stands.
      loading: () => image.placeholder && _still == null
          ? const Center(child: CircularProgressIndicator())
          : const SizedBox.shrink(),
      error: (_, _) => _failed(context),
      data: (bytes) => _Decoded(
        bytes: bytes,
        fit: image.fit,
        decodeWidth: image.decodeWidth,
        onAspect: image.onAspect,
        radius: image.radius,
        // Already the preview: then it is an image that failed.
        onTooLarge: preview ? null : () => setState(() => _tooLarge = true),
        failed: _failed(context),
      ),
    );
  }

  Widget _failed(BuildContext context) => widget.image.placeholder
      ? Center(
          child: Icon(
            HiwiskiSymbols.errorOutline,
            color: context.scheme.onSurfaceVariant,
          ),
        )
      : const SizedBox.shrink();
}

/// The bytes decoded and painted — resolved by hand rather than through `Image`, so
/// that the decoded size is known: it says the image's shape.
class _Decoded extends StatefulWidget {
  const _Decoded({
    required this.bytes,
    required this.fit,
    required this.decodeWidth,
    required this.onAspect,
    required this.radius,
    required this.onTooLarge,
    required this.failed,
  });

  final Uint8List bytes;
  final BoxFit fit;
  final int? decodeWidth;
  final ValueChanged<double>? onAspect;
  final Radius? radius;

  /// The bytes are too large to decode here ([ImageTooLargeError]); `null` shows
  /// [failed] instead.
  final VoidCallback? onTooLarge;

  /// What stands where an image could not be decoded.
  final Widget failed;

  @override
  State<_Decoded> createState() => _DecodedState();
}

class _DecodedState extends State<_Decoded> {
  ImageStream? _stream;
  ImageInfo? _info;
  bool _failed = false;

  /// The drawing this image is part of, if it is drawn into a file.
  StillImages? _still;
  late final _listener = ImageStreamListener(_loaded, onError: _error);

  void _error(Object error, StackTrace? _) {
    if (!mounted) return;
    // In the browser no header is read before decoding ([checkDecodable]): an
    // original too large for it fails in the decoder itself — the preview stands in
    // there for any original that could not be decoded.
    if ((error is ImageTooLargeError || kIsWeb) && widget.onTooLarge != null) {
      widget.onTooLarge?.call();
      return;
    }
    setState(() => _failed = true);
  }

  /// Never whatever size the file declares: "the whole image" is at most
  /// [maxDecodeEdge] on a side.
  ImageProvider get _provider =>
      boundedImage(widget.bytes, width: widget.decodeWidth);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_Decoded oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes) ||
        oldWidget.decodeWidth != widget.decodeWidth) {
      _resolve();
    }
  }

  void _resolve() {
    final next = _provider.resolve(createLocalImageConfiguration(context));
    if (next.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _failed = false;
    _stream = next..addListener(_listener);
  }

  /// Comes at once for an image in the cache — then during a build, where neither
  /// this state nor the one that wants the shape may be rebuilt yet.
  void _loaded(ImageInfo info, bool _) {
    final aspect = info.image.width / info.image.height;
    final building =
        SchedulerBinding.instance.schedulerPhase == .persistentCallbacks;
    if (building) {
      _info?.dispose();
      _info = info;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onAspect?.call(aspect);
      });
      return;
    }
    if (!mounted) {
      info.dispose();
      return;
    }
    final before = _info;
    setState(() => _info = info);
    before?.dispose();
    widget.onAspect?.call(aspect);
  }

  @override
  void dispose() {
    _still?.mark(this, waiting: false);
    _stream?.removeListener(_listener);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Decoded or failed, it no longer holds a drawing up.
    _still = StillImageScope.of(context)
      ?..mark(this, waiting: _info == null && !_failed);
    return SizedBox.expand(
      child: switch ((_info?.image, widget.radius)) {
        (null, _) when _failed => widget.failed,
        (final image?, final radius?) => CustomPaint(
          painter: _RoundedImage(image: image, fit: widget.fit, radius: radius),
        ),
        (final image, _) => RawImage(image: image, fit: widget.fit),
      },
    );
  }
}

/// The image filling a rounded rectangle — drawn as a shape with the image as its
/// paint, so nothing is clipped.
class _RoundedImage extends CustomPainter {
  _RoundedImage({required this.image, required this.fit, required this.radius});

  final ui.Image image;
  final BoxFit fit;
  final Radius radius;

  @override
  void paint(Canvas canvas, Size size) {
    final source = Size(image.width.toDouble(), image.height.toDouble());
    final sizes = applyBoxFit(fit, source, size);
    final from = Alignment.center.inscribe(sizes.source, Offset.zero & source);
    final to = Alignment.center.inscribe(sizes.destination, Offset.zero & size);
    final scale = to.width / from.width;
    final matrix = Matrix4.identity()
      ..translateByDouble(
        to.left - from.left * scale,
        to.top - from.top * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, to.height / from.height, 1, 1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(to.intersect(Offset.zero & size), radius),
      Paint()
        ..isAntiAlias = true
        ..shader = ImageShader(
          image,
          .clamp,
          .clamp,
          matrix.storage,
          filterQuality: .medium,
        ),
    );
  }

  @override
  bool shouldRepaint(_RoundedImage old) =>
      old.image != image || old.fit != fit || old.radius != radius;
}
