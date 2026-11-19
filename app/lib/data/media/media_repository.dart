import 'package:flutter/foundation.dart';

import '../../core/api/hiwiski_api.dart';
import '../../core/api/hiwiski_failure.dart';
import '../../core/api/image_client.dart';
import '../../core/storage/image_disk_cache.dart';
import '../../core/storage/local_image_store.dart';
import '../../core/sync/outbox.dart';
import '../query.dart';

export '../../core/api/image_client.dart' show ImageOwnerTypes;

/// Images for recipes, wiki pages and avatars — not a file module.
///
/// Images are **not mirrored**: what is viewed gets fetched, and then it stays.
/// The ID never changes when the image changes — a new image is a new ID —, so the
/// cache never has to ask whether it is still current.
///
/// **Without a server** an image is kept on the device itself
/// ([LocalImageStore]) under the id its carrier points to; when the device connects,
/// [carryOver] uploads it under that same id.
class MediaRepository {
  MediaRepository(
    this._api, {
    required this._localImages,
    required this._outbox,
    required this._serverless,
  });

  static const _previewSuffix = '-preview';

  final HiwiskiApi _api;
  final LocalImageStore _localImages;
  final Outbox _outbox;
  final bool _serverless;

  /// Images the server would not take now, though they are no less the family's:
  /// kept on the device, and not uploaded again until the app starts anew.
  final _heldBack = <String>{};

  late final _images = Query<(String, bool), Uint8List>(
    (key) => image(key.$1, preview: key.$2),
  );

  /// An image while it is shown — in memory only then: kept, every image ever loaded
  /// stayed, full-size recipe pictures included, until the OS killed the app; the disk
  /// cache has it anyway.
  Stream<Uint8List> watchImage(String id, {required bool preview}) =>
      _images.watch((id, preview));

  /// An image — from the device first, otherwise from the server.
  Future<Uint8List> image(String id, {required bool preview}) async {
    // Added without a server and not uploaded yet: the only copy there is. There is
    // no preview of it — the original serves as one.
    if (await _localImages.read(id) case final bytes?) return bytes;
    final key = preview ? '$id$_previewSuffix' : id;
    // The cache is a speed-up, not a requirement: if it fails, the image simply comes
    // from the server.
    try {
      final cached = await ImageDiskCache.read(key);
      if (cached != null) return cached;
    } catch (error) {
      debugPrint('hiwiski: image cache not read: $error');
    }
    final bytes = await HiwiskiApi.run(
      () => _api.images.fetch(id, preview: preview),
    );
    try {
      await ImageDiskCache.write(key, bytes);
    } catch (error) {
      debugPrint('hiwiski: image cache not written: $error');
    }
    return bytes;
  }

  /// Uploads an image with its carrier and returns its id — the item points to it
  /// through a field that travels like any other. Without a server it is kept on the
  /// device instead.
  Future<String> upload({
    required String ownerType,
    required String ownerItemId,
    required Uint8List bytes,
    required String filename,
  }) => _serverless
      ? _localImages.put(
          ownerType: ownerType,
          ownerItemId: ownerItemId,
          bytes: bytes,
          filename: filename,
        )
      : HiwiskiApi.run(
          () => _api.images.upload(
            ownerType: ownerType,
            ownerItemId: ownerItemId,
            bytes: bytes,
            filename: filename,
          ),
        );

  /// Keeps an image on the device for an item the server may not know yet, and
  /// returns the id the item can point to at once — an import creates its pages and
  /// their images in one go, offline too. [carryOver] uploads it under that id once
  /// the item has arrived; an upload now would be refused for a page still waiting in
  /// the outbox.
  Future<String> keep({
    required String ownerType,
    required String ownerItemId,
    required Uint8List bytes,
    required String filename,
  }) => _localImages.put(
    ownerType: ownerType,
    ownerItemId: ownerItemId,
    bytes: bytes,
    filename: filename,
  );

  /// What this device keeps: the database and the image cache, in bytes. The
  /// database's size is `null` where it cannot be measured (the browser).
  Future<({int? data, int images})> storage() async => (
    data: await ImageDiskCache.databaseSize(),
    images: await ImageDiskCache.size(),
  );

  /// Throws the cached images away — they come back from the server when viewed.
  Future<void> clearCache() => ImageDiskCache.clear();

  /// Uploads what was added without a server, each image under the id its carrier
  /// already points to — once the carrier itself is on the server: nothing of it
  /// waits in the outbox any more. Returns the images uploaded now.
  ///
  /// An image whose carrier the server does not know (deleted meanwhile, refused)
  /// is given up; one past the member's quota or under an id already taken stays on
  /// the device; one that fails otherwise stays for the next try.
  Future<List<({String id, String ownerType})>> carryOver() async {
    if (_serverless) return const [];
    final uploaded = <({String id, String ownerType})>[];
    for (final image in await _localImages.all()) {
      if (_heldBack.contains(image.id)) continue;
      if (image.ownerType != ImageOwnerTypes.member &&
          await _outbox.lastPendingFor(image.ownerItemId) != null) {
        continue;
      }
      try {
        await HiwiskiApi.run(
          () => _api.images.upload(
            ownerType: image.ownerType,
            ownerItemId: image.ownerItemId,
            bytes: image.bytes,
            filename: image.filename,
            id: image.id,
          ),
        );
      } on HiwiskiFailure catch (failure) {
        if (failure.isNetwork || failure.isTransient) rethrow;
        // Past the member's quota, or the id taken — by someone who read it in the
        // carrier before this device uploaded: the only copy stays, shown here, and
        // is tried again on the next start, not with every sync.
        if (failure.code == FailureCodes.mediaQuotaExceeded ||
            failure.code == FailureCodes.mediaIdTaken) {
          debugPrint('hiwiski: image ${image.id} waits for room: $failure');
          _heldBack.add(image.id);
          continue;
        }
        debugPrint('hiwiski: image ${image.id} not carried over: $failure');
        await _localImages.remove(image.id);
        continue;
      }
      try {
        await ImageDiskCache.write(image.id, image.bytes);
      } catch (error) {
        debugPrint('hiwiski: image cache not written: $error');
      }
      await _localImages.remove(image.id);
      uploaded.add((id: image.id, ownerType: image.ownerType));
    }
    return uploaded;
  }
}
