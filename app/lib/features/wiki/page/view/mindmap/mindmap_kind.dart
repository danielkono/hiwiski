import 'package:flutter/material.dart';

import '../../../../../core/common/wire.dart';
import '../../../../../core/l10n/generated/app_localizations.dart';
import '../../../../../core/theme/hiwiski_symbols.dart';
import '../../../../../core/ui/info_property.dart';
import '../../../../../domain/wiki/wiki_models.dart';
import '../../../../../domain/wiki/wiki_page.dart';
import '../../page_view_model.dart';
import '../page_kind.dart';
import 'mindmap_preview_card.dart';

/// A mind map: a page with a title and a text like any other, and below them a
/// picture of its canvas. The canvas opens full screen — read, moved around, and
/// edited there. Its elements and connections are items of their own, not
/// properties of the page.
class MindmapKindView extends PageKindView {
  const MindmapKindView();

  @override
  String get code => PageKinds.mindmap;

  /// Everywhere but inside a recipe collection, which holds recipes and folders.
  @override
  String? offeredAs(L l, WikiNode? parent) =>
      parent?.isRecipeBranch ?? false ? null : l.wikiNewMindmap;

  @override
  IconData icon(WikiNode? parent) => HiwiskiSymbols.hub;

  @override
  IconData treeIcon(WikiNode node) => HiwiskiSymbols.hub;

  /// The text, as on any page.
  @override
  List<Widget> body(
    BuildContext context, {
    required WikiPage page,
    required PageState state,
    required bool writable,
  }) => const [];

  @override
  List<Widget> tail(
    BuildContext context, {
    required WikiPage page,
    required PageState state,
    required PageKindActions actions,
  }) => [MindmapPreviewCard(page: page, state: state)];

  @override
  List<Widget> properties(
    BuildContext context, {
    required WikiPage page,
    required String location,
    required VoidCallback? onMove,
  }) => [
    InfoProperty(label: L.of(context).wikiArea, value: location, onTap: onMove),
  ];

  @override
  PageKindDraft draft(WikiPage page) => PlainDraft();
}
