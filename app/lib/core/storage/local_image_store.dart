import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../common/ids.dart';
import '../db/hiwiski_database.dart';

/// Images added while the device has no server.
///
/// With a server an image is uploaded and only cached here. Without one, the bytes
/// are the image: they stay in the database, under an id the carrier points to at
/// once, until the device connects and they are uploaded under that same id.
class LocalImageStore {
  LocalImageStore(this._db);

  final HiwiskiDatabase _db;

  /// Keeps an image and returns its new id.
  Future<String> put({
    required String ownerType,
    required String ownerItemId,
    required Uint8List bytes,
    required String filename,
  }) async {
    final id = newId();
    await _db
        .into(_db.localImages)
        .insert(
          LocalImageRow(
            id: id,
            ownerType: ownerType,
            ownerItemId: ownerItemId,
            filename: filename,
            bytes: bytes,
          ),
        );
    return id;
  }

  /// The bytes of [id], if it is one of these.
  Future<Uint8List?> read(String id) async => (await (_db.select(
    _db.localImages,
  )..where((row) => row.id.equals(id))).getSingleOrNull())?.bytes;

  /// Every image still waiting for a server.
  Future<List<LocalImageRow>> all() => _db.select(_db.localImages).get();

  /// Uploaded — or its carrier is gone: it leaves.
  Future<void> remove(String id) =>
      (_db.delete(_db.localImages)..where((row) => row.id.equals(id))).go();
}
