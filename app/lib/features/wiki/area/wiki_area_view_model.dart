import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../app/stores.dart';
import '../../../core/api/generated/export.dart' hide Mutation;
import '../../../core/common/command.dart';
import '../../../core/common/wire.dart';
import '../../../domain/common/item_ref.dart';
import '../../../domain/tags/tag.dart';
import '../../../domain/wiki/wiki_models.dart';
import '../../../domain/wiki/page_moves.dart';
import '../../../domain/wiki/wiki_page.dart';
import '../../../domain/access/access_rules.dart';
import '../../../core/api/hiwiski_failure.dart';

part 'wiki_area_view_model.g.dart';

/// `create`, run by a view: it shows the command running and reacts to how it ended.
final createPageMutation = Mutation<String>(label: 'wikiAreaViewModel.create');

/// `drop`, run by the tree: it says so when a drop was not allowed.
final dropPageMutation = Mutation<DropOutcome>(label: 'wikiAreaViewModel.drop');

/// The wiki area: the page tree through the tag filter.
@immutable
class WikiAreaState {
  const WikiAreaState({
    required this.pages,
    required this.tree,
    required this.shown,
    required this.groupShared,
    required this.tags,
    required this.filter,
    required this.movable,
    this.expanded = const {},
    this.expandable = const {},
    this.canImport = true,
  });

  /// Whether recipes can be imported from an address — the server fetches them;
  /// without one the entry is left out.
  final bool canImport;

  /// Which pages of the tree are expanded — remembered across leaving the wiki.
  final Set<String> expanded;

  /// The pages of the tree shown that have subpages to open.
  final Set<String> expandable;

  /// Whether every page that can be opened is: the button then offers "Collapse
  /// all", otherwise "Expand all".
  bool get allExpanded =>
      expandable.isNotEmpty && expandable.every(expanded.contains);

  /// Every page, archived ones included — an archived page still opens, with its
  /// breadcrumb.
  final List<WikiPage> pages;

  /// The pages that are not archived, as a tree.
  final List<WikiNode> tree;

  /// [tree] through the tag filter: a node stays if it or something below it
  /// carries one of the selected tags — otherwise the paths there would vanish.
  final List<WikiNode> shown;

  /// Who sees a root, at a glance: `true` if a group sees it, `false` if only
  /// individual people or only the owner do; missing while not known — offline
  /// nothing shows rather than a guessed lock.
  final Map<String, bool> groupShared;

  final List<Tag> tags;
  final Set<String> filter;

  WikiPage? pageById(String id) =>
      pages.where((page) => page.id == id).firstOrNull;

  /// The pages above [page], from its root down to its parent — the way up that the
  /// page's header offers as links.
  List<WikiPage> trailOf(WikiPage page) {
    final trail = breadcrumbOf(pages, page.id);
    return trail.isEmpty ? trail : trail.sublist(0, trail.length - 1);
  }

  /// The node of a page, anywhere in the tree.
  WikiNode? node(String id) => _find(tree, id);

  /// Only archived pages left counts as empty: the tree has nothing to show.
  bool get empty => pages.every((page) => page.archivedAt != null);

  /// The pages the member may drag — and drop into: their own, and those of a root
  /// they may write (its subpages inherit it). A root whose share sheet has not come
  /// counts as writable: offline the tree should not freeze, and the drop checks each
  /// page it changes before writing.
  final Set<String> movable;
}

/// How a drop in the tree ended.
enum DropOutcome {
  /// Written.
  moved,

  /// Nothing to do: onto itself, into its own subtree, or back where it was.
  unchanged,

  /// A page the drop would change may not be written by this member.
  notAllowed,
}

WikiNode? _find(List<WikiNode> nodes, String id) {
  for (final node in nodes) {
    if (node.page.id == id) return node;
    if (_find(node.children, id) case final found?) return found;
  }
  return null;
}

/// The nodes that carry one of the tags themselves or below them.
///
/// Each subtree filtered once: filtering it twice — once to ask, once to keep — doubled
/// the work on every level, exponential in the depth of the tree.
List<WikiNode> _filter(List<WikiNode> nodes, Set<String> tags) => [
  for (final node in nodes)
    if (_filter(node.children, tags) case final children
        when passesTagFilter(tags, node.page.tags) || children.isNotEmpty)
      WikiNode(node.page, children),
];

@riverpod
Stream<List<WikiPage>> _pages(Ref ref) =>
    ref.watch(wikiRepositoryProvider).watchPages();

@riverpod
Stream<List<Tag>> _tags(Ref ref) =>
    ref.watch(tagRepositoryProvider).watchTags();

@riverpod
Stream<ShareSheet> _shares(Ref ref, String pageId) => ref
    .watch(accessRepositoryProvider)
    .watchShareSheet(ItemRef.wikiPage(pageId));

