import 'package:flutter/material.dart';

import '../../../../../core/common/wire.dart';
import '../../../../../core/l10n/generated/app_localizations.dart';
import '../../../../../core/theme/hiwiski_symbols.dart';
import '../../../../../core/ui/info_property.dart';
import '../../../../../domain/wiki/wiki_models.dart';
import '../../../../../domain/wiki/wiki_page.dart';
import '../../page_view_model.dart';
import '../page_kind.dart';
import '../recipe/recipe_folder_head.dart';

/// An ordinary wiki page: Markdown, rendered in blocks (`TextPageBlocks`). A recipe
/// collection is one too — with its recipes as cards above the text.
class TextKindView extends PageKindView {
  const TextKindView();

  @override
  String get code => PageKinds.page;

  /// Everywhere but inside a recipe collection, which holds recipes and folders.
  @override
  String? offeredAs(L l, WikiNode? parent) =>
      parent?.isRecipeBranch ?? false ? null : l.wikiKindPage;

  @override
  IconData icon(WikiNode? parent) => HiwiskiSymbols.description;

  /// A page that has recipes below it shows as their collection.
  @override
  IconData treeIcon(WikiNode node) => node.isRecipeBranch
      ? HiwiskiSymbols.restaurant
      : HiwiskiSymbols.description;

  @override
  List<Widget> body(
    BuildContext context, {
    required WikiPage page,
    required PageState state,
    required bool writable,
  }) => const [];

  @override
  List<Widget> head(
    BuildContext context, {
    required WikiPage page,
    required PageState state,
    required PageKindActions actions,
  }) => [
    if (RecipeFolderHead.shows(page, state))
      RecipeFolderHead(page: page, state: state, actions: actions),
  ];

  @override
  List<Widget> properties(
    BuildContext context, {
    required WikiPage page,
    required String location,
    required VoidCallback? onMove,
  }) => [
    // Where the page sits — and the way to move it: tap the place.
    InfoProperty(label: L.of(context).wikiArea, value: location, onTap: onMove),
  ];

  @override
  PageKindDraft draft(WikiPage page) => PlainDraft();
}
