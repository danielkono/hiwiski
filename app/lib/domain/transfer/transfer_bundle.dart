/// An export as files — and files as an import.
///
/// One list is one Markdown file. A page is one too; with subpages or images it is a
/// zip archive laid out like a folder of notes:
///
/// ```
/// Recipes.md
/// Recipes/Pancakes.md        a subpage: in the folder named after its parent
/// media/<id>.jpg             every image, once
/// ```
///
/// An import reads the same layout back, and is forgiving about what else it is
/// given: a folder of notes zipped by hand has no front matter, and a folder without
/// a page of its own still has to hold its pages somewhere.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../core/common/wire.dart';
import '../tags/tag.dart';
import '../todo/kanban.dart';
import '../todo/todo_items.dart';
import '../wiki/wiki_page.dart';
import 'front_matter.dart';
import 'list_markdown.dart';
import 'page_markdown.dart';
import 'transfer_models.dart';

/// What an export hands to the person: one file to save.
class const ExportedFile(final String name, final Uint8List bytes);

// --- Export -----------------------------------------------------------------------

/// [list] with its [todos] as its file. [tagNames] are the tags the reader knows, by
/// id; a tag they cannot see is left out, as it is on screen.
TransferFile listExportFile({
  required TodoList list,
  required List<Todo> todos,
  required Map<String, String> tagNames,
}) {
  final columns = list.kind == ListKinds.kanban
      ? parseColumns(list.columns)
      : const <KanbanColumn>[];
  TransferTask task(Todo todo, {int? column}) => .new(
    title: todo.title,
    done: todo.status == TodoStatuses.done,
    description: todo.description,
    dueDate: todo.dueDate,
    dueTime: todo.dueTime,
    rrule: todo.rrule,
    amount: todo.amount,
    unit: todo.unit,
    tags: _tagNames(todo.tags, tagNames),
    column: column,
  );

  // A board's cards stand where the board shows them: the column is derived from
  // column and status together.
  final cards = arrangeCards(todos, columns);
  final markdown = listMarkdown(
    TransferList(
      name: list.name,
      kind: list.kind,
      description: list.description,
      colorToken: list.colorToken,
      tags: _tagNames(list.tags, tagNames),
      columns: [
        for (final column in columns)
          TransferColumn(
            name: column.name,
            colorToken: column.colorToken,
            done: column.done,
          ),
      ],
      tasks: columns.isEmpty
          ? [for (final todo in todos) task(todo)]
          : [
              for (final (index, column) in columns.indexed)
                for (final todo in cards[column.id] ?? const <Todo>[])
                  task(todo, column: index),
            ],
    ),
  );
  return TransferFile(
    '${fileName(list.name)}$markdownExtension',
    utf8.encode(markdown),
  );
}

/// [root] and, with [withSubpages], every page below it, parents before their
/// children and siblings in their order. Archived pages below are left where they
/// are: the archive is not part of the branch any more.
List<WikiPage> exportBranch(
  WikiPage root,
  List<WikiPage> pages, {
  required bool withSubpages,
}) {
  if (!withSubpages) return [root];
  final byParent = <String, List<WikiPage>>{};
  for (final page in pages) {
    if (page.parentId case final parentId? when page.archivedAt == null) {
      byParent.putIfAbsent(parentId, () => []).add(page);
    }
  }
  final branch = <WikiPage>[];
  // Two devices moving pages into each other offline can leave a cycle.
  final seen = <String>{};
  void take(WikiPage page) {
    if (!seen.add(page.id)) return;
    branch.add(page);
    [...?byParent[page.id]]
      ..sort(_byPosition)
      ..forEach(take);
  }

  take(root);
  return branch;
}

/// The images the pages of [branch] show: those in their text and a recipe's
/// picture.
Set<String> branchImageIds(List<WikiPage> branch) => {
  for (final page in branch) ...[
    ...imageIdsIn(page.content),
    if (page.property(WireFields.imageId) case final String id) id,
  ],
};

