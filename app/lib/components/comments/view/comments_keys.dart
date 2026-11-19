import 'package:flutter/widgets.dart';

/// The keys the tests find the comments' widgets by.
abstract final class CommentsKeys {
  static const commentDelete = ValueKey('comment-delete');
  static const commentEdit = ValueKey('comment-edit');
  static const commentEditInput = ValueKey('comment-edit-input');
  static const commentInput = ValueKey('comment-input');
}
