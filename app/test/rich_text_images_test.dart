import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/components/rich_text/rich_text_view_model.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_image_store.dart';
import 'package:hiwiski/core/sync/outbox.dart';
import 'package:hiwiski/data/media/media_repository.dart';
import 'package:hiwiski/domain/common/item_ref.dart';

import 'support/fakes.dart';

/// **An image added to a text does not wait for the server**: it is kept on the
/// device for its carrier and in the text at once — offline, and when the editor is
/// saved right after. It goes up with the sync.
void main() {
  test(
    'images are kept for their carrier, in order, without a request',
    () async {
      final db = HiwiskiDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final localImages = LocalImageStore(db);
      final server = _Offline();
      final api = HiwiskiApi(
        tokens: NoTokens(),
        baseUrl: 'http://hiwiski.test',
      );
      api.dio.httpClientAdapter = server;
      final container = ProviderContainer(
        overrides: [
          mediaRepositoryProvider.overrideWithValue(
            MediaRepository(
              api,
              localImages: localImages,
              outbox: Outbox(db),
              serverless: false,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final first = Uint8List.fromList([1]);
      final second = Uint8List.fromList([2]);

      final ids = await container
          .read(richTextViewModelProvider(const ItemRef.todo('task')).notifier)
          .addImages([
            (bytes: first, filename: 'a.jpg'),
            (bytes: second, filename: 'b.jpg'),
          ]);

      expect(server.requests, equals(0));
      expect(ids, hasLength(2));
      expect(await localImages.read(ids.first), equals(first));
      expect(await localImages.read(ids.last), equals(second));
      final kept = await localImages.all();
      expect(kept.map((image) => image.ownerItemId).toSet(), equals({'task'}));
      expect(
        kept.map((image) => image.ownerType).toSet(),
        equals({EntityTypes.todo}),
      );
    },
  );
}

/// No network: every request fails, and is counted.
class _Offline implements HttpClientAdapter {
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests++;
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'offline',
    );
  }

  @override
  void close({bool force = false}) {}
}
