import 'package:flutter/widgets.dart';

import 'rich_image.dart';

/// The images of a tree drawn once into a file rather than shown — a pinboard saved
/// as a picture —, given to it with [StillImageScope]: whether any of them is still
/// on its way, fetched or decoded.
///
/// The drawing waits until they have [settled]. It used to go on once nothing had
/// changed for a moment, and only a spinner turning kept it waiting for an image —
/// which, still turning when the drawing gave up, was drawn into the file.
class StillImages {
  final _waiting = <State>{};

  /// Whether every image has come, or failed.
  bool get settled => _waiting.isEmpty;

  /// Called by an image as it builds and goes: whether it is [waiting] still.
  void mark(State image, {required bool waiting}) {
    if (waiting) {
      _waiting.add(image);
    } else {
      _waiting.remove(image);
    }
  }
}

/// Above a tree drawn into a file: each [RichImage] below tells [images] while it is
/// on its way, and shows nothing meanwhile.
class StillImageScope extends InheritedWidget {
  const StillImageScope({
    super.key,
    required this.images,
    required super.child,
  });

  final StillImages images;

  /// The drawing the images below are part of — `null` on a screen.
  static StillImages? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StillImageScope>()?.images;

  @override
  bool updateShouldNotify(StillImageScope oldWidget) =>
      !identical(oldWidget.images, images);
}
