/// What an export writes and an import reads: lists and wiki pages as Markdown files,
/// the way a person can read and edit them outside the app.
///
/// The models here are the files' content, not the database's rows: tags by name
/// instead of id, a board's column by its place instead of its id, images and links
/// between pages as paths inside the export. Ids never leave the device — an import
/// creates new items, on this server or another one.
library;

import 'dart:typed_data';

/// One file of an export, or one the person picked for an import.
class const TransferFile(
  /// The path inside the export, with `/` on every platform; for a picked file its
  /// name.
  final String path,
  final Uint8List bytes,
);

/// A column of a board, without its id: an import gives it a new one.
class const TransferColumn({
  required final String name,
  required final String colorToken,
  required final bool done,
});

/// A task as a list's file holds it.
class const TransferTask({
  required final String title,
  final bool done = false,
  final String? description,
  final DateTime? dueDate,
  final String? dueTime,
  final String? rrule,
  final double? amount,
  final String? unit,

  /// The tags' names.
  final List<String> tags = const [],

  /// On a board, the index of its column in the list's columns; `null` leaves the
  /// place to the board's own rule (the first open or the first done column).
  final int? column,
});

/// A task list, a shopping list or a board with its tasks.
class TransferList {
  const TransferList({
    required this.name,
    required this.kind,
    this.description,
    this.colorToken,
    this.tags = const [],
    this.columns = const [],
    this.tasks = const [],
  });

  final String name;
  final String kind;
  final String? description;
  final String? colorToken;
  final List<String> tags;
  final List<TransferColumn> columns;
  final List<TransferTask> tasks;

  int get doneCount => tasks.where((task) => task.done).length;
}

/// A wiki page of any kind, with the pages below it.
class TransferPage {
  const TransferPage({
    required this.path,
    required this.title,
    required this.kind,
    required this.content,
    this.tags = const [],
    this.properties = const {},
    this.position = 0,
    this.children = const [],
  });

  /// The page's file inside the export — what a relative link or image in
  /// [content] is resolved against. A page an import makes up for a folder without a
  /// file of its own has the folder's path.
  final String path;
  final String title;
  final String kind;

  /// The text, with images and links to other exported pages as relative paths.
  final String content;
  final List<String> tags;

  /// What the page's kind adds, as the page stores it; an image among them is a
  /// relative path like those in [content].
  final Map<String, Object?> properties;
  final int position;
  final List<TransferPage> children;

  /// This page and every page below it.
  int get count => children.fold(1, (total, child) => total + child.count);
}

/// Where an import was started: it decides what a file becomes that does not say what
/// it is.
enum ImportPlace { todo, wiki }

/// Why a picked file is not part of the import.
enum SkipReason {
  /// Neither Markdown nor a zip archive.
  unsupported,

  /// A zip archive that cannot be opened.
  brokenArchive,

  /// Not text in UTF-8.
  notText,

  /// A list's file without a single task.
  noTasks,

  /// Longer than a text may be to sync.
  tooLong,
}

class const SkippedFile(final String path, final SkipReason reason);

/// What the picked files hold, checked and ready to be shown and taken.
class ImportPlan {
  const ImportPlan({
    this.lists = const [],
    this.pages = const [],
    this.images = const {},
    this.skipped = const [],
  });

  final List<TransferList> lists;

  /// The pages that go to the wiki's root, each with its branch.
  final List<TransferPage> pages;

  /// The images the pages point to, by their path inside the export.
  final Map<String, Uint8List> images;
  final List<SkippedFile> skipped;

  int get pageCount => pages.fold(0, (total, page) => total + page.count);

  int get taskCount =>
      lists.fold(0, (total, list) => total + list.tasks.length);

  bool get isEmpty => lists.isEmpty && pages.isEmpty;

  /// Every tag named anywhere in the import, each once.
  Set<String> get tagNames {
    final names = <String>{};
    void collect(TransferPage page) {
      names.addAll(page.tags);
      page.children.forEach(collect);
    }

    pages.forEach(collect);
    for (final list in lists) {
      names.addAll(list.tags);
      for (final task in list.tasks) {
        names.addAll(task.tags);
      }
    }
    return names;
  }
}

/// What the person picked for an import, and where they started it.
///
/// Compared by identity: it names one pick, and the preview and the import that
/// follows it read the same files.
class ImportSource(
  final List<TransferFile> files, {
  required final ImportPlace place,
});
