// The domain models of this feature, field for field what the local database
// stores. The repository maps its rows onto them: the layers above see these
// classes, never a Drift row.

/// A product from the shared catalog: its category and its usual unit.
class CatalogProduct {
  const CatalogProduct({
    required this.id,
    required this.name,
    this.aisleId,
    this.defaultUnit,
    required this.usageCount,
  });

  final String id;
  final String name;
  final String? aisleId;
  final String? defaultUnit;
  final int usageCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogProduct &&
          other.id == id &&
          other.name == name &&
          other.aisleId == aisleId &&
          other.defaultUnit == defaultUnit &&
          other.usageCount == usageCount;

  @override
  int get hashCode =>
      Object.hashAll([id, name, aisleId, defaultUnit, usageCount]);
}

/// A category of the shopping list.
///
/// Exactly one of [key] and [name] is set: a built-in one ([AisleKeys]) is shown in
/// the app's language, one of the family's own as written.
class CatalogAisle {
  const CatalogAisle({
    required this.id,
    this.key,
    this.name,
    required this.position,
    this.hidden = false,
  });

  final String id;
  final String? key;
  final String? name;
  final int position;

  /// Neither shown nor offered; its products go under "Other".
  final bool hidden;

  bool get builtIn => key != null;

  /// Whether this app knows it: an own category, or a built-in one with a key it has
  /// a name for. An unknown key could only be called "Other".
  bool get known => !builtIn || AisleKeys.all.contains(key);

  /// Whether it is shown — grouped under and offered in pickers: known and not hidden.
  /// One rule for the grouping, the picker and the categories screen, which each had
  /// their own copy.
  bool get shown => !hidden && known;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogAisle &&
          other.id == id &&
          other.key == key &&
          other.name == name &&
          other.position == position &&
          other.hidden == hidden;

  @override
  int get hashCode => Object.hash(id, key, name, position, hidden);
}

/// The built-in categories as the server stores them — keys, not words. The screen
/// shows them translated; a key this app does not know yet goes under "Other".
abstract final class AisleKeys {
  static const produce = 'produce';
  static const bakery = 'bakery';
  static const meatSeafood = 'meat_seafood';
  static const deli = 'deli';
  static const dairyEggs = 'dairy_eggs';
  static const breakfast = 'breakfast';
  static const pantry = 'pantry';
  static const spicesCondiments = 'spices_condiments';
  static const snacksSweets = 'snacks_sweets';
  static const beverages = 'beverages';
  static const frozen = 'frozen';
  static const baby = 'baby';
  static const personalCare = 'personal_care';
  static const household = 'household';
  static const pet = 'pet';

  static const all = [
    produce,
    bakery,
    meatSeafood,
    deli,
    dairyEggs,
    breakfast,
    pantry,
    spicesCondiments,
    snacksSweets,
    beverages,
    frozen,
    baby,
    personalCare,
    household,
    pet,
  ];
}

/// The catalog name a category change for a row goes under: its linked product's
/// name if it has one, otherwise its own title.
///
/// [aisleFor] reads the linked product first. A change written under the row's title —
/// "Hokkaido-Kürbis" linked to "Kürbis" — went to another product, and the row jumped
/// back to the old category.
String catalogNameFor(
  String title,
  String? productId,
  List<CatalogProduct> products,
) =>
    products.where((product) => product.id == productId).firstOrNull?.name ??
    title;

/// The category ID of a row: via the product, otherwise via the name.
///
/// "Hokkaido-Kürbis" finds "Kürbis", "Hafermilch" finds "Hafermilch" before "Milch" —
/// an exact name wins, otherwise the longest contained one.
String? aisleFor(
  String title,
  String? productId,
  List<CatalogProduct> products,
) {
  if (productId != null) {
    final byId = products
        .where((product) => product.id == productId)
        .firstOrNull;
    if (byId?.aisleId case final aisleId?) return aisleId;
  }
  final name = title.trim().toLowerCase();
  if (name.isEmpty) return null;
  CatalogProduct? best;
  for (final product in products) {
    final candidate = product.name.toLowerCase();
    if (candidate == name) return product.aisleId;
    if (name.contains(candidate) &&
        (best == null || candidate.length > best.name.length)) {
      best = product;
    }
  }
  return best?.aisleId;
}

/// The shopping rows grouped by category, in the family's order; what has none — or
/// a hidden one, or one this app does not know — goes under "Other" (`null`) at the
/// end.
List<(CatalogAisle?, List<T>)> groupByAisle<T>(
  List<T> rows, {
  required String Function(T row) title,
  required String? Function(T row) productId,
  required List<CatalogProduct> products,
  required List<CatalogAisle> aisles,
}) {
  final shown = {
    for (final aisle in aisles)
      if (aisle.shown) aisle.id: aisle,
  };
  final byAisle = <String?, List<T>>{};
  for (final row in rows) {
    final id = aisleFor(title(row), productId(row), products);
    byAisle.putIfAbsent(shown.containsKey(id) ? id : null, () => []).add(row);
  }
  final ordered = shown.values.toList()
    ..sort((a, b) => a.position.compareTo(b.position));
  return [
    for (final aisle in ordered)
      if (byAisle[aisle.id] case final rows?) (aisle, rows),
    // The keys are `String?`; `null` is the products without an aisle.
    // ignore: many_lints/avoid_collection_methods_with_unrelated_types
    if (byAisle[null] case final rows?) (null, rows),
  ];
}

/// The categories a picker offers: visible ones this app knows, in their order.
List<CatalogAisle> offeredAisles(List<CatalogAisle> aisles) => [
  for (final aisle in aisles)
    if (aisle.shown) aisle,
];
