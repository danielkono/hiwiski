import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/link_index.dart';
import '../../../app/repositories.dart';
import '../../../app/stores.dart';
import '../../../core/api/generated/export.dart' hide Mutation;
import '../../../core/common/command.dart';
import '../../../core/common/wire.dart';
import '../../../data/media/media_repository.dart' show ImageOwnerTypes;
import '../../../domain/access/access_rules.dart';
import '../../../domain/common/change.dart';
import '../../../domain/common/item_ref.dart';
import '../../../domain/links/link_index.dart';
import '../../../domain/tags/tag.dart';
import '../../../domain/wiki/pinboard.dart';
import '../../../domain/wiki/wiki_models.dart';
import '../../../domain/wiki/wiki_page.dart';

part 'page_view_model.g.dart';

/// `archive`, run by a view: it shows the command running and reacts to how it ended.
/// `addContentImages`, run by the editor: it inserts the images when it is done and
/// shows that it runs.
final addContentImagesMutation = Mutation<List<String>>(
  label: 'pageViewModel.addContentImages',
);

final archivePageMutation = Mutation<List<WikiPage>>(
  label: 'pageViewModel.archive',
);

/// A wiki page as its screen, its body and a link's preview show it.
@immutable
class PageState {
  PageState({
    required this.page,
    required this.pages,
    required this.level,
    required this.members,
    required this.tags,
    required this.servings,
    this.me,
    Pinboard? pinboard,
    this.pinboardTargets = const {},
  }) : pinboard = pinboard ?? .empty;

  final WikiPage page;

  /// The page's pinboard — empty on a page of another kind.
  final Pinboard pinboard;

  /// What the map's link elements point to, by their address — what they show.
  final Map<String, LinkItem> pinboardTargets;

  /// Every page, archived ones included — the breadcrumb, the recipes below, where
  /// it may move.
  final List<WikiPage> pages;

  /// The reader's level: on *read* there is nothing to edit — not even the tags.
  final AccessLevel? level;
  final Map<String, Member> members;

  /// The known tags by id — for the chips on recipe cards.
  final Map<String, Tag> tags;

  /// The servings chosen for display; `null` for the recipe's own.
  final int? servings;

  /// Who is signed in — moving a page, and deleting a page at the root, are its
  /// owner's.
  final String? me;

  bool get archived => page.archivedAt != null;

  bool get mayChange => mayWrite(level);

  /// An archived page is read-only.
  bool get writable => mayChange && !archived;

  /// Moving it to another parent or to the root changes who sees it: the owner's.
  bool get mayMove => writable && ownsItem(page.ownerId, me);

  /// A writer deletes a subpage inside what they may write; a page at the root —
  /// what was shared with them — only its owner deletes.
  bool get mayDelete =>
      mayChange && (ownsItem(page.ownerId, me) || page.parentId != null);

  bool get isRecipe => page.kind == PageKinds.recipe;

  /// From the root down to the page.
  List<WikiPage> get trail => breadcrumbOf(pages, page.id);

  /// How many subpages the page has, however deep — open ones go along when it is
  /// archived, archived ones come back when it is restored.
  int subpages({required bool archived}) {
    final below = branchOf(pages, page.id)..remove(page.id);
    return pages
        .where(
          (page) =>
              below.contains(page.id) && (page.archivedAt != null) == archived,
        )
        .length;
  }

  /// Who archived the page, by name.
  String? get archivedBy => members[page.archivedBy]?.displayName;

  /// The recipes below a collection. Its own archived recipes are listed only on an
  /// archived page.
  List<WikiPage> get recipes {
    return recipesUnder(
      archived
          ? pages
          : [
              for (final row in pages)
                if (row.archivedAt == null) row,
            ],
      page,
    );
  }

  /// Where the page may move: no archived page — nothing new goes under it
  /// — and neither itself nor one of its own subpages, which would
  /// make a cycle and the branch vanish from the tree. Counted over all pages: a
  /// subpage under an archived one is one too.
  List<WikiNode> get moveTargets {
    final forbidden = branchOf(pages, page.id);
    List<WikiNode> without(List<WikiNode> nodes) => [
      for (final node in nodes)
        if (!forbidden.contains(node.page.id))
          WikiNode(node.page, without(node.children)),
    ];
    return without(
      WikiNode.build([
        for (final row in pages)
          if (row.archivedAt == null) row,
      ]),
    );
  }

  int get _baseServings => page.servings ?? 4;

  /// Scaling is for display only — the recipe stays stored the way it was written.
  /// A recipe that rewrites itself while being viewed would be useless after the
  /// third guest.
  int get shownServings => servings ?? _baseServings;

  List<Ingredient> get scaledIngredients => [
    for (final item in Ingredient.decode(page.ingredients))
      item.scaled(_baseServings, shownServings),
  ];
}

@riverpod
Stream<List<WikiPage>> _pages(Ref ref) =>
    ref.watch(wikiRepositoryProvider).watchPages();

@riverpod
Stream<Pinboard> _pinboard(Ref ref, String pageId) =>
    ref.watch(pinboardRepositoryProvider).watchMap(pageId);

@riverpod
Stream<ShareSheet> _shares(Ref ref, String pageId) => ref
    .watch(accessRepositoryProvider)
    .watchShareSheet(ItemRef.wikiPage(pageId));

