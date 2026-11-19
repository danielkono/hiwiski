/// A wiki page as one Markdown file: its text as it is, with what the page is beyond
/// its text in the front matter.
///
/// Inside the app an image is `![](hiwiski-image:<id>)` and a link to another page
/// `[Title](hiwiski://wiki_page/<id>)` — ids only this server knows. An export turns
/// both into relative paths (`../media/<id>.jpg`, `Recipes/Pancakes.md`), which any
/// Markdown editor follows, and an import turns them back into the ids of what it
/// created.
library;

import 'package:path/path.dart' as p;

import '../../core/common/app_names.dart';
import '../../core/common/wire.dart';
import 'front_matter.dart';
import 'transfer_models.dart';

/// [page] as the text of its file.
String pageMarkdown(TransferPage page) {
  final front = writeFrontMatter({
    TransferFields.type: TransferTypes.wikiPage,
    TransferFields.title: page.title,
    TransferFields.kind: page.kind,
    TransferFields.position: page.position,
    if (page.tags.isNotEmpty) TransferFields.tags: page.tags,
    if (page.properties.isNotEmpty) TransferFields.properties: page.properties,
  });
  final content = page.content.trim();
  return content.isEmpty ? front : '$front\n$content\n';
}

/// A page read from the file at [path]. A file without front matter is a page named
/// after its file, its whole text the content.
TransferPage parsePage(String markdown, {required String path}) {
  final (:fields, :body) = splitFrontMatter(markdown);
  final title = fields[TransferFields.title];
  final kind = fields[TransferFields.kind];
  final properties = fields[TransferFields.properties];
  final position = fields[TransferFields.position];
  return TransferPage(
    path: path,
    title: title is String && title.trim().isNotEmpty
        ? title.trim()
        : p.posix.basenameWithoutExtension(path),
    kind: kind is String && kind.trim().isNotEmpty
        ? kind.trim()
        : PageKinds.page,
    content: body.trim(),
    tags: stringList(fields[TransferFields.tags]),
    properties: properties is Map<String, Object?> ? properties : const {},
    position: position is int ? position : 0,
  );
}

/// The ids of the images in [content], in order, each once. Images inside a code
/// block are text and not counted.
List<String> imageIdsIn(String content) {
  final ids = <String>{};
  _eachLine(content, (line) {
    for (final match in _image.allMatches(line)) {
      if (_imageId(match.group(_targetGroup) ?? _none) case final id?) {
        ids.add(id);
      }
    }
    return line;
  });
  return [...ids];
}

/// [content] for the file at [path]: every image the export holds
/// ([imagePath] answers with its path there) and every link to a page that is exported
/// too ([pagePath]) as a path relative to this file.
///
/// An image the export does not hold is taken out: outside the app its address leads
/// nowhere. A line that held nothing else goes with it. Links to anything else stay as
/// they are — on the server they came from, they still work.
String exportContent(
  String content, {
  required String path,
  required String? Function(String imageId) imagePath,
  required String? Function(String pageId) pagePath,
}) => _eachLine(content, (line) {
  bool dropped = false;
  final withImages = line.replaceAllMapped(_image, (match) {
    final id = _imageId(match.group(_targetGroup) ?? _none);
    if (id == null) return match.group(0) ?? _none;
    final target = imagePath(id);
    if (target == null) {
      dropped = true;
      return '';
    }
    return '![${match.group(_labelGroup)}](${_relative(target, from: path)})';
  });
  if (dropped && withImages.trim().isEmpty) return null;
  return withImages.replaceAllMapped(_link, (match) {
    final target = switch (_pageId(match.group(_targetGroup) ?? _none)) {
      final id? => pagePath(id),
      null => null,
    };
    return target == null
        ? match.group(0) ?? _none
        : '[${match.group(_labelGroup)}](${_relative(target, from: path)})';
  });
});

