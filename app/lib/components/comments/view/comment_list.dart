import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/item_navigation.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/delete_hold_button.dart';
import '../../../core/ui/notice_bar.dart';
import '../../../core/ui/removable_row.dart';
import '../../../core/ui/text_insertion.dart';
import '../../../core/ui/undo_snack_bar.dart';
import '../../../domain/common/item_ref.dart';
import '../../../domain/common/uuid_time.dart';
import '../../../domain/links/link_index.dart';
import '../../../domain/wiki/comment.dart';
import '../../links/view/link_picker.dart';
import '../../links/view/linked_text.dart';
import '../../links/view/reference_autocomplete.dart';
import '../../member_avatar/view/member_avatar.dart';
import '../comments_view_model.dart';
import 'comments_keys.dart';

/// The comments on an item.
///
/// **On all items, not just wiki pages**: also on tasks, events, lists and
/// calendars. That is why the component takes an [ItemRef] and knows no domain type.
///
/// Flat, no replies. Whoever may read may comment; one's own comments can be
/// edited and deleted.
class CommentList extends ConsumerStatefulWidget {
  const CommentList({super.key, required this.item, this.readOnly = false});

  final ItemRef item;

  /// The comments of an archived item are shown, not added to or removed.
  final bool readOnly;

  @override
  ConsumerState<CommentList> createState() => _CommentListState();
}

