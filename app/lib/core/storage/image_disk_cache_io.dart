import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../common/app_names.dart';

const _directory = 'hiwiski-images';

/// A file being written; renamed once it is complete.
const _partial = '.part';

Future<Directory> _dir() async {
  final base = await getApplicationCacheDirectory();
  return Directory(p.join(base.path, _directory)).create(recursive: true);
}

Future<Uint8List?> read(String key) async {
  final file = File(p.join((await _dir()).path, key));
  return await file.exists() ? file.readAsBytes() : null;
}

/// Each write has a temporary file of its own: two writers of the same image — the
/// preview and the full view racing — shared one, and the second rename found it
/// gone. A write that fails anyway, or one a `clear` cut short, is a cache miss, not
/// an error: the image comes from the server again.
Future<void> write(String key, Uint8List bytes) async {
  final dir = await _dir();
  final partial = File(
    p.join(dir.path, '$key.${_random.nextInt(1 << 32)}$_partial'),
  );
  try {
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(p.join(dir.path, key));
  } on FileSystemException {
    try {
      if (await partial.exists()) await partial.delete();
    } on FileSystemException catch (error) {
      // Gone with a cleared cache.
      debugPrint('hiwiski: partial image not removed: $error');
    }
  }
}

final _random = Random();

Future<int> size() async {
  int total = 0;
  await for (final entity in (await _dir()).list()) {
    if (entity is File) total += await entity.length();
  }
  return total;
}

Future<void> clear() async {
  final dir = await _dir();
  if (await dir.exists()) await dir.delete(recursive: true);
}

const _databaseFile = '.sqlite';
const _databaseWal = '.sqlite-wal';

/// `drift_flutter` puts the database into the documents folder as `hiwiski.sqlite`.
Future<int?> databaseSize() async {
  final base = await getApplicationDocumentsDirectory();
  int total = 0;
  for (final suffix in const [_databaseFile, _databaseWal]) {
    final name = '${AppNames.product}$suffix';
    final file = File(p.join(base.path, name));
    if (await file.exists()) total += await file.length();
  }
  return total;
}