/// The files of [branch] (as [exportBranch] returns it): one per page, and one per
/// image in [images] that a page shows.
///
/// A pinboard's picture in [pinboards] (by the page's id) is an image like any other,
/// at the top of its page: outside the app the map is seen, and an import makes an
/// ordinary page of it, with the picture.
List<TransferFile> pageExportFiles({
  required List<WikiPage> branch,
  required Map<String, String> tagNames,
  required Map<String, Uint8List> images,
  Map<String, Uint8List> pinboards = const {},
}) {
  images = {...images, ...pinboards};
  final inBranch = {for (final page in branch) page.id};
  final paths = <String, String>{};
  final taken = <String>{};
  for (final page in branch) {
    // The root lies at the top; every other page in the folder of its parent.
    final folder = switch (paths[page.parentId]) {
      final parent? when inBranch.contains(page.parentId) =>
        p.posix.withoutExtension(parent),
      _ => '',
    };
    final base = p.posix.join(folder, fileName(page.title));
    String path = '$base$markdownExtension';
    for (int count = 2; !taken.add(path.toLowerCase()); count++) {
      path = '$base ($count)$markdownExtension';
    }
    paths[page.id] = path;
  }

  final imagePaths = {
    for (final MapEntry(:key, :value) in images.entries)
      key: p.posix.join(mediaFolder, '$key.${_imageExtension(value)}'),
  };
  final used = <String>{};
  String? imagePath(String id) {
    final path = imagePaths[id];
    if (path != null) used.add(id);
    return path;
  }

  final files = <TransferFile>[];
  for (final page in branch) {
    final path = paths[page.id] ?? '';
    final properties = {...decodeProperties(page.properties)};
    // A recipe's picture is an image like those in the text: a path, or gone.
    if (properties.remove(WireFields.imageId) case final String id) {
      if (imagePath(id) case final target?) {
        properties[WireFields.imageId] = p.posix.relative(
          target,
          from: p.posix.dirname(path),
        );
      }
    }
    final markdown = pageMarkdown(
      TransferPage(
        path: path,
        title: page.title,
        kind: page.kind,
        position: page.position,
        tags: _tagNames(page.tags, tagNames),
        properties: properties,
        content: exportContent(
          pinboards.containsKey(page.id)
              ? '${imageMarkdown(page.title, page.id)}\n\n${page.content}'
              : page.content,
          path: path,
          imagePath: imagePath,
          pagePath: (id) => paths[id],
        ),
      ),
    );
    files.add(TransferFile(path, utf8.encode(markdown)));
  }
  for (final id in used) {
    if ((imagePaths[id], images[id]) case (final path?, final bytes?)) {
      files.add(TransferFile(path, bytes));
    }
  }
  return files;
}

/// [files] as the one file to save: a single Markdown file as it is, anything more as
/// a zip archive called [name].
ExportedFile packExport(List<TransferFile> files, {required String name}) {
  if (files case [final only]) {
    return ExportedFile(p.posix.basename(only.path), only.bytes);
  }
  final archive = Archive();
  for (final file in files) {
    archive.addFile(ArchiveFile.bytes(file.path, file.bytes));
  }
  return ExportedFile(
    '${fileName(name)}$archiveExtension',
    ZipEncoder().encodeBytes(archive),
  );
}

/// [title] as a file name every system takes: nothing a path or a shell reads as
/// more than a letter, not hidden, not endless.
String fileName(String title) {
  final cleaned = title
      .replaceAll(_unsafeInNames, '-')
      .replaceAll(_spaces, ' ')
      .trim()
      .replaceFirst(_leadingDots, '');
  final short = cleaned.length > _maxNameLength
      ? cleaned.substring(0, _maxNameLength).trim()
      : cleaned;
  return short.isEmpty ? _untitled : short;
}

// --- Import -----------------------------------------------------------------------

/// The extensions an import can be picked with.
const importExtensions = ['md', 'markdown', 'zip'];