class _CommentListState extends ConsumerState<CommentList> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty) return;
    _input.clear();
    await ref.read(commentsViewModelProvider(widget.item).notifier).add(body);
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(commentsViewModelProvider(widget.item))
      .when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (error, _) => NoticeBar.failure(context, error: error),
        data: _list,
      );

  void _deleted(Comment comment) {
    final l = L.of(context);
    ref.read(commentsViewModelProvider(widget.item).notifier).delete(comment);
    // The row is gone when "Undo" comes: it goes through the container, which
    // outlives it.
    final container = ProviderScope.containerOf(context, listen: false);
    final item = widget.item;
    showUndoSnackBar(
      context,
      message: l.commentDeleted,
      onUndo: () => container
          .read(commentsViewModelProvider(item).notifier)
          .undoDelete(comment.id),
    );
  }

  Widget _list(CommentsState state) {
    final l = L.of(context);
    final comments = state.comments;
    final members = state.authors;
    final me = state.me;

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(
          l.wikiComments(comments.length),
          style: context.tokens.text.sectionLabel,
        ),
        const SizedBox(height: HiwiskiMetrics.space12),
        for (final comment in comments)
          // One's own comment is deleted like a task from its row: hold the symbol,
          // the row slides away, "Undo" brings it back. Others' have no symbol.
          RemovableRow(
            key: ValueKey(comment.id),
            onRemoved: () => _deleted(comment),
            child: _Comment(
              // Keyed: a comment being edited keeps its state when one above it
              // goes.
              key: ValueKey(comment.id),
              comment: comment,
              author: members[comment.ownerId],
              mine: comment.ownerId == me && !widget.readOnly,
              onEdit: (body) => ref
                  .read(commentsViewModelProvider(widget.item).notifier)
                  .edit(comment, body),
              onOpen: (target) => openLinkTarget(context, ref, target),
            ),
          ),
        const SizedBox(height: HiwiskiMetrics.space8),
        if (!widget.readOnly)
          Row(
            children: [
              Expanded(
                child: ReferenceAutocomplete(
                  controller: _input,
                  focusNode: _inputFocus,
                  child: TextField(
                    key: CommentsKeys.commentInput,
                    controller: _input,
                    focusNode: _inputFocus,
                    decoration: InputDecoration(
                      hintText: l.wikiCommentHint,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              // The same link picker as in the editor: it inserts the address, so an item
              // created offline can be linked as well.
              IconButton(
                icon: const Icon(HiwiskiSymbols.link),
                tooltip: l.wikiLinkInsert,
                onPressed: () async {
                  final markdown = await showLinkPicker(context);
                  if (markdown != null) insertAtCursor(_input, markdown);
                },
              ),
              IconButton(
                icon: const Icon(HiwiskiSymbols.send),
                tooltip: L.of(context).commentSend,
                onPressed: _send,
              ),
            ],
          ),
      ],
    );
  }
}

class _Comment extends StatefulWidget {
  const _Comment({
    super.key,
    required this.comment,
    required this.author,
    required this.mine,
    required this.onEdit,
    required this.onOpen,
  });

  final Comment comment;
  final dynamic author;
  final bool mine;

  /// Saves one's own comment with the new body.
  final ValueChanged<String> onEdit;

  /// A reference in the comment — `#TD-14` or a picked link — opens its target, as
  /// everywhere else a text can hold one.
  final ValueChanged<LinkItem> onOpen;

  @override
  State<_Comment> createState() => _CommentState();
}

class _CommentState extends State<_Comment> {
  /// While one's own comment is being edited: its text, otherwise `null`.
  TextEditingController? _editor;
  final _editorFocus = FocusNode();

  @override
  void dispose() {
    _editor?.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() => _editor = TextEditingController(text: widget.comment.body));
    _editorFocus.requestFocus();
  }

  void _stopEditing() {
    final editor = _editor;
    setState(() => _editor = null);
    // After the frame: the field still holds the controller until it is gone.
    WidgetsBinding.instance.addPostFrameCallback((_) => editor?.dispose());
  }

  void _save() {
    final body = _editor?.text.trim() ?? '';
    // Emptying a comment is not deleting it: that has its own button.
    if (body.isNotEmpty && body != widget.comment.body) widget.onEdit(body);
    _stopEditing();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).toString();
    final author = widget.author;
    final editor = _editor;
    return Padding(
      padding: const .only(bottom: HiwiskiMetrics.space12),
      child: Row(
        crossAxisAlignment: .start,
        children: [
          if (author != null)
            MemberAvatar.of(author, radius: HiwiskiMetrics.avatarSmall)
          else
            const SizedBox(width: 2 * HiwiskiMetrics.avatarSmall),
          const SizedBox(width: HiwiskiMetrics.space10),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                // Name and time side by side; with large text the time moves
                // below the name instead of past the edge.
                Wrap(
                  spacing: HiwiskiMetrics.space8,
                  crossAxisAlignment: .center,
                  children: [
                    Text(
                      author?.displayName as String? ?? '',
                      style: context.texts.labelMedium,
                    ),
                    if (timeOfUuidV7(widget.comment.id) case final written?)
                      Text(
                        DateFormat.MMMd(locale).add_Hm().format(written),
                        style: context.texts.bodySmall?.copyWith(
                          color: context.scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                if (editor != null) ...[
                  ReferenceAutocomplete(
                    controller: editor,
                    focusNode: _editorFocus,
                    child: TextField(
                      key: CommentsKeys.commentEditInput,
                      controller: editor,
                      focusNode: _editorFocus,
                      minLines: 1,
                      maxLines: null,
                      decoration: const InputDecoration(isDense: true),
                      onSubmitted: (_) => _save(),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: .end,
                    children: [
                      TextButton(
                        onPressed: _stopEditing,
                        child: Text(l.actionCancel),
                      ),
                      TextButton(onPressed: _save, child: Text(l.actionSave)),
                    ],
                  ),
                ] else
                  LinkedProse(
                    text: widget.comment.body,
                    style: context.texts.bodyMedium,
                    onOpen: widget.onOpen,
                  ),
              ],
            ),
          ),
          if (widget.mine && editor == null) ...[
            IconButton(
              key: CommentsKeys.commentEdit,
              iconSize: HiwiskiMetrics.icon16,
              tooltip: l.actionEdit,
              icon: const Icon(HiwiskiSymbols.edit),
              onPressed: _startEditing,
            ),
            // Held, it deletes; a tap only says so — as on a task's row.
            const DeleteHoldButton(
              holdKey: CommentsKeys.commentDelete,
              size: HiwiskiMetrics.icon16,
            ),
          ],
        ],
      ),
    );
  }
}
