import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../components/rich_text/view/image_files.dart';
import '../../../../components/comments/view/comment_list.dart';
import '../../../../components/export/view/info_export_button.dart';
import '../../../../components/item_info/view/item_info.dart';
import '../../../../components/links/view/link_picker.dart';
import '../../../../components/rich_text/view/markdown_field.dart';
import '../../../../components/rich_text/view/markdown_text_controller.dart';
import '../../../../components/rich_text/view/markdown_toolbar.dart';
import '../../../../core/shell/breakpoints.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/ui/info_bar.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/ui/archive_ui.dart';
import '../../../../core/ui/info_archive_button.dart';
import '../../../../core/ui/info_delete_section.dart';
import '../../../../core/ui/keyboard_bar.dart';
import '../../../../core/ui/loading_strip.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../core/ui/text_insertion.dart';
import '../../../../domain/wiki/page_images.dart';
import '../../../../domain/common/item_ref.dart';
import '../../../../domain/wiki/wiki_page.dart';
import '../../view/mindmap/mindmap_picture.dart';
import '../../view/wiki_keys.dart';
import '../page_view_model.dart';
import 'page_actions.dart';
import 'move_sheet.dart';
import 'page_body.dart';
import 'page_kind.dart';
import 'revision_view.dart';
import 'text_length_notice.dart';

/// A wiki page: rendered Markdown, the comments below it, the info bar next to
/// it.
///
/// **The layout stays the same while editing**: the text becomes the field it is
/// written in — formatted, as it reads, or as its Markdown — and no second screen
/// opens for editing.
class PageScreen extends ConsumerStatefulWidget {
  const PageScreen({
    super.key,
    required this.page,
    this.onDeleted,
    this.onCreate,
    this.onImport,
    required this.actions,
  });

  /// Where the page reports editing and its buttons to: the header around the page
  /// shows them (see [PageActions]).
  final PageActions actions;

  final WikiPage page;

  /// Creates something below this page — for "New recipe" in an empty recipe collection.
  final void Function(String parentId, String kind)? onCreate;

  /// A recipe from an address into this page — offered in an empty recipe collection.
  final ValueChanged<String>? onImport;

  final VoidCallback? onDeleted;

  @override
  ConsumerState<PageScreen> createState() => _PageScreenState();
}

class _PageScreenState extends ConsumerState<PageScreen> {
  final _content = MarkdownTextController();
  final _title = TextEditingController();
  bool _editing = false;

  final _contentFocus = FocusNode();

  /// What the page's kind adds to editing beyond title and text — a recipe's
  /// servings, time, source and ingredients (`PageKindView.draft`).
  PageKindDraft? _draft;

  /// The state the edit starts from. Saving goes against it, not against
  /// `widget.page`: if another member's change comes in meanwhile, the mutation would
  /// otherwise carry their version as `baseVersion` — the server would see no conflict
  /// and silently overwrite.
  late WikiPage _base = widget.page;

