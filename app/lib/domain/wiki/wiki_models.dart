import 'dart:convert';

import '../../core/common/wire.dart';
import 'wiki_page.dart';

/// A node in the page tree.
///
/// The tree is **built once from the flat list**, not queried again per level: with
/// arbitrary depth one query per node would be one query too many, and the
/// tree would flicker when expanding.
/// The kind of a recipe collection — a page like any other, whose purpose is recipes.
const kindRecipeFolder = 'RECIPE_FOLDER';

class WikiNode {
  WikiNode(this.page, this.children);

  final WikiPage page;
  final List<WikiNode> children;

  bool get isRecipe => page.kind == PageKinds.recipe;

  /// A recipe collection: a folder meant for recipes, a recipe branch even while empty.
  bool get isRecipeFolder => page.kind == kindRecipeFolder;

  /// Whether recipes live under this node — then the "+" menu offers "Folder" and
  /// "Recipe" instead of "Subpage".
  ///
  /// A recipe collection counts from the start. Before, a branch only became one through
  /// a recipe in it — and the only way to the first recipe was the import.
  /// The pages right below this one — what the tree's row counts for a page.
  int get subpageCount => children.length;

  /// The recipes anywhere below this one — what the row counts for a recipe branch.
  int get recipeCount => children.fold(
    0,
    (total, child) => total + (child.isRecipe ? 1 : 0) + child.recipeCount,
  );

  bool get isRecipeBranch =>
      isRecipe ||
      isRecipeFolder ||
      children.any((child) => child.isRecipe || child.isRecipeBranch);

  /// The tree without the archived pages.
  ///
  /// A subpage left active under an archived page hangs under the **nearest ancestor
  /// that is not archived** — only here, for display. Its `parentId` stays, so restoring
  /// the parent puts everything back where it was.
  static List<WikiNode> buildActive(List<WikiPage> pages) {
    final byId = {for (final page in pages) page.id: page};
    String? visibleParent(WikiPage page) {
      String? parentId = page.parentId;
      final seen = <String>{page.id};
      while (parentId != null && seen.add(parentId)) {
        final parent = byId[parentId];
        if (parent == null || parent.archivedAt == null) return parentId;
        parentId = parent.parentId;
      }
      return null;
    }

    return build([
      for (final page in pages)
        if (page.archivedAt == null)
          page.parentId == null ? page : page.withParentId(visibleParent(page)),
    ]);
  }

  /// Builds the tree from the flat list.
  static List<WikiNode> build(List<WikiPage> pages) {
    final byParent = <String?, List<WikiPage>>{};
    for (final page in pages) {
      byParent.putIfAbsent(page.parentId, () => []).add(page);
    }
    for (final group in byParent.values) {
      group.sort((a, b) {
        final byPosition = a.position.compareTo(b.position);
        return byPosition != 0 ? byPosition : a.title.compareTo(b.title);
      });
    }

    List<WikiNode> childrenOf(String? parentId, Set<String> seen) {
      return [
        for (final page in byParent[parentId] ?? const <WikiPage>[])
          // A cycle can arise when two devices move pages in opposite directions
          // while offline. It must not send the display into an endless loop —
          // the affected page is then simply missing from the tree once.
          if (seen.add(page.id)) WikiNode(page, childrenOf(page.id, seen)),
      ];
    }

    // A page whose parent is not (or no longer) there would otherwise hang in the void.
    // It sits at the root: visible and findable is better than gone.
    final known = {for (final page in pages) page.id};
    final roots = <WikiPage>[
      // The keys are `String?`; `null` is the pages at the root.
      // ignore: many_lints/avoid_collection_methods_with_unrelated_types
      ...?byParent[null],
      for (final entry in byParent.entries)
        if (entry.key != null && !known.contains(entry.key)) ...entry.value,
    ];

    final seen = <String>{};
    final tree = [
      for (final page
          in roots..sort((a, b) => a.position.compareTo(b.position)))
        if (seen.add(page.id)) WikiNode(page, childrenOf(page.id, seen)),
    ];
    // A cycle with no way up to the root — A under B, B under A — was reached from
    // nowhere and vanished from the tree entirely. Its first page sits at the root
    // instead; the rest of the cycle hangs below it.
    final rest = [...pages]..sort((a, b) => a.position.compareTo(b.position));
    for (final page in rest) {
      if (seen.add(page.id)) {
        tree.add(WikiNode(page, childrenOf(page.id, seen)));
      }
    }
    return tree;
  }
}

/// An ingredient of a recipe.
///
/// `uncertain` marks what the import could not split up with confidence —
/// `recipeIngredient` is free text and never fully adds up.
class Ingredient {
  // The fields of an ingredient in a recipe's `ingredients`.
  static const _labelField = 'label';
  static const _amountField = 'amount';
  static const _unitField = 'unit';
  static const _productIdField = 'productId';
  static const _stapleField = 'staple';
  static const _optionalField = 'optional';
  static const _uncertainField = 'uncertain';

  const Ingredient({
    required this.label,
    this.amount,
    this.unit,
    this.productId,
    this.staple = false,
    this.optional = false,
    this.uncertain = false,
  });

  final String label;
  final double? amount;
  final String? unit;
  final String? productId;

