/// Picks a backup archive to upload and saves a downloaded one — the platform
/// differences in one place, as for `pickFiles`.
library;

import 'pick_files.dart';

export 'archive_files_stub.dart'
    if (dart.library.js_interop) 'archive_files_web.dart';

/// A backup archive the person chose: its name, its size and its bytes as a stream, so
/// it goes to the server without sitting in memory where the platform allows.
typedef PickedArchive = ({String name, int length, Stream<List<int>> bytes});

/// The file dialog, for one archive. Read as a stream where the platform can.
Future<PickedArchive?> pickArchive() async {
  final file = (await pickFiles()).firstOrNull;
  if (file == null) return null;
  final length = await file.length() ?? (await file.readAsBytes()).length;
  return (name: file.name, length: length, bytes: file.readAsByteStream());
}
