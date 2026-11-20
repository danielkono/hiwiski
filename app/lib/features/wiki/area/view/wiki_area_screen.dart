import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../components/import/view/import_button.dart';
import '../../../../core/ui/panel_reopen.dart';
import '../../../../core/ui/panel_reopen_corner.dart';
import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/item_navigation.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/shell/breakpoints.dart';
import '../../../../core/ui/content_width.dart';
import '../../../../core/ui/embedded_page.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/ui/archive_ui.dart';
import '../../../../core/ui/edit_actions.dart';
import '../../page/view/page_actions.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/page_header.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../../../core/ui/states.dart';
import '../../../../domain/wiki/page_moves.dart';
import '../../page/view/page_kind.dart';
import '../../page/view/page_screen.dart';
import '../../recipe_import/view/recipe_import_sheet.dart';
import '../../view/wiki_keys.dart';
import '../wiki_area_view_model.dart';
import 'wiki_tree.dart';

/// The wiki area.
///
/// **On desktop side by side**: page tree 280 wide with a line on the right, the article
/// next to it. **On the phone the tree is the area screen**; a page opens as its own
/// screen.
class WikiAreaScreen extends ConsumerStatefulWidget {
  const WikiAreaScreen({super.key, this.initialPageId});

  /// The page the area opens with — from `/wiki?pageId=…`.
  ///
  /// That is the jump from a reference chip: "A tap takes you there".
  final String? initialPageId;

  @override
  ConsumerState<WikiAreaScreen> createState() => _WikiAreaScreenState();
}

class _WikiAreaScreenState extends ConsumerState<WikiAreaScreen> {
  String? _selectedId;

  /// The page tree on desktop can be collapsed (`left_panel_close/open`).
  bool _treeOpen = true;

  /// What the open page reports for the header — on the phone it shows "Edit" there.
  final _pageActions = PageActions();

  @override
  void dispose() {
    _pageActions.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialPageId;
  }

  @override
  void didUpdateWidget(WikiAreaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A second jump to the same area does not rebuild the screen, it updates
    // it -- without this the first page would stay open.
    final wanted = widget.initialPageId;
    // No setState: a build follows didUpdateWidget anyway.
    if (wanted != oldWidget.initialPageId && wanted != _selectedId) {
      _selectedId = wanted;
    }
  }

  /// Opens a page — **in the address too**, so a reload comes back to it instead of
  /// the first page of the tree. `null` closes it (back to the tree on the phone).
  ///
  /// **On the phone a page is laid on top**, as a screen of its own: the system's
  /// "Back" and the swipe from the edge return to the tree — or to the page it was
  /// opened from — and the tree below keeps where it was scrolled and what was open.
  /// Replacing the screen left nothing to go back to.
  void _select(String? id) {
    if (Breakpoint.of(context).isCompact) {
      if (id == null && canGoBack(context)) {
        goBack(context, () {});
        return;
      }
      if (id != null && id != _selectedId) {
        // The pushed screen lives until it is popped; nothing waits for that.
        unawaited(WikiRoute(pageId: id).push<void>(context));
        return;
      }
    }
    setState(() => _selectedId = id);
    if (widget.initialPageId != id) WikiRoute(pageId: id).go(context);
  }