  /// Held from the start: "saved on leaving" saves in `dispose`, and there `ref` may
  /// no longer be used — Riverpod threw, and what was typed was lost.
  late PageViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = ref.read(pageViewModelProvider(widget.page.id).notifier);
    _load();
  }

  @override
  void didUpdateWidget(PageScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.id != widget.page.id) {
      // On a page change, first save what was typed: a click in the tree must not
      // cost any work.
      if (_editing) _save();
      // No setState: a build follows didUpdateWidget anyway.
      _editing = false;
      _viewModel = ref.read(pageViewModelProvider(widget.page.id).notifier);
      _load();
    }
  }

  void _load() {
    _base = widget.page;
    _content.text = widget.page.content;
    _title.text = widget.page.title;
    _draft?.dispose();
    _draft = PageKindView.of(widget.page).draft(widget.page)
      ..addListener(_draftChanged);
  }

  /// How often a row of the kind's fields came or went — each time the editor is
  /// built again.
  int _draftRevision = 0;

  void _draftChanged() => setState(() => _draftRevision++);

  /// Only take over the current state when the editor opens: whatever another member
  /// has saved in the meantime then shows up in the source too.
  /// Tells the header around the page what to show — after the frame, as the header is
  /// built in the same one.
  void _report({required bool writable, required bool archived}) {
    final actions = widget.actions;
    final editing = _editing;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      actions.report(
        editing: editing,
        writable: writable,
        archived: archived,
        onEdit: _startEditing,
        onDone: _done,
        onCancel: _cancel,
      );
    });
  }

  /// Leaves the editor without saving: the page reads as it did before "Edit".
  void _cancel() => setState(() {
    _editing = false;
    _load();
  });

  Future<void> _done() async {
    // Images still being added go into the text first, or they would be left out.
    await _content.imagesAdded;
    // Done or cancelled meanwhile — a second tap while waiting, for one.
    if (!mounted || !_editing) return;
    _save();
    setState(() => _editing = false);
  }

  void _startEditing() {
    _load();
    setState(() => _editing = true);
  }

  @override
  void dispose() {
    try {
      // "Saved on leaving".
      if (_editing) _save();
    } finally {
      widget.actions.withdraw();
      _content.dispose();
      _contentFocus.dispose();
      _title.dispose();
      _draft?.dispose();
      super.dispose();
    }
  }

  void _save() {
    // Only what changed goes out — a field nobody touched must not overwrite what
    // someone else changed meanwhile.
    final title = _title.text.trim();
    final saved = _draft?.save(
      _viewModel,
      _base,
      // An emptied title is not saved: the page would have no name in the tree,
      // the breadcrumb and every link to it.
      title: title.isNotEmpty && title != _base.title ? title : null,
      content: _content.text != _base.content ? _content.text : null,
    );
    // Written on the device; nothing in it waits for the server, and `dispose`
    // cannot wait at all. A text beyond the server's limit is written too, and its
    // change waits on the device until it is shorter.
    if (saved != null) unawaited(saved);
  }

  /// The **link picker**.
  ///
  /// It inserts the address, never the number: otherwise an item just created offline
  /// could not be linked, and that is exactly the common case.
  /// Pictures into the text: picked, kept on the device for the page, and put at the
  /// cursor on lines of their own — several at once are one group, shown as a stack.
  /// They go up with the sync; nothing here waits for the server.
  /// Through the text's controller: "Done" waits until they are in the text.
  Future<void> _addImages() => _content.addImages(_images);

  Future<void> _images() async {
    final l = L.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final page = widget.page;
    try {
      final ids = await addContentImagesMutation.run(ref, (tsx) async {
        final viewModel = tsx.get(pageViewModelProvider(page.id).notifier);
        final files = await pickImageFiles();
        return files.isEmpty
            ? const <String>[]
            : viewModel.addContentImages(page, files);
      });
      if (ids.isEmpty || !mounted) return;
      final at = _content.selection.isValid
          ? _content.selection.start
          : _content.text.length;
      insertAtCursor(_content, imagesInsertion(_content.text, at, ids));
    } on Object catch (error) {
      // Not the server's answer: a picture that could not be read. It used to end
      // the attempt without a word.
      debugPrint('hiwiski: images not added: $error');
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l.wikiImagesFailed)));
    }
    if (mounted) _contentFocus.requestFocus();
  }

  /// The cursor to the end of the text, and the keyboard up.
  void _writeAtEnd() {
    _content.selection = TextSelection.collapsed(offset: _content.text.length);
    _contentFocus.requestFocus();
  }

  Future<void> _link() async {
    final markdown = await showLinkPicker(context);
    if (markdown != null) insertAtCursor(_content, markdown);
    // The picker took the focus; the text gets it back either way.
    if (mounted) _contentFocus.requestFocus();
  }

  /// Archives the page — and asks first whether its subpages go along, if it has any.
  Future<void> _archive() async {
    final page = widget.page;
    final subpages =
        ref
            .read(pageViewModelProvider(page.id))
            .value
            ?.subpages(archived: false) ??
        0;
    final withSubpages = subpages == 0
        ? false
        : await askWithSubpages(context, subpages: subpages, restore: false);
    if (withSubpages == null || !mounted) return;
    if (_editing) {
      _save();
      setState(() => _editing = false);
    }
    final archived = await archivePageMutation.run(
      ref,
      (tsx) => tsx
          .get(pageViewModelProvider(page.id).notifier)
          .archive(page, withSubpages: withSubpages),
    );
    if (!mounted) return;
    showArchivedSnackBar(
      context,
      onUndo: () => _viewModel.restorePages(archived),
    );
  }

  Future<void> _restore() async {
    final page = widget.page;
    final subpages =
        ref
            .read(pageViewModelProvider(page.id))
            .value
            ?.subpages(archived: true) ??
        0;
    final withSubpages = subpages == 0
        ? false
        : await askWithSubpages(context, subpages: subpages, restore: true);
    if (withSubpages == null) return;
    await _viewModel.restore(page, withSubpages: withSubpages);
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(pageViewModelProvider(widget.page.id))
      .when(
        skipLoadingOnReload: true,
        // At the top edge: the page fills the room it is given, and a strip left to
        // fill it too flashed over the whole page on every change of page.
        loading: () => const Align(
          alignment: .topCenter,
          child: LoadingStrip(loading: true),
        ),
        error: (error, _) => Align(
          alignment: Alignment.topCenter,
          child: NoticeBar.failure(context, error: error),
        ),
        // Gone: the area closes it (`onDeleted`).
        data: (state) {
          if (state == null) return const SizedBox.shrink();
          final l = L.of(context);
          final trail = state.trail;

          final wide = InfoBar.besideContent(context);
          final padding = Breakpoint.of(context).pagePadding;
          final page = widget.page;
          final kind = PageKindView.of(page);
          // With a keyboard on the screen the insert bar docks on top of it — above the text
          // it would scroll away with the first lines.
          final dockToolbar = typesOnScreen();
          final imagesBusy = ref.watch(addContentImagesMutation).isPending;
          // An archived page is read-only.
          final archived = page.archivedAt != null;
          // On *read* there is nothing to edit — not even the tags.
          final mayChange = state.mayChange;
          final writable = mayChange && !archived;
          final location = trail.length > 1
              ? trail.take(trail.length - 1).map((p) => p.title).join(' › ')
              : l.wikiMoveRoot;
          void move() => showMoveSheet(context, page: page);
          final infoBar = ItemInfo(
            item: ItemRef.wikiPage(widget.page.id),
            editable: writable,
            properties: kind.properties(
              context,
              page: page,
              location: location,
              onMove: state.mayMove ? move : null,
            ),
            actions: [
              // Delete stays possible on an archived page: into the trash, still archived.
              // Export is everyone's who can read the page.
              if (state.mayDelete)
                InfoDeleteSection(
                  besides: [
                    InfoExportButton(
                      item: ItemRef.wikiPage(widget.page.id),
                      drawMindmap: mindmapDrawingOf,
                    ),
                    if (!archived)
                      InfoArchiveButton(
                        label: l.wikiArchive,
                        onArchive: _archive,
                      ),
                  ],
                  label: l.wikiDelete,
                  confirmTitle: l.wikiDelete,
                  confirmBody: l.wikiDeleteBody,
                  onDelete: () async {
                    // The selection goes before the page does: the tree may drop
                    // it before the delete returns, and a selected page missing
                    // from the tree reads as deleted by someone else.
                    final deleting = _viewModel.delete(widget.page);
                    widget.onDeleted?.call();
                    await deleting;
                  },
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: InfoExportButton(
                    item: ItemRef.wikiPage(widget.page.id),
                    drawMindmap: mindmapDrawingOf,
                  ),
                ),
            ],
            versionView: (revisionId) => RevisionView(
              page: widget.page,
              revisionId: revisionId,
              canRestore: writable,
            ),
          );

          _report(writable: writable, archived: archived);

          return Row(
            crossAxisAlignment: .stretch,
            children: [
              Expanded(
                // As wide as a list and at the left like one: the text starts
                // under the title in the header, whatever the window's width.
                child: Align(
                  alignment: .topLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth:
                          HiwiskiMetrics.contentMaxWidth + padding.horizontal,
                    ),
                    child: Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        Expanded(
                          // Slivers: a long page is rendered in blocks, built as they
                          // come into view (PageBody.sliver).
                          child: CustomScrollView(
                            slivers: [
                              SliverPadding(
                                padding: .only(
                                  left: padding.left,
                                  right: padding.right,
                                  bottom: HiwiskiMetrics.space32,
                                ),
                                sliver: SliverMainAxisGroup(
                                  slivers: [
                                    if (_editing)
                                      SliverList.list(
                                        children: [
                                          _TitleField(controller: _title),
                                          ...?_draft?.fields(context),
                                          if (!dockToolbar) ...[
                                            MarkdownToolbar(
                                              controller: _content,
                                              focusNode: _contentFocus,
                                              onLink: _link,
                                              onImages: _addImages,
                                              imagesBusy: imagesBusy,
                                            ),
                                            const SizedBox(
                                              height: HiwiskiMetrics.space8,
                                            ),
                                          ],
                                          MarkdownField(
                                            controller: _content,
                                            focusNode: _contentFocus,
                                            fieldKey: WikiKeys.wikiContent,
                                            dockedBelow: dockToolbar
                                                ? KeyboardBar.height
                                                : 0,
                                            decoration: const InputDecoration(
                                              border: .none,
                                            ),
                                          ),
                                          TextLengthNotice(
                                            controller: _content,
                                          ),
                                        ],
                                      )
                                    else
                                      PageBody(
                                        page: page,
                                        onCreate: widget.onCreate,
                                        onImport: widget.onImport,
                                        onRestore: mayChange ? _restore : null,
                                        sliver: true,
                                      ),
                                    // While the text is written it is the page:
                                    // comments and the info area below it made
                                    // it long, and every line typed scrolled it.
                                    if (!_editing)
                                      SliverList.list(
                                        children: [
                                          const SizedBox(
                                            height: HiwiskiMetrics.space32,
                                          ),
                                          CommentList(
                                            item: ItemRef.wikiPage(
                                              widget.page.id,
                                            ),
                                            readOnly: archived,
                                          ),
                                          // On phone and tablet the info bar sits below
                                          // the content, on desktop as a column next
                                          // to it.
                                          if (!wide) infoBar,
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                              // The text reaches down to the bottom: a tap below
                              // it writes on at its end, as on a sheet of paper,
                              // instead of landing beside a box.
                              if (_editing)
                                SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: GestureDetector(
                                    key: WikiKeys.wikiContentBelow,
                                    behavior: .opaque,
                                    onTap: _writeAtEnd,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Only while the text has the focus: the bar inserts into the text,
                        // not into the title or the servings. And while pictures go up:
                        // the picker took the focus and the keyboard with it, and the
                        // bar's spinner was the only sign that anything was happening.
                        if (_editing && dockToolbar)
                          ListenableBuilder(
                            listenable: _contentFocus,
                            builder: (context, _) =>
                                _contentFocus.hasFocus || imagesBusy
                                ? KeyboardBar(
                                    child: MarkdownToolbar(
                                      controller: _content,
                                      focusNode: _contentFocus,
                                      onLink: _link,
                                      onImages: _addImages,
                                      imagesBusy: imagesBusy,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        // What the kind docks below the page while it is read.
                        if (!_editing) ...kind.dock(context, page: page),
                      ],
                    ),
                  ),
                ),
              ),
              if (wide) infoBar,
            ],
          );
        },
      );
}

/// The page's title as a field, above its text while it is edited. Read, the title —
/// with the number, the pages above it and "Edit" — is in the header around the page.
class _TitleField extends StatelessWidget {
  const _TitleField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .only(
      top: HiwiskiMetrics.space8,
      bottom: HiwiskiMetrics.space16,
    ),
    child: TextField(
      key: WikiKeys.wikiTitle,
      controller: controller,
      decoration: InputDecoration(labelText: L.of(context).wikiPageTitle),
    ),
  );
}