@riverpod
class WikiAreaViewModel extends _$WikiAreaViewModel {
  /// Which page holds the filter.
  static const _page = 'wiki';

  static const _area = TagFilterAreas.areas;

  @override
  Future<WikiAreaState> build() async {
    ref.watch(tagFilterHoldProvider(_area, _page));
    final filter = ref.watch(
      tagFiltersProvider.select((f) => f[_area] ?? const <String>{}),
    );
    final tagUses = ref.watch(preferencesProvider.select((p) => p.tagUses));
    final pageList = ref.watch(_pagesProvider.future);
    final tags = ref.watch(_tagsProvider.future);
    final me = ref.watch(sessionProvider.select((s) => s.member?.id));
    final expanded = ref.watch(wikiTreeProvider);
    final pages = await pageList;
    final tree = WikiNode.buildActive(pages);
    final shown = filter.isEmpty ? tree : _filter(tree, filter);
    final sheets = {
      for (final root in tree)
        root.page.id: ref.watch(_sharesProvider(root.page.id)).value,
    };
    return WikiAreaState(
      canImport: ref.watch(sessionProvider.select((s) => s.hasServer)),
      pages: pages,
      tree: tree,
      shown: shown,
      // From the server — not waited for: offline nothing shows rather than a
      // guessed lock.
      groupShared: {
        for (final root in tree)
          if (sheets[root.page.id] case final sheet?)
            root.page.id: sheet.entries.any(
              (entry) => entry.source != .owner && entry.subjectType == .group,
            ),
      },
      tags: rankTags(await tags, tagUses),
      filter: filter,
      expanded: expanded,
      expandable: expandableOf(shown),
      movable: {
        for (final root in tree)
          ..._movable(
            root,
            writable: mayWrite(sheets[root.page.id]?.myLevel),
            me: me,
          ),
      },
    );
  }

  /// [node] and what lies below it, as far as the member may move it.
  static Iterable<String> _movable(
    WikiNode node, {
    required bool writable,
    required String? me,
  }) sync* {
    if (writable || node.page.ownerId == me) yield node.page.id;
    for (final child in node.children) {
      yield* _movable(child, writable: writable, me: me);
    }
  }

  /// Reads the pages again — after they could not be read.
  void retry() => ref.invalidate(_pagesProvider);

  /// Returns the new page's id.
  @command
  Future<String> create({
    required String title,
    String? parentId,
    String kind = PageKinds.page,
  }) => ref
      .read(wikiRepositoryProvider)
      .createPage(title: title, parentId: parentId, kind: kind);

  /// A page dropped on another row of the tree: before it, inside it or after it.
  ///
  /// Every page the drop changes — the moved one, a new parent, siblings that have to
  /// make room — is checked against the member's level first; one that may not be
  /// written stops the whole drop. The server checks again either way.
  @command
  Future<DropOutcome> drop(String id, String targetId, DropZone zone) async {
    final current = state.value;
    if (current == null) return .unchanged;
    final wiki = ref.read(wikiRepositoryProvider);
    final access = ref.read(accessRepositoryProvider);
    final me = ref.read(sessionProvider).member?.id;
    final plan = dropPlan(current.tree, id, targetId, zone);
    final moved = current.pageById(id);
    if (plan == null || moved == null) return .unchanged;
    final positions = positionsFor(plan.siblings, id);
    final reparent = plan.parentId != moved.parentId;
    if (!reparent && positions.isEmpty) return .unchanged;
    // Into another parent or to the root is the owner's: it changes who sees the page.
    // Rearranging among its siblings is not.
    if (reparent && !ownsItem(moved.ownerId, me)) return .notAllowed;

    final touched = {id, ...positions.keys, if (reparent) ?plan.parentId};
    for (final pageId in touched) {
      if (current.pageById(pageId)?.ownerId == me) continue;
      final AccessLevel? level;
      try {
        level = (await access.shareSheet(ItemRef.wikiPage(pageId))).myLevel;
      } on HiwiskiFailure {
        // Unknown — offline, never seen: the server has the last word.
        continue;
      }
      if (!mayWrite(level)) return .notAllowed;
    }
    await wiki.arrangePages(
      moved: moved,
      parentId: plan.parentId,
      positions: positions,
      siblings: plan.siblings,
    );
    return .moved;
  }

  /// The tree's expanded pages changed — kept for the next visit.
  void setExpanded(Set<String> expanded) =>
      ref.read(wikiTreeStoreProvider).set(expanded);

  /// Opens every page of the tree shown that has subpages.
  void expandAll(WikiAreaState state) =>
      setExpanded({...state.expanded, ...state.expandable});

  /// Closes every page of the tree.
  void collapseAll() => setExpanded(const {});

  void toggleTag(String id) =>
      ref.read(tagFilterStoreProvider).toggle(_area, id);

  void clearTags() => ref.read(tagFilterStoreProvider).clear(_area);
}
