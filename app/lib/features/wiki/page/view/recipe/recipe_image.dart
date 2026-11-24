import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/api/hiwiski_failure.dart';
import '../../../../../core/l10n/generated/app_localizations.dart';
import '../../../../../core/theme/hiwiski_metrics.dart';
import '../../../../../core/theme/hiwiski_symbols.dart';
import '../../../../../core/theme/hiwiski_tokens.dart';
import '../../../../../core/ui/bounded_image.dart';
import '../../../../../core/ui/failure_text.dart';
import '../../../../../components/rich_text/view/image_files.dart';
import '../../../../../domain/wiki/wiki_page.dart';
import '../../page_view_model.dart';

/// The recipe image from the media store. As long as there is none — or while it
/// loads — the hatched area from the design: a gap of the same size, so the layout does
/// not jump when the image arrives.
///
/// With [editable], "Choose image" or "Change image" sits on it at the bottom right.
class RecipeImage extends ConsumerStatefulWidget {
  const RecipeImage({
    super.key,
    required this.page,
    required this.height,
    this.radius = HiwiskiMetrics.radiusWidget,
    this.preview = false,
    this.editable = false,
  });

  final WikiPage page;
  final double height;
  final double radius;

  /// The small version (longest edge 640) — for cards in the grid.
  final bool preview;
  final bool editable;

  @override
  ConsumerState<RecipeImage> createState() => _RecipeImageState();
}

class _RecipeImageState extends ConsumerState<RecipeImage> {
  bool _uploading = false;

  Future<void> _pick() async {
    final l = L.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final file = (await pickImageFiles(single: true)).firstOrNull;
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      // Upload first, then set it via sync: the upload changes no item, and the
      // `imageId` travels like any other field — offline it waits in the outbox.
      await ref
          .read(pageViewModelProvider(widget.page.id).notifier)
          .uploadImage(widget.page, bytes: file.bytes, filename: file.filename);
    } on HiwiskiFailure catch (failure) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failure.status == 404
                ? l.recipeImageNotYetSynced
                : failureText(context, failure),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final imageId = widget.page.imageId;
    final bytes = imageId == null
        ? null
        : ref.watch(pageImageViewModelProvider(imageId, widget.preview)).value;
    final scheme = context.scheme;

    final placeholder = CustomPaint(
      painter: _Hatch(
        base: scheme.surfaceContainerHigh,
        line: scheme.surfaceContainer,
      ),
      child: Center(
        child: Icon(
          HiwiskiSymbols.restaurant,
          size: HiwiskiMetrics.icon48,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: .all(.circular(widget.radius)),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          fit: .expand,
          children: [
            if (bytes == null)
              placeholder
            else
              Image(
                // At most as wide as the screen: the header never shows more, and
                // a file may declare any size.
                image: boundedImage(
                  bytes,
                  width:
                      (MediaQuery.sizeOf(context).width *
                              MediaQuery.devicePixelRatioOf(context))
                          .ceil(),
                ),
                fit: .cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stack) => placeholder,
              ),
            if (widget.editable)
              Positioned(
                right: HiwiskiMetrics.space8,
                bottom: HiwiskiMetrics.space8,
                child: _uploading
                    ? const SizedBox.square(
                        dimension: HiwiskiMetrics.icon24,
                        child: CircularProgressIndicator(
                          strokeWidth: HiwiskiMetrics.strokeBold,
                        ),
                      )
                    : FilledButton.tonalIcon(
                        icon: const Icon(
                          HiwiskiSymbols.addPhotoAlternate,
                          size: HiwiskiMetrics.icon18,
                        ),
                        label: Text(
                          imageId == null
                              ? l.recipeImagePick
                              : l.recipeImageChange,
                        ),
                        onPressed: _pick,
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Hatch extends CustomPainter {
  _Hatch({required this.base, required this.line});

  final Color base;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (double x = -size.height; x < size.width; x += 11) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Hatch old) => old.base != base || old.line != line;
}
