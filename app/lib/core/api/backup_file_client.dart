import 'dart:typed_data';

import 'package:dio/dio.dart';

/// An archive uploaded to the server, waiting for its password.
typedef UploadedBackup = ({String id, int bytes});

/// The archive calls **by hand** — the `backupFiles` tag is excluded from Dart
/// generation for the same reason as the images: a binary body becomes `dart:io File`
/// there, which does not compile in the browser. And they are streamed,
/// with progress. The spec stays the source: `api/paths/admin.yaml` and
/// `api/paths/setup.yaml`.
class BackupFileClient {
  BackupFileClient(this._dio);

  static const _backups = '/api/v1/admin/backups';
  static const _uploads = '$_backups/uploads';
  static const _file = '/file';
  static const _setupUploads = '/api/v1/setup/uploads';
  static const _setupCodeHeader = 'X-Hiwiski-Setup-Code';
  static const _octetStream = 'application/octet-stream';
  static const _id = 'id';
  static const _bytes = 'bytes';

  final Dio _dio;

  /// `GET /api/v1/admin/backups/{id}/file` into memory — in the browser, which hands
  /// it to the download from there.
  Future<Uint8List> fetch(String id, {ProgressCallback? onProgress}) async {
    final response = await _dio.get<List<int>>(
      '$_backups/$id$_file',
      options: Options(responseType: .bytes),
      onReceiveProgress: onProgress,
    );
    return Uint8List.fromList(
      response.data ??
          (throw const FormatException('download answered without bytes')),
    );
  }

  /// `GET /api/v1/admin/backups/{id}/file` straight into a file at [path] — on a
  /// device, so an archive of years of photos never sits in memory.
  Future<void> fetchTo(
    String id,
    String path, {
    ProgressCallback? onProgress,
  }) =>
      _dio.download('$_backups/$id$_file', path, onReceiveProgress: onProgress);

  /// `POST /api/v1/admin/backups/uploads`. The body is the file, streamed.
  Future<UploadedBackup> upload(
    Stream<List<int>> bytes,
    int length, {
    ProgressCallback? onProgress,
  }) => _upload(_uploads, bytes, length, onProgress: onProgress);

  /// `POST /api/v1/setup/uploads`, on a fresh server — with [setupCode] where the
  /// server asks for one. The body is the file, streamed.
  Future<UploadedBackup> uploadForSetup(
    Stream<List<int>> bytes,
    int length, {
    String? setupCode,
    ProgressCallback? onProgress,
  }) => _upload(
    _setupUploads,
    bytes,
    length,
    setupCode: setupCode,
    onProgress: onProgress,
  );

  Future<UploadedBackup> _upload(
    String path,
    Stream<List<int>> bytes,
    int length, {
    String? setupCode,
    ProgressCallback? onProgress,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      path,
      data: bytes,
      options: Options(
        contentType: _octetStream,
        headers: {
          Headers.contentLengthHeader: length,
          _setupCodeHeader: ?setupCode,
        },
      ),
      onSendProgress: onProgress,
    );
    return switch (response.data) {
      {_id: final String id, _bytes: final int bytes} => (id: id, bytes: bytes),
      _ => throw const FormatException('upload answered without an id'),
    };
  }
}
