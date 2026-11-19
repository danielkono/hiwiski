import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/repositories.dart';
import '../../app/stores.dart';
import '../../core/common/command.dart';
import '../../core/common/wire.dart';
import '../../domain/tags/tag.dart';

part 'tags_view_model.g.dart';

/// `createTag`, run by a view: it shows the command running and reacts to how it ended.
final createTagMutation = Mutation<String>(label: 'tagsViewModel.createTag');

/// The family's tags as the tag widgets show them.
@immutable
class TagsState {
  const TagsState({
    required this.ranked,
    required this.recent,
    required this.me,
  });

  /// Every tag, in the order that matters to this member ([rankTags]).
  final List<Tag> ranked;

  /// The ids used most recently on tasks and lists, newest first.
  final List<String> recent;

  /// Who is signed in — one's own tags can be renamed and deleted.
  final String? me;

  Map<String, Tag> get byId => {for (final tag in ranked) tag.id: tag};
}

@riverpod
Stream<List<Tag>> _tags(Ref ref) =>
    ref.watch(tagRepositoryProvider).watchTags();

@riverpod
Stream<List<String>> _recent(Ref ref) =>
    ref.watch(tagRepositoryProvider).watchRecent();

@riverpod
class TagsViewModel extends _$TagsViewModel {
  @override
  Future<TagsState> build() async {
    final tagUses = ref.watch(preferencesProvider.select((p) => p.tagUses));
    final me = ref.watch(sessionProvider.select((s) => s.member?.id));
    final tags = ref.watch(_tagsProvider.future);
    final recent = ref.watch(_recentProvider.future);
    return TagsState(
      ranked: rankTags(await tags, tagUses),
      recent: await recent,
      me: me,
    );
  }

  @command
  Future<String> createTag(
    String name, {
    String colorToken = ColorTokens.blue,
  }) => ref.read(tagRepositoryProvider).createTag(name, colorToken: colorToken);

  Future<void> updateTag(Tag tag, {String? name, String? colorToken}) => ref
      .read(tagRepositoryProvider)
      .updateTag(tag, name: name, colorToken: colorToken);

  /// Deleted, it leaves every filter too.
  Future<void> deleteTag(Tag tag) =>
      ref.read(tagRepositoryProvider).deleteTag(tag);

  /// Putting a tag on an item counts as using it — the filter bar ranks by that.
  void used(Iterable<String> ids) =>
      // Only the ranking of the filter bar; a lost use costs nothing.
      ref.read(preferencesStoreProvider).recordTagUses(ids).ignore();
}
