import '../../core/common/app_names.dart';

/// Images in a page's text.
///
/// An image is Markdown — `![](hiwiski-image:<id>)` — on a line of its own; images on
/// consecutive lines are **one group** and show as a stack that is swiped or clicked
/// through. The text stays the source: no second place where images are listed, and
/// a page's history shows when one came or went.

/// A part of a page's text: Markdown, or a group of images.
sealed class PageSegment {
  const PageSegment();
}

final class TextSegment extends PageSegment {
  const TextSegment(this.markdown);

  final String markdown;

  @override
  bool operator ==(Object other) =>
      other is TextSegment && other.markdown == markdown;

  @override
  int get hashCode => markdown.hashCode;

  @override
  String toString() => 'TextSegment($markdown)';
}

final class ImageGroup extends PageSegment {
  const ImageGroup(this.imageIds);

  final List<String> imageIds;

  @override
  bool operator ==(Object other) =>
      other is ImageGroup &&
      other.imageIds.length == imageIds.length &&
      [
        for (int i = 0; i < imageIds.length; i++)
          other.imageIds[i] == imageIds[i],
      ].every((same) => same);

  @override
  int get hashCode => Object.hashAll(imageIds);

  @override
  String toString() => 'ImageGroup($imageIds)';
}

final _image = RegExp(
  '!\\[[^\\]]*\\]\\(${UriSchemes.hiwiskiImage}:([0-9A-Za-z-]+)\\)',
);
final _imageLine = RegExp(
  '^\\s*(?:!\\[[^\\]]*\\]\\(${UriSchemes.hiwiskiImage}:[0-9A-Za-z-]+\\)\\s*)+\$',
);
final _fence = RegExp(r'^\s*(```|~~~)');

/// One image as Markdown.
String imageMarkdown(String id) => '![](${UriSchemes.hiwiskiImage}:$id)';

/// [markdown] cut into text and image groups, in order. Image lines inside a code
/// block stay text.
List<PageSegment> pageSegments(String markdown) {
  final segments = <PageSegment>[];
  final text = <String>[];
  final images = <String>[];
  bool inFence = false;

  void flushText() {
    if (text.isEmpty) return;
    final joined = text.join('\n');
    if (joined.trim().isNotEmpty) segments.add(TextSegment(joined));
    text.clear();
  }

  void flushImages() {
    if (images.isEmpty) return;
    segments.add(ImageGroup([...images]));
    images.clear();
  }

  for (final line in markdown.split('\n')) {
    if (_fence.hasMatch(line)) inFence = !inFence;
    if (!inFence && _imageLine.hasMatch(line)) {
      flushText();
      images.addAll([
        for (final match in _image.allMatches(line)) ?match.group(1),
      ]);
      continue;
    }
    flushImages();
    text.add(line);
  }
  flushImages();
  flushText();
  return segments;
}

/// What to insert at [at] in [text] for [ids]: the images on lines of their own —
/// one group — with line breaks around them only where the text needs them.
String imagesInsertion(String text, int at, List<String> ids) {
  final before = at <= 0 || text[at - 1] == '\n' ? '' : '\n';
  final after = at >= text.length || text[at] == '\n' ? '' : '\n';
  return '$before${ids.map(imageMarkdown).join('\n')}$after';
}
