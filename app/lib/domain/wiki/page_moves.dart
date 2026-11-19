import 'wiki_models.dart';
import 'wiki_page.dart';

/// Where a page dropped on another row of the tree lands: before it, inside it as its last subpage, or after it.
enum DropZone { before, inside, after }

/// The distance between two sibling positions after a renumbering.
const pagePositionStep = 1024;

/// What a drop makes of the tree: the page's new parent (`null`: the root), and its
/// new siblings in order, itself among them.
typedef DropPlan = ({String? parentId, List<WikiPage> siblings});

/// The plan for dropping [draggedId] on [targetId] in [zone] — `null` where the drop
/// is no move at all: onto itself, or into its own subtree, which would make a cycle.
///
/// [tree] is the tree as shown: an archived parent's active subpages hang under the
/// nearest active ancestor there, and that is where a drop beside them puts a page.
DropPlan? dropPlan(
  List<WikiNode> tree,
  String draggedId,
  String targetId,
  DropZone zone,
) {
  if (draggedId == targetId) return null;
  final dragged = _find(tree, draggedId);
  final target = _find(tree, targetId);
  if (dragged == null || target == null) return null;
  if (_find(dragged.node.children, targetId) != null) return null;

  if (zone == .inside) {
    return (
      parentId: target.node.page.id,
      siblings: [
        for (final child in target.node.children)
          if (child.page.id != draggedId) child.page,
        dragged.node.page,
      ],
    );
  }
  final others = [
    for (final sibling in target.siblings)
      if (sibling.page.id != draggedId) sibling.page,
  ];
  final at = others.indexWhere((page) => page.id == targetId);
  others.insert(zone == .before ? at : at + 1, dragged.node.page);
  return (parentId: target.parentId, siblings: others);
}

/// The positions a plan writes — as few as it can: where the moved page fits between
/// its new neighbours, only it changes; where they leave no room (two pages on the
/// same position, as every page starts), the whole row is renumbered.
///
/// Returns page id → new position, only for the pages whose position changes.
Map<String, int> positionsFor(List<WikiPage> siblings, String movedId) {
  final at = siblings.indexWhere((page) => page.id == movedId);
  final before = at > 0 ? siblings[at - 1].position : null;
  final after = at < siblings.length - 1 ? siblings[at + 1].position : null;
  final between = switch ((before, after)) {
    (null, null) => 0,
    (null, final after?) => after - pagePositionStep,
    (final before?, null) => before + pagePositionStep,
    (final before?, final after?) when after - before < 2 => null,
    (final before?, final after?) => before + (after - before) ~/ 2,
  };
  // Room only counts where the rest of the row is in order already: ties among the
  // others are sorted by title, and the moved page would land somewhere among them.
  final ordered = [
    for (int i = 1; i < siblings.length; i++)
      if (i != at && i - 1 != at)
        siblings[i - 1].position < siblings[i].position,
  ].every((strict) => strict);
  if (between != null && ordered) {
    return {if (siblings[at].position != between) movedId: between};
  }
  return {
    for (final (index, page) in siblings.indexed)
      if (page.position != index * pagePositionStep)
        page.id: index * pagePositionStep,
  };
}

/// A node, the list it sits in and its parent's id, as shown.
({WikiNode node, List<WikiNode> siblings, String? parentId})? _find(
  List<WikiNode> nodes,
  String id, [
  String? parentId,
]) {
  for (final node in nodes) {
    if (node.page.id == id) {
      return (node: node, siblings: nodes, parentId: parentId);
    }
    if (_find(node.children, id, node.page.id) case final found?) return found;
  }
  return null;
}