/// Reads what the person picked — Markdown files, zip archives, or both — into what
/// it would create. Nothing is refused as a whole: a file that cannot be read is
/// listed in [ImportPlan.skipped], and the rest goes on.
ImportPlan readImport(List<TransferFile> picked, {required ImportPlace place}) {
  final skipped = <SkippedFile>[];
  // Files picked side by side are one folder; every archive is one of its own, so a
  // relative path never reaches from one into another.
  final bundles = <List<TransferFile>>[];
  final loose = <TransferFile>[];
  for (final file in picked) {
    final extension = _extension(file.path);
    if (extension == _zip) {
      switch (_unzip(file.bytes)) {
        case final files?:
          bundles.add(files);
        case null:
          skipped.add(SkippedFile(file.path, .brokenArchive));
      }
    } else if (_markdownExtensions.contains(extension) ||
        _imageExtensions.contains(extension)) {
      loose.add(TransferFile(p.posix.basename(file.path), file.bytes));
    } else {
      skipped.add(SkippedFile(file.path, .unsupported));
    }
  }
  if (loose.isNotEmpty) bundles.insert(0, loose);

  final lists = <TransferList>[];
  final pages = <TransferPage>[];
  final images = <String, Uint8List>{};
  for (final (index, files) in bundles.indexed) {
    final plan = _readBundle(files, prefix: '$index', place: place);
    lists.addAll(plan.lists);
    pages.addAll(plan.pages);
    images.addAll(plan.images);
    skipped.addAll(plan.skipped);
  }
  return ImportPlan(
    lists: lists,
    pages: pages,
    images: images,
    skipped: skipped,
  );
}

/// The files of one archive, or `null` if it is none. Folders, hidden files and what
/// macOS adds to an archive are left out; a path that climbs out of the archive is
/// not followed.
List<TransferFile>? _unzip(Uint8List bytes) {
  // The decoder reads anything without complaint and finds no files in it: only the
  // signature tells an empty archive from a file that is none.
  final signed =
      bytes.length >= _zipMagic.length &&
      [for (final (index, byte) in _zipMagic.indexed) bytes[index] == byte]
          .every((same) => same);
  if (!signed) return null;
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    // Bigger unpacked than the notes of any family, it is not one of ours. The
    // sizes are known before anything is unpacked.
    final total = archive.files.fold(0, (sum, file) => sum + file.size);
    if (total > _maxArchiveBytes) return null;
    return [
      for (final file in archive.files)
        if (file.isFile && !file.isSymbolicLink)
          if (_cleanPath(file.name) case final path?)
            TransferFile(path, file.content),
    ];
  } on Object {
    // Whatever the decoder trips over: to the person it is a file that is no archive.
    return null;
  }
}

String? _cleanPath(String name) {
  final path = p.posix.normalize(
    name.replaceAll(_backslash, p.posix.separator),
  );
  final segments = p.posix.split(path);
  final hidden = segments.any(
    (segment) => segment.startsWith(_dot) || segment == _macResources,
  );
  return hidden || p.posix.isAbsolute(path) ? null : path;
}

ImportPlan _readBundle(
  List<TransferFile> files, {
  required String prefix,
  required ImportPlace place,
}) {
  String keyed(String path) => p.posix.join(prefix, path);

  final lists = <TransferList>[];
  final skipped = <SkippedFile>[];
  final pagesByPath = <String, TransferPage>{};
  final imageFiles = <String, Uint8List>{};
  for (final file in files) {
    final extension = _extension(file.path);
    if (_imageExtensions.contains(extension)) {
      imageFiles[keyed(file.path)] = file.bytes;
      continue;
    }
    if (!_markdownExtensions.contains(extension)) continue;
    final String text;
    try {
      text = utf8.decode(file.bytes);
    } on FormatException {
      skipped.add(SkippedFile(file.path, .notText));
      continue;
    }
    if (text.length > _maxTextLength) {
      skipped.add(SkippedFile(file.path, .tooLong));
      continue;
    }
    final name = p.posix.basenameWithoutExtension(file.path);
    final isList = switch (splitFrontMatter(text).fields[TransferFields.type]) {
      TransferTypes.todoList => true,
      TransferTypes.wikiPage => false,
      // A file that does not say what it is becomes what the place it was brought
      // to holds.
      _ => place == .todo,
    };
    if (!isList) {
      pagesByPath[file.path] = parsePage(text, path: file.path);
    } else if (hasTasks(text)) {
      lists.add(parseList(text, fallbackName: name));
    } else {
      skipped.add(SkippedFile(file.path, .noTasks));
    }
  }

  // The folder a page's subpages lie in is named after the page's file. A folder
  // without such a file gets an empty page of its name: its pages keep their place
  // below one another instead of all landing at the root.
  final folders = <String>{
    for (final path in pagesByPath.keys)
      for (
        String folder = p.posix.dirname(path);
        folder != _here;
        folder = p.posix.dirname(folder)
      )
        folder,
  };
  final pageOfFolder = <String, String>{
    for (final path in pagesByPath.keys) p.posix.withoutExtension(path): path,
  };
  for (final folder in folders) {
    if (pageOfFolder.containsKey(folder)) continue;
    pageOfFolder[folder] = folder;
    pagesByPath[folder] = TransferPage(
      path: folder,
      title: p.posix.basename(folder),
      kind: PageKinds.page,
      content: '',
    );
  }

  final childrenOf = <String, List<String>>{};
  for (final path in pagesByPath.keys) {
    final folder = p.posix.dirname(path);
    final parent = folder == _here ? _here : pageOfFolder[folder] ?? _here;
    childrenOf.putIfAbsent(parent, () => []).add(path);
  }

  final images = <String, Uint8List>{};
  TransferPage build(String path) {
    final page = pagesByPath[path];
    if (page == null) throw StateError('no page at $path');
    final key = keyed(path);
    final wanted = [
      ...imagePathsIn(page.content, path: key),
      if (page.properties[WireFields.imageId] case final String target)
        ?resolvePath(target, from: key),
    ];
    for (final image in wanted) {
      if (imageFiles[image] case final bytes?) images[image] = bytes;
    }
    return TransferPage(
      path: key,
      title: page.title,
      kind: page.kind,
      content: page.content,
      tags: page.tags,
      properties: page.properties,
      position: page.position,
      children: [
        for (final child in childrenOf[path] ?? const <String>[]) build(child),
      ]..sort(_pageOrder),
    );
  }

  return ImportPlan(
    lists: lists,
    pages: [
      for (final path in childrenOf[_here] ?? const <String>[]) build(path),
    ]..sort(_pageOrder),
    images: images,
    skipped: skipped,
  );
}

