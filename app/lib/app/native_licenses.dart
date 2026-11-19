import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where the native libraries' licenses lie, and the list of them.
const nativeLicensesDirectory = 'assets/licenses';
const nativeLicensesManifest = '$nativeLicensesDirectory/native.json';

const _libraries = 'libraries';
const _name = 'name';
const _platforms = 'platforms';
const _covers = 'covers';
const _license = 'license';
const _notice = 'notice';
const _web = 'web';

/// One native library the apps ship, as `assets/licenses/native.json` lists it.
///
/// [covers] says what it stands for: on Android the Maven coordinates
/// (`group:artifact`, or a prefix ending in `.` or `:`), on iOS the Swift package's
/// identity in `Package.resolved`. Empty for what neither build lists, SQLite from
/// the `sqlite3` package's build hook.
@immutable
class NativeLibrary {
  const NativeLibrary({
    required this.name,
    required this.platforms,
    required this.covers,
    required this.license,
    this.notice,
  });

  factory NativeLibrary.fromJson(Map<String, Object?> json) => .new(
    name: json[_name] as String,
    platforms: [...json[_platforms] as List<Object?>].cast<String>(),
    covers: [...json[_covers] as List<Object?>].cast<String>(),
    license: json[_license] as String,
    notice: json[_notice] as String?,
  );

  final String name;
  final List<String> platforms;
  final List<String> covers;

  /// The license's text, a file next to the manifest.
  final String license;

  /// The library's NOTICE, where it has one: the Apache license asks for it to
  /// travel with every copy.
  final String? notice;

  /// Whether this entry stands for the Maven module or the Swift package [id].
  bool coversId(String id) => covers.any(
    (cover) =>
        cover == id ||
        ((cover.endsWith('.') || cover.endsWith(':')) && id.startsWith(cover)),
  );

  static List<NativeLibrary> parse(String manifest) => [
    for (final entry
        in (jsonDecode(manifest) as Map<String, Object?>)[_libraries]
            as List<Object?>)
      NativeLibrary.fromJson(entry as Map<String, Object?>),
  ];
}

/// The name [NativeLibrary.platforms] uses for the platform this runs on: Flutter's
/// own, in lower case (`android`, `ios`, `macos` …), and `web` in a browser.
String get currentLicensePlatform =>
    kIsWeb ? _web : defaultTargetPlatform.name.toLowerCase();

/// The native libraries, for "Licenses of the packages used" next to the Dart
/// packages and the fonts.
///
/// Flutter collects the licenses of the Dart packages and of its own engine by
/// itself; the libraries the Android and iOS builds add -- the home screen widgets',
/// the plugins' own -- it does not know. Their licenses ask to travel with the app,
/// the Apache license's NOTICE files included. Only this platform's are listed: the
/// others are not in this build. The Android build and
/// `test/native_licenses_test.dart` refuse a library the list does not cover
/// (docs/development/app.md, "Licenses").
void registerNativeLicenses() {
  LicenseRegistry.addLicense(() async* {
    final platform = currentLicensePlatform;
    final libraries = NativeLibrary.parse(
      await rootBundle.loadString(nativeLicensesManifest),
    );
    for (final library in libraries) {
      if (!library.platforms.contains(platform)) continue;
      final texts = [
        if (library.notice case final notice?)
          await rootBundle.loadString('$nativeLicensesDirectory/$notice'),
        await rootBundle.loadString(
          '$nativeLicensesDirectory/${library.license}',
        ),
      ];
      yield LicenseEntryWithLineBreaks([library.name], texts.join('\n\n'));
    }
  });
}
