import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/repositories.dart';
import '../../app/stores.dart';
import '../../core/api/generated/export.dart';
import '../../domain/common/item_ref.dart';
import '../../domain/wiki/comment.dart';

part 'comments_view_model.g.dart';

/// The comments on an item, with their authors.
@immutable
class const CommentsState({
  required final List<Comment> comments,

  /// The members by id — a comment names its author.
  required final Map<String, Member> authors,

  /// Who is signed in: one's own comments can be edited and deleted.
  required final String? me,
});

@riverpod
Stream<List<Comment>> _comments(Ref ref, ItemRef item) =>
    ref.watch(wikiRepositoryProvider).watchComments(item.type, item.id);

/// Comments deleted a moment ago that can still be taken back — left out.
@riverpod
Stream<Set<String>> _pendingDeletes(Ref ref) =>
    ref.watch(wikiRepositoryProvider).watchPendingCommentDeletes();

@riverpod
Stream<List<Member>> _members(Ref ref) =>
    ref.watch(familyRepositoryProvider).watchMembers();

/// **On all items, not just wiki pages**: also on tasks, events, lists and
/// calendars.
@riverpod
class CommentsViewModel extends _$CommentsViewModel {
  @override
  Future<CommentsState> build(ItemRef item) async {
    // From the server — not waited for: offline the names may never come.
    final members = ref.watch(_membersProvider).value ?? const <Member>[];
    final me = ref.watch(sessionProvider.select((s) => s.member?.id));
    final deleted = ref.watch(_pendingDeletesProvider).value ?? const {};
    final comments = ref.watch(_commentsProvider(item).future);
    return CommentsState(
      comments: [
        for (final comment in await comments)
          if (!deleted.contains(comment.id)) comment,
      ],
      authors: {for (final member in members) member.id: member},
      me: me,
    );
  }

  Future<void> add(String body) => ref
      .read(wikiRepositoryProvider)
      .addComment(itemType: item.type, itemId: item.id, body: body);

  Future<void> edit(Comment comment, String body) =>
      ref.read(wikiRepositoryProvider).updateComment(comment, body: body);

  /// Deletes [comment] — after a moment in which [undoDelete] takes it back, as a
  /// task deleted from its row.
  void delete(Comment comment) =>
      ref.read(wikiRepositoryProvider).deleteCommentSoon(comment);

  /// Takes a comment's deletion back while it can be.
  void undoDelete(String commentId) =>
      ref.read(wikiRepositoryProvider).undoDeleteComment(commentId);
}
