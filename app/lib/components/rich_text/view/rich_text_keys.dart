import 'package:flutter/widgets.dart';

/// The keys the tests find the rich text's widgets by.
abstract final class RichTextKeys {
  static const imageGallery = ValueKey('image-gallery');
  static const imageGalleryClose = ValueKey('image-gallery-close');
  static const imageStack = ValueKey('image-stack');
  static const insertImages = ValueKey('insert-images');
  static const imagesBusy = ValueKey('images-busy');
  static const showFormatted = ValueKey('show-formatted');
  static const showMarkdown = ValueKey('show-markdown');
}
