import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/item_navigation.dart';
import '../../../core/ui/info_bar.dart';
import '../../../core/ui/notice_bar.dart';
import '../../../domain/common/item_ref.dart';
import '../../assignees/view/assignees_section.dart';
import '../../history/view/history_section.dart';
import '../../history/view/history_sections.dart';
import '../../links/view/references_section.dart';
import '../../sharing/view/share_summary_section.dart';
import '../../tags/view/tags_section.dart';
import '../item_info_view_model.dart';

/// An item's info area: what only this kind of item has comes in
/// from the screen as [properties] and [actions]; assignees, tags, sharing,
/// references, facts and history are the same everywhere and come from here.
class ItemInfo extends ConsumerWidget {
  const ItemInfo({
    super.key,
    required this.item,
    this.editable = false,
    this.properties = const [],
    this.actions = const [],
    this.versionView,
  });

  final ItemRef item;

  /// Whether the reader may change assignees and tags — the screen knows the level
  /// and whether the item is archived.
  final bool editable;

  /// The screen's own rows, on top: due date, repeat, list, calendar …
  final List<Widget> properties;

  /// The screen's own sections, last: delete, archive.
  final List<Widget> actions;

  /// A page's text has versions of its own ([HistorySection.versionView]).
  final HistoryVersionView? versionView;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(itemInfoViewModelProvider(item))
      .when(
        skipLoadingOnReload: true,
        // The screen's own properties and actions do not wait for the rest.
        loading: () => InfoBar(
          sections: [
            if (properties.isNotEmpty) _Properties(properties),
            ...actions,
          ],
        ),
        error: (error, _) => InfoBar(
          sections: [
            if (properties.isNotEmpty) _Properties(properties),
            NoticeBar.failure(context, error: error),
            ...actions,
          ],
        ),
        data: (state) => _ItemInfoBar(
          properties: properties,
          versionView: versionView,
          actions: actions,
          editable: editable,
          item: item,
          state: state,
        ),
      );
}

/// The screen's own properties, as the first section.
class _Properties extends StatelessWidget {
  const _Properties(this.properties);

  final List<Widget> properties;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: .stretch, children: properties);
}

class _ItemInfoBar extends ConsumerWidget {
  const _ItemInfoBar({
    required this.properties,
    required this.versionView,
    required this.actions,
    required this.editable,
    required this.item,
    required this.state,
  });

  final List<Widget> properties;

  final HistoryVersionView? versionView;
  final List<Widget> actions;
  final bool editable;
  final ItemRef item;
  final ItemInfoState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InfoBar(
      sections: [
        if (properties.isNotEmpty) _Properties(properties),
        if (state.assignees case final assignees?)
          AssigneesSection(
            assignees: assignees,
            onChanged: editable && state.assignable
                ? (assignees) => ref
                      .read(itemInfoViewModelProvider(item).notifier)
                      .setAssignees(assignees)
                : null,
          ),
        TagsSection(
          raw: state.tags ?? '',
          inherited: state.inheritedTags,
          inheritedFrom: state.inheritedFrom,
          onChanged: editable
              ? (tags) => ref
                    .read(itemInfoViewModelProvider(item).notifier)
                    .setTags(tags)
              : null,
        ),
        ShareSummarySection(item: item),
        if (state.references)
          ReferencesSections(
            item: item,
            onOpen: (target) => openLinkTarget(context, ref, target),
          ),
        ItemFactsSection(item: item),
        HistorySection(item: item, versionView: versionView),
        ...actions,
      ],
    );
  }
}
