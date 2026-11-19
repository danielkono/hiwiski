import 'package:flutter/material.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../domain/wiki/wiki_models.dart';
import '../../../../domain/wiki/wiki_page.dart';
import '../page_view_model.dart';
import 'recipe/recipe_folder_kind.dart';
import 'recipe/recipe_kind.dart';
import 'text/text_kind.dart';

/// What a kind of wiki page brings to the app.
///
/// The page screen is the same for every kind — header, editing the title and the
/// text, comments, info bar, archive and delete. What differs comes from here: how
/// it is offered in "New page" and shown in the tree, how the page reads, what its
/// info bar shows first, which fields editing adds above the text and how they are
/// saved, what sits docked below it. Its fields are properties of the page and travel
/// without a column of their own. **A new kind of page is one subclass in a folder
/// next to `text/` and `recipe/`, and a line in [all]** — see `docs/development/wiki-page-kinds.md`.
abstract class PageKindView {
  const PageKindView();

  /// Every kind this app knows, in the order "New page" offers them.
  static const all = <PageKindView>[
    TextKindView(),
    RecipeFolderKindView(),
    RecipeKindView(),
  ];

  /// The presentation of [page]'s kind; a kind this app does not know reads as text
  /// — its properties are kept all the same.
  factory PageKindView.of(WikiPage page) => all
      .where((kind) => kind.code == page.kind)
      .firstWhere((_) => true, orElse: () => const TextKindView());

  /// The page's `kind` this is the presentation of.
  String get code;

  /// What "New page" calls it below [parent] (`null`: at the root) — `null` where
  /// it is not offered there.
  String? offeredAs(L l, WikiNode? parent);

  /// Its symbol in "New page" below [parent].
  IconData icon(WikiNode? parent);

  /// Its symbol for [node] in the tree.
  IconData treeIcon(WikiNode node);

  /// What the page shows while it is read, whole — or nothing: it reads as text,
  /// rendered Markdown in blocks built as they come into view (`TextBlock`).
  List<Widget> body(
    BuildContext context, {
    required WikiPage page,
    required PageState state,
    required bool writable,
  });

  /// What stands above the text while it is read — a recipe collection's cards.
  List<Widget> head(
    BuildContext context, {
    required WikiPage page,
    required PageState state,
    required PageKindActions actions,
  }) => const [];

  /// The info bar's first rows: where the page sits, and what this kind adds.
  List<Widget> properties(
    BuildContext context, {
    required WikiPage page,
    required String location,
    required VoidCallback? onMove,
  });

  /// What stays docked below the page while it is read.
  List<Widget> dock(BuildContext context, {required WikiPage page}) => const [];

  /// The fields editing adds above the text, holding what is typed into them.
  PageKindDraft draft(WikiPage page);
}

/// What a page's head may do beyond reading: the shell's callbacks, `null` where the
/// reader may not or the page is a preview.
class const PageKindActions({
  required final bool preview,
  required final bool writable,

  /// Creates something below the page.
  final void Function(String parentId, String kind)? onCreate,

  /// A recipe from an address into the page.
  final ValueChanged<String>? onImport,
});

/// The fields a kind adds while editing — and what of them changed. A
/// [ChangeNotifier]: rows that come and go rebuild the editor.
abstract class PageKindDraft extends ChangeNotifier {
  /// The fields above the text.
  List<Widget> fields(BuildContext context);

  /// Saves [title] and [content] — what every page has, `null` when unchanged — with
  /// what this kind's fields changed against [base].
  Future<void> save(
    PageViewModel viewModel,
    WikiPage base, {
    required String? title,
    required String? content,
  });
}

/// A kind without fields of its own: only title and text.
class PlainDraft extends PageKindDraft {
  @override
  List<Widget> fields(BuildContext context) => const [];

  @override
  Future<void> save(
    PageViewModel viewModel,
    WikiPage base, {
    required String? title,
    required String? content,
  }) => viewModel.edit(base, title: title, content: content);
}