  /// Pantry staple — **unchecked** up front when moving to the shopping list.
  /// Everyone has salt.
  final bool staple;

  final bool optional;
  final bool uncertain;

  Ingredient copyWith({
    String? label,
    double? amount,
    String? unit,
    String? productId,
    bool? staple,
    bool? optional,
    bool? uncertain,
  }) => .new(
    label: label ?? this.label,
    amount: amount ?? this.amount,
    unit: unit ?? this.unit,
    productId: productId ?? this.productId,
    staple: staple ?? this.staple,
    optional: optional ?? this.optional,
    uncertain: uncertain ?? this.uncertain,
  );

  /// Scales the amount to a different number of servings.
  ///
  /// An ingredient **without** an amount is not scaled — "Salz nach Geschmack" stays
  /// "Salz nach Geschmack", and "etwas Öl" must not become "1,5 etwas Öl".
  Ingredient scaled(int from, int to) {
    final amount = this.amount;
    if (amount == null || from <= 0 || to <= 0 || from == to) return this;
    return copyWith(amount: amount * to / from);
  }

  Map<String, dynamic> toJson() => {
    _labelField: label,
    if (amount != null) _amountField: amount,
    if (unit != null) _unitField: unit,
    if (productId != null) _productIdField: productId,
    if (staple) _stapleField: true,
    if (optional) _optionalField: true,
    if (uncertain) _uncertainField: true,
  };

  static Ingredient fromJson(Map<String, dynamic> json) => .new(
    label: json[_labelField] as String? ?? '',
    amount: (json[_amountField] as num?)?.toDouble(),
    unit: json[_unitField] as String?,
    productId: json[_productIdField] as String?,
    staple: json[_stapleField] as bool? ?? false,
    optional: json[_optionalField] as bool? ?? false,
    uncertain: json[_uncertainField] as bool? ?? false,
  );

  static List<Ingredient> decode(String raw) {
    if (raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is Map<String, dynamic>) fromJson(entry),
      ];
    } on FormatException {
      // A broken column must not cost us the recipe.
      return const [];
    }
  }

  static String encode(List<Ingredient> ingredients) =>
      jsonEncode([for (final item in ingredients) item.toJson()]);
}

/// How an amount appears on screen.
///
/// "1,5" instead of "1.5" is handled by `intl`; this is only about turning `2.0` into
/// "2" and not turning `0.3333` into "0,3333333".
String formatAmount(double? amount) {
  if (amount == null) return '';
  final rounded = (amount * 100).round() / 100;
  if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
  return rounded.toString().replaceAll('.', ',');
}

/// The path from the root to here — for the breadcrumb.
/// The pages of [nodes] that can be opened in the tree: every one with subpages, at
/// any depth — what "Expand all" opens.
Set<String> expandableOf(List<WikiNode> nodes) => {
  for (final node in nodes)
    if (node.children.isNotEmpty) ...{
      node.page.id,
      ...expandableOf(node.children),
    },
};

List<WikiPage> breadcrumbOf(List<WikiPage> pages, String pageId) {
  final byId = {for (final page in pages) page.id: page};
  final trail = <WikiPage>[];
  WikiPage? current = byId[pageId];
  // The cycle guard is not decoration: two devices that move pages in opposite
  // directions while offline can build one.
  final seen = <String>{};
  while (current != null && seen.add(current.id)) {
    trail.insert(0, current);
    current = current.parentId == null ? null : byId[current.parentId];
  }
  return trail;
}

/// [rootId] and every page below it, however deep — archived ones included.
///
/// For the move: a page cannot go under itself or under one of its own subpages. Counted
/// over the active pages only, a page under an archived child was missed and offered as
/// a target, and the move built a cycle.
Set<String> branchOf(List<WikiPage> pages, String rootId) {
  final byParent = <String?, List<WikiPage>>{};
  for (final page in pages) {
    byParent.putIfAbsent(page.parentId, () => []).add(page);
  }
  final result = <String>{rootId};
  final queue = <String>[rootId];
  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    for (final child in byParent[current] ?? const <WikiPage>[]) {
      if (result.add(child.id)) queue.add(child.id);
    }
  }
  return result;
}

/// The recipes under [root], in tree order.
///
/// Each page once: a parent cycle that offline moves left behind made the walk recurse
/// until the stack overflowed — during build, so the page could not open.
List<WikiPage> recipesUnder(List<WikiPage> pages, WikiPage root) {
  final result = <WikiPage>[];
  final seen = <String>{root.id};
  void walk(String parentId) {
    final children = pages.where((page) => page.parentId == parentId).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    for (final child in children) {
      if (!seen.add(child.id)) continue;
      if (child.kind == PageKinds.recipe) result.add(child);
      walk(child.id);
    }
  }

  walk(root.id);
  return result;
}

/// The archived pages the archive lists by themselves: those whose parent is not
/// archived along. A subpage archived with its parent sits under it — "with 3
/// subpages" — and is not listed again. One rule for the archive and its count.
List<WikiPage> topLevelArchivedPages(List<WikiPage> archived) {
  final ids = {for (final page in archived) page.id};
  return [
    for (final page in archived)
      if (!ids.contains(page.parentId)) page,
  ];
}