@riverpod
Stream<List<Member>> _members(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchMembers();

@riverpod
Stream<List<Tag>> _tags(Ref ref) =>
    ref.watch(tagRepositoryProvider).watchTags();

@riverpod
Stream<Uint8List> _image(Ref ref, String imageId, bool preview) =>
    ref.watch(mediaRepositoryProvider).watchImage(imageId, preview: preview);

@riverpod
class PageViewModel extends _$PageViewModel {
  int? _servings;

  /// `null` once the page is gone.
  @override
  Future<PageState?> build(String pageId) async {
    // From the server — not waited for: offline they may never come.
    final level = ref.watch(_sharesProvider(pageId)).value?.myLevel;
    final members = ref.watch(_membersProvider).value ?? const <Member>[];
    final pageList = ref.watch(_pagesProvider.future);
    final tags = ref.watch(_tagsProvider.future);
    final pages = await pageList;
    final page = pages.where((page) => page.id == pageId).firstOrNull;
    if (page == null) return null;
    // A pinboard and what it links to, only on a pinboard's page: watched on every
    // page, a page was built anew whenever anything anywhere that can be linked to
    // changed — a task's title, a list's name.
    final pinboard = page.kind == PageKinds.pinboard
        ? await ref.watch(_pinboardProvider(pageId).future)
        : null;
    return PageState(
      page: page,
      pinboard: pinboard,
      pinboardTargets: pinboard == null
          ? const {}
          : pinboardTargetsOf(pinboard, ref.watch(linkIndexProvider)),
      pages: pages,
      level: level,
      members: {for (final member in members) member.id: member},
      tags: {for (final tag in await tags) tag.id: tag},
      servings: _servings,
      me: ref.watch(sessionProvider.select((s) => s.member?.id)),
    );
  }

  /// The servings to scale the ingredients to — shared by the recipe and the docked
  /// "Add to shopping list" button.
  void setServings(int servings) {
    _servings = servings;
    ref.invalidateSelf();
  }

  /// Saves title, text and what the page's kind adds ([properties], by their wire
  /// names — `recipeChanges` for a recipe).
  Future<void> edit(
    WikiPage page, {
    String? title,
    String? content,
    Map<String, Object?> properties = const {},
  }) => ref
      .read(wikiRepositoryProvider)
      .updatePage(page, title: title, content: content, properties: properties);

  /// Upload first, then set it via sync: the upload changes no item, and the
  /// `imageId` travels like any other field — offline it waits in the outbox.
  Future<void> uploadImage(
    WikiPage page, {
    required Uint8List bytes,
    required String filename,
  }) async {
    final wiki = ref.read(wikiRepositoryProvider);
    final id = await ref
        .read(mediaRepositoryProvider)
        .upload(
          ownerType: ImageOwnerTypes.wikiPage,
          ownerItemId: page.id,
          bytes: bytes,
          filename: filename,
        );
    await wiki.updatePage(page, properties: recipeChanges(imageId: Change(id)));
  }

  /// Keeps images for the page's text on the device, in order, and returns their ids
  /// — the editor puts them into the text at the cursor at once. They go up with the
  /// sync, after the page: offline too, and for a page not on the server yet.
  ///
  /// Not so the recipe picture ([uploadImage]): the server only takes an `imageId` it
  /// already has, while it reads nothing from the images in a text.
  @command
  Future<List<String>> addContentImages(
    WikiPage page,
    List<({Uint8List bytes, String filename})> files,
  ) async {
    final media = ref.read(mediaRepositoryProvider);
    return [
      for (final file in files)
        await media.keep(
          ownerType: ImageOwnerTypes.wikiPage,
          ownerItemId: page.id,
          bytes: file.bytes,
          filename: file.filename,
        ),
    ];
  }

  /// Returns what was archived, for "Undo".
  @command
  Future<List<WikiPage>> archive(WikiPage page, {required bool withSubpages}) =>
      ref
          .read(wikiRepositoryProvider)
          .archivePage(page, withSubpages: withSubpages);

  Future<void> restorePages(List<WikiPage> pages) =>
      ref.read(wikiRepositoryProvider).restorePages(pages);

  Future<void> restore(WikiPage page, {required bool withSubpages}) => ref
      .read(wikiRepositoryProvider)
      .restorePage(page, withSubpages: withSubpages);

  Future<void> delete(WikiPage page) =>
      ref.read(wikiRepositoryProvider).deletePage(page);

  /// A box ticked right on the rendered page.
  Future<void> toggleTask(WikiPage page, int index) =>
      ref.read(wikiRepositoryProvider).toggleTaskAt(page, index);

  Future<void> move(WikiPage page, String? parentId) =>
      ref.read(wikiRepositoryProvider).movePage(page, parentId);
}

/// One revision in full, opened for reading.
@riverpod
class PageRevisionViewModel extends _$PageRevisionViewModel {
  @override
  Future<Revision> build(String pageId, String revisionId) =>
      ref.watch(wikiRepositoryProvider).revision(pageId, revisionId);

  void retry() => ref.invalidateSelf();
}

/// An image of the media store, in memory only while it is shown.
@riverpod
class PageImageViewModel extends _$PageImageViewModel {
  @override
  Future<Uint8List> build(String imageId, bool preview) =>
      ref.watch(_imageProvider(imageId, preview).future);
}