List<String> _tagNames(String raw, Map<String, String> tagNames) => [
  for (final id in tagIdsOf(raw)) ?tagNames[id],
];

int _byPosition(WikiPage a, WikiPage b) {
  final byPosition = a.position.compareTo(b.position);
  return byPosition != 0 ? byPosition : a.title.compareTo(b.title);
}

int _pageOrder(TransferPage a, TransferPage b) {
  final byPosition = a.position.compareTo(b.position);
  return byPosition != 0 ? byPosition : a.title.compareTo(b.title);
}

/// The extension of [path], lower case and without its dot.
String _extension(String path) {
  final extension = p.posix.extension(path).toLowerCase();
  return extension.isEmpty ? extension : extension.substring(1);
}

/// What the image is, read from its first bytes — the server keeps no file names.
/// It stores JPEG, PNG, GIF and WebP; anything else would not be there.
String _imageExtension(Uint8List bytes) {
  bool startsWith(List<int> magic, [int at = 0]) =>
      bytes.length >= at + magic.length &&
      [for (final (index, byte) in magic.indexed) bytes[at + index] == byte]
          .every((same) => same);
  if (startsWith(_pngMagic)) return _png;
  if (startsWith(_gifMagic)) return _gif;
  if (startsWith(_riffMagic) && startsWith(_webpMagic, _webpMagicAt)) {
    return _webp;
  }
  return _jpg;
}

/// The folder of an export's images.
const mediaFolder = 'media';
const markdownExtension = '.md';
const archiveExtension = '.zip';

const _zip = 'zip';
const _markdownExtensions = {'md', 'markdown'};
const _jpg = 'jpg';
const _png = 'png';
const _gif = 'gif';
const _webp = 'webp';
const _imageExtensions = {_jpg, 'jpeg', _png, _gif, _webp};

const _zipMagic = [0x50, 0x4B];
const _pngMagic = [0x89, 0x50, 0x4E, 0x47];
const _gifMagic = [0x47, 0x49, 0x46, 0x38];
const _riffMagic = [0x52, 0x49, 0x46, 0x46];
const _webpMagic = [0x57, 0x45, 0x42, 0x50];
const _webpMagicAt = 8;

const _here = '.';
const _dot = '.';
const _backslash = r'\';
const _macResources = '__MACOSX';
const _untitled = 'untitled';
const _maxNameLength = 80;

/// The longest text a field may hold to sync (`SyncLimits` on the server): a longer
/// page would be created here and never arrive.
const _maxTextLength = 200000;
const _maxArchiveBytes = 512 * 1024 * 1024;

final _unsafeInNames = RegExp(r'[/\\:*?"<>|\x00-\x1f]');
final _spaces = RegExp(r'\s+');
final _leadingDots = RegExp(r'^\.+');