/// The other direction, for the page read from the file at [path]: a relative path
/// to an image the import took ([imageId] answers with its new id) or to a page it
/// created ([pageId]) becomes the app's own address. Everything else stays.
String importContent(
  String content, {
  required String path,
  required String? Function(String imagePath) imageId,
  required String? Function(String pagePath) pageId,
}) => _eachLine(content, (line) {
  final withImages = line.replaceAllMapped(_image, (match) {
    final id = switch (resolvePath(
      (match.group(_targetGroup) ?? _none),
      from: path,
    )) {
      final target? => imageId(target),
      null => null,
    };
    return id == null
        ? match.group(0) ?? _none
        : '![${match.group(_labelGroup)}](${UriSchemes.hiwiskiImage}:$id)';
  });
  return withImages.replaceAllMapped(_link, (match) {
    final id = switch (resolvePath(
      (match.group(_targetGroup) ?? _none),
      from: path,
    )) {
      final target? => pageId(target),
      null => null,
    };
    return id == null
        ? match.group(0) ?? _none
        : '[${match.group(_labelGroup)}]($_pageAddress$id)';
  });
});

/// The relative paths [content] points to as images, resolved from the file at
/// [path] — what an import looks for among the files it was given.
List<String> imagePathsIn(String content, {required String path}) {
  final paths = <String>{};
  _eachLine(content, (line) {
    for (final match in _image.allMatches(line)) {
      if (resolvePath((match.group(_targetGroup) ?? _none), from: path)
          case final target?) {
        paths.add(target);
      }
    }
    return line;
  });
  return [...paths];
}

/// A link's [target] as a path inside the export, seen from the file at [from] —
/// `null` for an address (anything with a scheme), an anchor, or a path that leaves
/// the export.
String? resolvePath(String target, {required String from}) {
  if (target.isEmpty ||
      target.startsWith(_anchor) ||
      _scheme.hasMatch(target)) {
    return null;
  }
  final String decoded;
  try {
    decoded = Uri.decodeComponent(target);
  } on ArgumentError {
    return null;
  }
  final resolved = p.posix.normalize(
    p.posix.join(p.posix.dirname(from), decoded),
  );
  return resolved.startsWith(_parent) || p.posix.isAbsolute(resolved)
      ? null
      : resolved;
}

/// [target] as a link from the file at [from], each segment encoded: a space or a
/// bracket in a title would end the link early.
String _relative(String target, {required String from}) => p.posix
    .split(p.posix.relative(target, from: p.posix.dirname(from)))
    .map((segment) => segment == _parent ? segment : _encoded(segment))
    .join(p.posix.separator);

/// A path segment as part of a link. Brackets are encoded on top of what a URI
/// needs: Markdown ends a link at the first closing one.
String _encoded(String segment) =>
    Uri.encodeComponent(segment)
        .replaceAll(_open, _openEncoded)
        .replaceAll(_close, _closeEncoded);

String? _imageId(String target) =>
    target.startsWith(_imageAddress) && target.length > _imageAddress.length
    ? target.substring(_imageAddress.length)
    : null;

String? _pageId(String target) =>
    target.toLowerCase().startsWith(_pageAddress) &&
        target.length > _pageAddress.length
    ? target.substring(_pageAddress.length)
    : null;

/// [content] line by line through [change], which returns the new line or `null` to
/// drop it. Fenced code passes through untouched: what looks like an image there is
/// an example of one.
String _eachLine(String content, String? Function(String line) change) {
  final lines = <String>[];
  bool fenced = false;
  for (final line in content.split('\n')) {
    if (_fence.hasMatch(line)) {
      fenced = !fenced;
      lines.add(line);
    } else if (fenced) {
      lines.add(line);
    } else if (change(line) case final changed?) {
      lines.add(changed);
    }
  }
  return lines.join('\n');
}

const _imageAddress = '${UriSchemes.hiwiskiImage}:';
final _pageAddress =
    '${UriSchemes.hiwiski}://${EntityTypes.wikiPage.toLowerCase()}/';
const _anchor = '#';
const _open = '(';
const _openEncoded = '%28';
const _close = ')';
const _closeEncoded = '%29';
const _parent = '..';

const _labelGroup = 1;
const _targetGroup = 2;

/// `![label](target)`.
final _image = RegExp(r'!\[([^\]]*)\]\(([^)\s]+)\)');

/// `[label](target)` that is not an image; the label may hold escaped brackets.
final _link = RegExp(r'(?<!!)\[((?:\\.|[^\]\\])*)\]\(([^)\s]+)\)');
final _scheme = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:');
final _fence = RegExp(r'^\s*(```|~~~)');

/// A group that did not take part in a match.
const _none = '';
