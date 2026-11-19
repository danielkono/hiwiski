import 'package:flutter/material.dart';

import '../../../../../core/l10n/generated/app_localizations.dart';
import '../../../../../core/theme/hiwiski_symbols.dart';
import '../../../../../domain/wiki/wiki_models.dart';
import '../text/text_kind.dart';

/// A recipe collection — or, inside one, a folder: a page that reads as text, with
/// its recipes as cards above it (`RecipeFolderHead`).
class RecipeFolderKindView extends TextKindView {
  const RecipeFolderKindView();

  @override
  String get code => kindRecipeFolder;

  /// At the root and below a page a collection; inside a collection a folder.
  @override
  String? offeredAs(L l, WikiNode? parent) =>
      parent?.isRecipeBranch ?? false ? l.wikiNewFolder : l.wikiNewRecipeFolder;

  /// The collection itself is the recipes'; a folder inside it is a folder.
  @override
  IconData icon(WikiNode? parent) => parent == null || !parent.isRecipeBranch
      ? HiwiskiSymbols.restaurant
      : HiwiskiSymbols.folder;

  @override
  IconData treeIcon(WikiNode node) => node.page.parentId == null
      ? HiwiskiSymbols.restaurant
      : HiwiskiSymbols.folder;
}
