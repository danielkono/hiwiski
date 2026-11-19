import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/repositories.dart';
import '../../app/stores.dart';
import '../../core/common/command.dart';
import '../../domain/tags/tag.dart';

part 'manage_tags_view_model.g.dart';

/// `create`, run by a view: it shows the command running and reacts to how it ended.
final createOwnTagMutation = Mutation<String>(
  label: 'manageTagsViewModel.create',
);

/// Account → Tags: one's own and the shared ones, with how often each is used.
@immutable
class ManageTagsState {
  const ManageTagsState({
    required this.mine,
    required this.shared,
    required this.usage,
    this.shareable = true,
  });

  /// Whether one's own tags can be shared — not without a server.
  final bool shareable;

  final List<Tag> mine;
  final List<Tag> shared;

  /// How often each tag is attached to an item that lives on this device.
  final Map<String, int> usage;

  int get count => mine.length + shared.length;
}

@riverpod
Stream<List<Tag>> _tags(Ref ref) =>
    ref.watch(tagRepositoryProvider).watchTags();

@riverpod
Stream<Map<String, int>> _usage(Ref ref) =>
    ref.watch(tagRepositoryProvider).watchUsage();

@riverpod
class ManageTagsViewModel extends _$ManageTagsViewModel {
  @override
  Future<ManageTagsState> build() async {
    final me = ref.watch(sessionProvider.select((s) => s.member?.id));
    final tagList = ref.watch(_tagsProvider.future);
    final usage = ref.watch(_usageProvider.future);
    final tags = await tagList;
    return ManageTagsState(
      shareable: ref.watch(sessionProvider.select((s) => s.hasServer)),
      mine: [
        for (final tag in tags)
          if (tag.ownerId == me) tag,
      ],
      shared: [
        for (final tag in tags)
          if (tag.ownerId != me) tag,
      ],
      usage: await usage,
    );
  }

  @command
  Future<String> create(String name) =>
      ref.read(tagRepositoryProvider).createTag(name);

  /// Deleted, it leaves every filter too.
  Future<void> delete(Tag tag) =>
      ref.read(tagRepositoryProvider).deleteTag(tag);
}
