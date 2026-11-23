import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../components/rich_text/view/still_images.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_theme.dart';
import '../../../../domain/wiki/mindmap.dart';
import 'mindmap_members.dart';
import 'mindmap_scene.dart';

/// Draws mind maps as pictures, with what [context] knows — taken at once, so the
/// drawing still works once the sheet or screen that asked for it has closed.
///
/// A picture shows the whole map, as "Show all" does, light as on paper whatever
/// the device shows: it is printed, mailed, put into documents.
MindmapDrawing mindmapDrawingOf(BuildContext context) {
  final view = View.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final locale = Localizations.localeOf(context);
  return (picture) =>
      _draw(picture, view: view, container: container, locale: locale);
}

Future<Uint8List> _draw(
  MindmapPicture picture, {
  required ui.FlutterView view,
  required ProviderContainer container,
  required Locale locale,
}) async {
  final map = picture.map;
  final area = (map.bounds ?? .zero).inflate(
    HiwiskiMetrics.mindmapPictureMargin,
  );
  // Sharp on a screen, but no larger than a device can hold in memory at once: a
  // vast map is drawn smaller.
  final ratio = math.min(
    HiwiskiMetrics.mindmapPictureScale,
    HiwiskiMetrics.mindmapPictureMaxEdge / math.max(area.width, area.height),
  );
  final theme = HiwiskiTheme.light();

  // A tree of its own, off the screen: built, laid out and painted here, never shown.
  final boundary = RenderRepaintBoundary();
  final renderView = RenderView(
    view: view,
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(area.size),
      physicalConstraints: BoxConstraints.tight(area.size * ratio),
      devicePixelRatio: ratio,
    ),
    child: RenderPositionedBox(child: boundary),
  );
  final images = StillImages();
  final pipeline = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  bool changed = false;
  final focus = FocusManager();
  final builder = BuildOwner(
    focusManager: focus,
    onBuildScheduled: () => changed = true,
  );
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        data: MediaQueryData(
          size: area.size,
          devicePixelRatio: ratio,
          textScaler: .noScaling,
        ),
        child: Localizations(
          locale: locale,
          delegates: L.localizationsDelegates,
          child: Theme(
            data: theme,
            child: Material(
              color: theme.colorScheme.surface,
              // What an element shows on hover — a name, a hint — needs an
              // overlay to show in, even where nothing hovers.
              child: Overlay(
                initialEntries: [
                  OverlayEntry(
                    builder: (_) => StillImageScope(
                      images: images,
                      child: MindmapMembers(
                        members: picture.members,
                        child: MindmapScene(
                          map: map,
                          area: area,
                          linkTarget: (target) => picture.targets[target],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  ).attachToRenderTree(builder);

  void frame() {
    builder
      ..buildScope(root)
      ..finalizeTree();
    pipeline
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();
  }

  try {
    frame();
    // What arrives later — a picture from the device's store, a linked page's
    // text — is waited for, until nothing has changed for a moment and no picture
    // is on its way any more. One that has not come when the wait gives up is left
    // out.
    final waited = Stopwatch()..start();
    Duration quiet = .zero;
    while ((quiet < _settled || !images.settled) && waited.elapsed < _longest) {
      await Future<void>.delayed(_tick);
      if (changed) {
        changed = false;
        quiet = .zero;
        frame();
      } else {
        quiet += _tick;
      }
    }
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      final bytes = await image.toByteData(format: .png);
      if (bytes == null) throw StateError('the picture could not be encoded');
      return bytes.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    // Unmounted: what the tree listened to — the family, the pictures — lets go.
    RenderObjectToWidgetAdapter<RenderBox>(container: boundary)
        .attachToRenderTree(builder, root);
    builder
      ..buildScope(root)
      ..finalizeTree();
    pipeline
      ..rootNode = null
      ..dispose();
    focus.dispose();
  }
}

const _tick = Duration(milliseconds: 50);
const _settled = Duration(milliseconds: 400);
const _longest = Duration(seconds: 10);
