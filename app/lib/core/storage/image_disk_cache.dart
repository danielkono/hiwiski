import 'dart:typed_data';

// The browser knows `dart:io` as a name but not as a disk — hence the switch on
// `js_interop` and not on `io`.
import 'image_disk_cache_io.dart'
    if (dart.library.js_interop) 'image_disk_cache_stub.dart'
    as impl;

/// The cache on the device: **only viewed** images, and they stay. The browser
/// has none — there the browser itself keeps nothing fetched with a token, and the app
/// keeps the image as long as it is open.
abstract final class ImageDiskCache {
  static Future<Uint8List?> read(String key) => impl.read(key);

  static Future<void> write(String key, Uint8List bytes) =>
      impl.write(key, bytes);

  /// Space used in bytes — for "Storage" in the settings.
  static Future<int> size() => impl.size();

  /// The mirrored data — not measurable in the browser, `null` there.
  static Future<int?> databaseSize() => impl.databaseSize();

  /// "Free up storage": throws the images away; they come back the next time they are
  /// viewed.
  static Future<void> clear() => impl.clear();
}
