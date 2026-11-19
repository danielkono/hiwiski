import 'dart:convert';

import '../../core/common/wire.dart';
import '../common/change.dart';
import 'wiki_models.dart';
import 'wiki_page.dart';

/// A recipe's fields, read from the page's properties. On the wire they
/// keep the names they always had.
extension RecipeFields on WikiPage {
  int? get servings => (property(WireFields.servings) as num?)?.toInt();

  /// The ingredients as JSON — what `Ingredient.decode` reads.
  String get ingredients => switch (property(WireFields.ingredients)) {
    final List<Object?> list => jsonEncode(list),
    _ => '[]',
  };

  String? get sourceUrl => property(WireFields.sourceUrl) as String?;

  String? get imageId => property(WireFields.imageId) as String?;

  int? get durationMinutes =>
      (property(WireFields.durationMinutes) as num?)?.toInt();
}

/// Changes to a recipe's fields as the properties that carry them — each only if
/// given; [Change] clears what may be empty.
Map<String, Object?> recipeChanges({
  Change<int?>? servings,
  List<Ingredient>? ingredients,
  Change<String?>? sourceUrl,
  Change<int?>? durationMinutes,
  Change<String?>? imageId,
}) => {
  if (servings != null) WireFields.servings: servings.value,
  if (ingredients != null)
    WireFields.ingredients: [for (final item in ingredients) item.toJson()],
  if (sourceUrl != null) WireFields.sourceUrl: sourceUrl.value,
  if (durationMinutes != null)
    WireFields.durationMinutes: durationMinutes.value,
  if (imageId != null) WireFields.imageId: imageId.value,
};
