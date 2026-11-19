import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/repositories.dart';
import '../../app/stores.dart';
import '../../core/common/command.dart';
import '../../domain/common/item_ref.dart';

part 'rich_text_view_model.g.dart';

/// `uploadImages`, run by the editor: it inserts the images when it is done and shows
/// that it runs.
final uploadRichImagesMutation = Mutation<List<String>>(
  label: 'richTextViewModel.uploadImages',
);

/// A text that holds Markdown, links and images — a wiki page's, a task's
/// description, an event's note. Its state is the item that carries its images
/// (there is no upload without a carrier).
@riverpod
class RichTextViewModel extends _$RichTextViewModel {
  @override
  ItemRef build(ItemRef carrier) => carrier;

  /// Uploads [files] onto the carrier and returns their ids, in order — the editor
  /// puts them into the text. Needs the carrier on the server: an item still only on
  /// the device answers 404.
  @command
  Future<List<String>> uploadImages(
    List<({Uint8List bytes, String filename})> files,
  ) async {
    final media = ref.read(mediaRepositoryProvider);
    return [
      for (final file in files)
        await media.upload(
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
