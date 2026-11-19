import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../common/wire.dart';

/// The `ownerType` of an image: the item that carries it.
abstract final class ImageOwnerTypes {
  static const member = 'MEMBER';
  static const wikiPage = EntityTypes.wikiPage;
  static const todo = EntityTypes.todo;
  static const todoList = EntityTypes.todoList;
  static const event = EntityTypes.event;
}

/// The two image calls **by hand** — the `images` tag is excluded from Dart generation
/// because the generator maps a binary body to `dart:io File`, which does not compile in
/// the browser.
/// The spec stays the source: `api/paths/images.yaml`.
class ImageClient {
  ImageClient(this._dio);

  static const _path = '/api/v1/images';
  static const _preview = 'preview';

  // The parts of the upload and the field of its answer.
  static const _ownerType = 'ownerType';
  static const _ownerItemId = 'ownerItemId';
  static const _file = 'file';
  static const _id = 'id';

  final Dio _dio;

  /// `POST /api/v1/images` — always with an owner. Returns the image's ID.
  ///
  /// [id] is the one the image already has on the device — an image added without a
  /// server, which its carrier points to. Sent twice, it is one upload.
  Future<String> upload({
    required String ownerType,
    required String ownerItemId,
    required Uint8List bytes,
    required String filename,
    String? id,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      _path,
      data: FormData.fromMap({
        _ownerType: ownerType,
        _ownerItemId: ownerItemId,
        _id: ?id,
        _file: MultipartFile.fromBytes(bytes, filename: filename),
      }),
    );
    return switch (response.data) {
      {_id: final String id} => id,
      _ => throw const FormatException('upload answered without an image id'),
    };
  }

  /// `GET /api/v1/images/{id}` or `…/preview`.
  Future<Uint8List> fetch(String id, {required bool preview}) async {
    final response = await _dio.get<List<int>>(
      preview ? '$_path/$id/$_preview' : '$_path/$id',
      options: Options(responseType: .bytes),
    );
    return Uint8List.fromList(
      response.data ??
          (throw const FormatException('image answered without bytes')),
    );
  }
}
