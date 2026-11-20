import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/repositories.dart';
import '../../app/stores.dart';
import '../../core/common/command.dart';
import '../../domain/common/item_ref.dart';

part 'rich_text_view_model.g.dart';

/// `addImages`, run by the editor: it inserts the images when it is done and shows
/// that it runs — the iPhone converts its photos first, which takes a moment.
final addRichImagesMutation = Mutation<List<String>>(
  label: 'richTextViewModel.addImages',
);

/// A text that holds Markdown, links and images — a wiki page's, a task's
/// description, an event's note. Its state is the item that carries its images
/// (there is no image without a carrier).
@riverpod
class RichTextViewModel extends _$RichTextViewModel {
  @override
  ItemRef build(ItemRef carrier) => carrier;

  /// Keeps [files] on the device for the carrier and returns their ids, in order —
  /// the editor puts them into the text at once. They go up with the sync, like the
  /// text that names them (`MediaRepository.keep`): offline too, for an item not on
  /// the server yet too, and saving while they are still on their way loses nothing.
  @command
  Future<List<String>> addImages(
    List<({Uint8List bytes, String filename})> files,
  ) async {
    final media = ref.read(mediaRepositoryProvider);
    return [
      for (final file in files)
        await media.keep(
          ownerType: carrier.type,
          ownerItemId: carrier.id,
          bytes: file.bytes,
          filename: file.filename,
        ),
    ];
  }
}

/// Whether a text opens formatted for writing or as its Markdown — the member's choice
/// in Account → Customize. The editor switches either way; this is where it starts.
@riverpod
class RichTextModeViewModel extends _$RichTextModeViewModel {
  @override
  bool build() =>
      ref.watch(preferencesProvider.select((p) => p.formattedEditor));
}

@riverpod
Stream<Uint8List> _image(Ref ref, String imageId, bool preview) =>
    ref.watch(mediaRepositoryProvider).watchImage(imageId, preview: preview);

/// An image of the media store, in memory only while it is shown.
@riverpod
class RichImageViewModel extends _$RichImageViewModel {
  @override
  Future<Uint8List> build(String imageId, bool preview) =>
      ref.watch(_imageProvider(imageId, preview).future);
}
