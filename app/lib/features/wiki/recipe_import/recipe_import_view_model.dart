import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../core/api/generated/export.dart' hide Mutation;
import '../../../core/common/command.dart';
import '../../../core/common/wire.dart';
import '../../../domain/common/change.dart';
import '../../../domain/wiki/wiki_models.dart';
import '../../../domain/wiki/wiki_page.dart';

part 'recipe_import_view_model.g.dart';

/// `take`, run by a view: it shows the command running and reacts to how it ended.
final takeRecipeMutation = Mutation<String>(
  label: 'recipeImportViewModel.take',
);

@riverpod
Stream<List<WikiPage>> _pages(Ref ref) =>
    ref.watch(wikiRepositoryProvider).watchPages();

/// A recipe from an address: fetched and read by the server, reviewed here, taken
/// into a folder.
@riverpod
class RecipeImportViewModel extends _$RecipeImportViewModel {
  /// Where a recipe can go: a folder, not another recipe — recipe collections first,
  /// that is where an import usually goes. No archived page.
  @override
  Future<List<WikiPage>> build() async =>
      [
        for (final page in await ref.watch(_pagesProvider.future))
          if (page.archivedAt == null && page.kind != PageKinds.recipe) page,
      ]..sort(
        (a, b) =>
            (b.kind == kindRecipeFolder ? 1 : 0) -
            (a.kind == kindRecipeFolder ? 1 : 0),
      );

  /// Creates the recipe under [parentId] and returns its id.
  @command
  Future<String> take({
    required String title,
    required String? parentId,
    required int servings,
    required List<Ingredient> ingredients,
    required String content,
    String? sourceUrl,
    int? durationMinutes,
  }) async {
    final wiki = ref.read(wikiRepositoryProvider);
    final id = await wiki.createPage(
      title: title,
      parentId: parentId,
      kind: PageKinds.recipe,
    );
    final page = await wiki.watchPage(id).firstWhere((row) => row != null);
    // The row was just created; `firstWhere` waited for it.
    if (page == null) return id;
    await wiki.updatePage(
      page,
      properties: recipeChanges(
        servings: Change(servings),
        ingredients: ingredients,
        sourceUrl: Change(sourceUrl),
        durationMinutes: Change(durationMinutes),
      ),
      content: content,
    );
    return id;
  }
}

/// What the server read from a recipe's address — for the review before taking it.
/// Keyed by the address.
@riverpod
class ParsedRecipeViewModel extends _$ParsedRecipeViewModel {
  @override
  Future<ParsedRecipe> build(String url) =>
      ref.watch(wikiRepositoryProvider).importRecipe(url);
}