  /// Something new under [parentId] — the dialog asks for the title **and the kind**:
  /// a page or a recipe collection, under a recipe branch a recipe or a folder.
  /// [kind] preselects one ("New recipe" in an empty collection).
  Future<void> _create(String? parentId, [String? kind]) async {
    final l = L.of(context);
    final parent = parentId == null
        ? null
        : ref.read(wikiAreaViewModelProvider).value?.node(parentId);
    // What may go here, as the kinds say themselves (`PageKindView.offeredAs`).
    final kinds = {
      for (final kind in PageKindView.all)
        if (kind.offeredAs(l, parent) case final label?)
          kind.code: (label: label, icon: kind.icon(parent)),
    };
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => _NewPageDialog(
        title: parent == null
            ? l.wikiNewPage
            : l.wikiCreateIn(parent.page.title),
        kinds: kinds,
        initialKind: switch (kind) {
          final kind? when kinds.containsKey(kind) => kind,
          _ => kinds.keys.first,
        },
      ),
    );
    if (result == null) return;
    final (title, chosen) = result;
    final id = await createPageMutation.run(
      ref,
      (tsx) => tsx
          .get(wikiAreaViewModelProvider.notifier)
          .create(title: title, parentId: parentId, kind: chosen),
    );
    if (!mounted) return;
    await _untilInTree(id);
    if (mounted) _select(id);
  }

  /// How long a new page may take to reach the tree before it is opened anyway.
  static const _treeCatchUp = Duration(seconds: 5);

  /// Until the tree holds [id]. A page just created reaches the tree through the
  /// database's stream a moment later — on a slow phone or in the browser more than
  /// a frame later — and selected before that, it read as gone: "This no longer
  /// exists", and back to the tree.
  Future<void> _untilInTree(String id) async {
    final there = Completer<void>();
    final subscription = ref.listenManual(wikiAreaViewModelProvider, (_, next) {
      if (next.value?.pageById(id) != null && !there.isCompleted) {
        there.complete();
      }
    }, fireImmediately: true);
    try {
      await there.future.timeout(_treeCatchUp, onTimeout: () {});
    } finally {
      subscription.close();
    }
  }

  /// A page dropped in the tree; a drop the member's level does not allow says so.
  Future<void> _drop(String id, String targetId, DropZone zone) async {
    final messenger = ScaffoldMessenger.of(context);
    final notAllowed = L.of(context).wikiMoveNotAllowed;
    final outcome = await dropPageMutation.run(
      ref,
      (tsx) =>
          tsx.get(wikiAreaViewModelProvider.notifier).drop(id, targetId, zone),
    );
    if (outcome == .notAllowed) {
      messenger.showSnackBar(SnackBar(content: Text(notAllowed)));
    }
  }

  void _import(String? targetId) =>
      showRecipeImportSheet(context, targetId: targetId, onCreated: _select);

  @override
  Widget build(BuildContext context) {
    final header = PageHeader(title: L.of(context).wikiTitle);
    return ref
        .watch(wikiAreaViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          // **No screen counts as done while one of the states is missing**
          // — and the error state is the one you overlook while
          // building and find again as an empty area when running it.
          error: (error, _) => HiwiskiPage.error(
            header: header,
            error: error,
            onRetry: () => ref.read(wikiAreaViewModelProvider.notifier).retry(),
          ),
          data: _page,
        );
  }

  Widget _page(WikiAreaState state) {
    final l = L.of(context);
    final tree = state.tree;
    final compact = Breakpoint.of(context).isCompact;

    // On desktop there is always a page next to the tree — without a
    // selection the first root, instead of an empty area.
    if (_selectedId == null && !compact && tree.isNotEmpty) {
      _selectedId = tree.first.page.id;
    }

    final selected = switch (_selectedId) {
      null => null,
      final selectedId => state.pageById(selectedId),
    };

    // A deleted page must not remain as an empty frame — and whoever came by a link,
    // or had it open while it went elsewhere, learns why they are back at the tree.
    if (_selectedId case final gone? when selected == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Deleted or archived here, the selection is cleared before this frame
        // ends — then there is nothing to explain.
        if (!mounted || _selectedId != gone) return;
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(l.stateGone)));
        _select(null);
      });
    }

    // "Above it the tag filter bar."
    final tree_ = WikiTree(
      nodes: state.shown,
      groupShared: state.groupShared,
      selectedId: _selectedId,
      onSelect: (page) => _select(page.id),
      onCreate: _create,
      onImport: state.canImport ? _import : null,
      movable: state.movable,
      onDrop: _drop,
      expanded: state.expanded,
      onExpandedChanged: (expanded) =>
          ref.read(wikiAreaViewModelProvider.notifier).setExpanded(expanded),
    );

    // One button for the whole tree: everything open, or everything closed again.
    final toggleAll = state.expandable.isEmpty
        ? null
        : IconButton(
            key: WikiKeys.treeToggleAll,
            icon: Icon(
              state.allExpanded
                  ? HiwiskiSymbols.unfoldLess
                  : HiwiskiSymbols.unfoldMore,
            ),
            tooltip: state.allExpanded ? l.wikiCollapseAll : l.wikiExpandAll,
            onPressed: () => state.allExpanded
                ? ref.read(wikiAreaViewModelProvider.notifier).collapseAll()
                : ref.read(wikiAreaViewModelProvider.notifier).expandAll(state),
          );

    // The tree put away: its button goes left of the page's title.
    final showTree = _treeOpen
        ? null
        : IconButton(
            icon: const Icon(HiwiskiSymbols.leftPanelOpen),
            tooltip: l.wikiTreeShow,
            onPressed: () => setState(() => _treeOpen = true),
          );

    // On the phone a page is a screen of its own, and the filter bar steps aside.
    final pageOpen = compact && selected != null;

    // The open page's own header: title, number, the pages above it as links, and
    // "Edit" — as a list has it. On the phone it is the screen's header; beside the
    // tree it stands under the area's, which keeps saying "Wiki" as the tasks' area
    // keeps saying "Tasks" above an open list.
    final pageHeader = selected == null
        ? null
        : PageHeader(
            title: selected.title,
            // Created offline, a page has no number yet, and the dash says so.
            entityKey: selected.entityKey ?? l.todoNoKey,
            crumbs: [
              for (final step in state.trailOf(selected))
                HeaderCrumb(label: step.title, onTap: () => _select(step.id)),
            ],
            // Opened from a link, "Back" returns there; on the phone otherwise from
            // the page to the tree.
            onBack: switch ((canGoBack(context), pageOpen)) {
              (true, _) => () => goBack(context, () {}),
              (false, true) => () => _select(null),
              (false, false) => null,
            },
            trailing: [
              ListenableBuilder(
                listenable: _pageActions,
                builder: (context, _) => _PageButtons(actions: _pageActions),
              ),
            ],
          );

    final body = switch ((compact, selected)) {
      // Only archived pages left counts as empty: the tree has nothing to show.
      (_, null) when state.empty => EmptyState(
        icon: HiwiskiSymbols.menuBook,
        message: l.wikiEmpty,
        actionLabel: l.wikiNewPage,
        onAction: () => _create(null, PageKinds.page),
      ),
      // On the phone: the tree is the area screen, the page lies on top of it.
      (true, final page?) => PageScreen(
        page: page,
        actions: _pageActions,
        onDeleted: () => _select(null),
        onCreate: _create,
        onImport: state.canImport ? _import : null,
      ),
      (true, _) => tree_,
      (false, final page) => Row(
        crossAxisAlignment: .stretch,
        children: [
          if (_treeOpen) ...[
            Container(
              width: HiwiskiMetrics.treeWidth + HiwiskiMetrics.space32,
              padding: const .only(right: HiwiskiMetrics.space8),
              child: Column(
                crossAxisAlignment: .stretch,
                children: [
                  // The button first: put away, the tree leaves the one that brings
                  // it back at the same place, left of the page's title.
                  Padding(
                    padding: const .only(left: PanelReopen.inset),
                    child: Row(
                      spacing: HiwiskiMetrics.space4,
                      children: [
                        IconButton(
                          icon: const Icon(HiwiskiSymbols.leftPanelClose),
                          tooltip: l.wikiTreeHide,
                          onPressed: () => setState(() => _treeOpen = false),
                        ),
                        Expanded(
                          child: Text(
                            l.wikiPages,
                            style: context.texts.labelLarge?.copyWith(
                              color: context.scheme.onSurfaceVariant,
                              fontWeight: .w600,
                            ),
                          ),
                        ),
                        ?toggleAll,
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const .only(
                        left: HiwiskiMetrics.space32 - HiwiskiMetrics.space4,
                      ),
                      child: tree_,
                    ),
                  ),
                ],
              ),
            ),
            VerticalDivider(
              width: HiwiskiMetrics.hairline,
              color: context.tokens.divider,
            ),
          ],
          Expanded(
            child: switch (page) {
              null => PanelReopenCorner(
                button: showTree,
                inset: PanelReopen.inset,
                child: EmptyState(
                  icon: HiwiskiSymbols.menuBook,
                  message: l.wikiEmpty,
                ),
              ),
              final page => PanelReopen(
                button: showTree,
                // Measured here, beside the tree: whether the info bar fits next to
                // the article depends on what the tree leaves.
                child: ContentWidth(
                  child: Column(
                    crossAxisAlignment: .stretch,
                    children: [
                      // Inside this screen: no second avatar, no arrow back.
                      if (pageHeader != null) EmbeddedPage(child: pageHeader),
                      Expanded(
                        child: PageScreen(
                          page: page,
                          actions: _pageActions,
                          onDeleted: () => _select(null),
                          onCreate: _create,
                          onImport: state.canImport ? _import : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            },
          ),
        ],
      ),
    };

    return HiwiskiPage(
      header: switch (pageHeader) {
        // On the phone the open page is the screen, and the header is its own.
        final pageHeader? when pageOpen => pageHeader,
        _ => PageHeader(
          title: l.wikiTitle,
          // On the phone the tree is the screen: its button sits in the header.
          trailing: [
            const ImportButton(place: .wiki),
            if (compact) ?toggleAll,
          ],
        ),
      },
      filter: TagPageFilter(
        tags: state.tags,
        selected: state.filter,
        onToggle: (id) =>
            ref.read(wikiAreaViewModelProvider.notifier).toggleTag(id),
        onClear: () => ref.read(wikiAreaViewModelProvider.notifier).clearTags(),
        visible: !pageOpen,
      ),
      body: body,
      // **Something new is always the floating button**, bottom right and labelled —
      // a list among the tasks, an event in the calendar, a page here. The wiki had
      // a text button at the end of its tree instead, below everything else. An empty
      // wiki offers it in the middle of the screen; a page open on the phone or being
      // edited has the room to itself.
      //
      // The Scaffold's slot always holds a widget, and the button appears and
      // disappears inside it, with no transition, like the tree and the page next to
      // it. If the slot itself were filled or emptied, the Scaffold would scale the
      // button in or out, and also rotate it, because it cannot tell that the widget
      // in the slot is a labelled button.
      floatingActionButton: ListenableBuilder(
        listenable: _pageActions,
        builder: (context, _) => state.empty || pageOpen || _pageActions.editing
            ? const SizedBox.shrink()
            : FloatingActionButton.extended(
                key: WikiKeys.newPage,
                onPressed: () => _create(null, PageKinds.page),
                icon: const Icon(HiwiskiSymbols.add),
                label: Text(l.wikiNewPage),
              ),
      ),
    );
  }
}

/// Title and kind of a new page. Returns `(title, kind)`.
class _NewPageDialog extends StatefulWidget {
  const _NewPageDialog({
    required this.title,
    required this.kinds,
    required this.initialKind,
  });

  final String title;

  /// Kind → label and symbol, in the order offered.
  final Map<String, ({String label, IconData icon})> kinds;
  final String initialKind;

  @override
  State<_NewPageDialog> createState() => _NewPageDialogState();
}

class _NewPageDialogState extends State<_NewPageDialog> {
  final _controller = TextEditingController();
  late String _kind = widget.initialKind;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop((title, _kind));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Text(l.wikiNewKind, style: context.tokens.text.sectionLabel),
          const SizedBox(height: HiwiskiMetrics.space8),
          SegmentedButton<String>(
            key: WikiKeys.newPageKind,
            segments: [
              for (final MapEntry(:key, value: (:label, :icon))
                  in widget.kinds.entries)
                ButtonSegment(value: key, label: Text(label), icon: Icon(icon)),
            ],
            selected: {_kind},
            showSelectedIcon: false,
            onSelectionChanged: (value) =>
                setState(() => _kind = value.firstOrNull ?? _kind),
          ),
          const SizedBox(height: HiwiskiMetrics.space16),
          TextField(
            key: WikiKeys.newPageTitle,
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(labelText: l.wikiPageTitle),
            onSubmitted: (_) => _done(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        // "Create" for something new, "Save" for a change.
        FilledButton(onPressed: _done, child: Text(l.actionCreate)),
      ],
    );
  }
}

/// "Edit" — or "Cancel" and "Save" while editing — and the archived chip, in the header
/// of a page: where a task and an event have them.
class _PageButtons extends StatelessWidget {
  const _PageButtons({required this.actions});

  final PageActions actions;

  @override
  Widget build(BuildContext context) {
    final onDone = actions.onDone;
    final onEdit = actions.onEdit;
    final onCancel = actions.onCancel;
    return Row(
      mainAxisSize: .min,
      spacing: HiwiskiMetrics.space8,
      children: [
        if (actions.archived) const ArchivedChip(),
        if (actions.writable &&
            onEdit != null &&
            onDone != null &&
            onCancel != null)
          EditActions(
            editing: actions.editing,
            onEdit: onEdit,
            onSave: onDone,
            onCancel: onCancel,
          ),
      ],
    );
  }
}
