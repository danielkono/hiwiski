import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/native_licenses.dart';

/// **Every native library the apps ship has its license on the licenses page.**
/// Flutter lists the Dart packages by itself, the Swift packages of the iOS widgets
/// it does not know; for Android the build checks the same (`checkNativeLicenses` in
/// android/app/build.gradle.kts). Docs: docs/development/app.md, "Licenses".
void main() {
  final libraries = NativeLibrary.parse(
    File(nativeLicensesManifest).readAsStringSync(),
  );

  test('every Swift package of the Apple builds is listed', () {
    for (final (platform, resolved) in [
      ('ios', 'ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved'),
      (
        'macos',
        'macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved',
      ),
    ]) {
      final file = File(resolved);
      if (!file.existsSync()) continue;
      final pins =
          (jsonDecode(file.readAsStringSync()) as Map<String, Object?>)['pins']!
              as List<Object?>;
      for (final pin in pins) {
        final id = (pin! as Map<String, Object?>)['identity']! as String;
        expect(
          libraries.where(
            (library) =>
                library.platforms.contains(platform) && library.coversId(id),
          ),
          isNotEmpty,
          reason:
              '$id ($resolved) has no entry for $platform in '
              '$nativeLicensesManifest',
        );
      }
    }
  });

  // CocoaPods would bring libraries the check above does not read.
  test('no CocoaPods', () {
    expect(File('ios/Podfile.lock').existsSync(), isFalse);
    expect(File('macos/Podfile.lock').existsSync(), isFalse);
  });

  test('every text the list names is there', () {
    for (final library in libraries) {
      for (final text in [library.license, ?library.notice]) {
        expect(
          File('$nativeLicensesDirectory/$text').existsSync(),
          isTrue,
          reason: '${library.name}: $text',
        );
      }
    }
  });

  group('the licenses page', () {
    setUp(LicenseRegistry.reset);
    tearDown(LicenseRegistry.reset);

    Future<Map<String, String>> listed() async {
      registerNativeLicenses();
      return {
        await for (final entry in LicenseRegistry.licenses)
          entry.packages.single: [
            for (final paragraph in entry.paragraphs) paragraph.text,
          ].join('\n'),
      };
    }

    testWidgets(
      'on Android: its libraries, not the Swift ones',
      variant: TargetPlatformVariant.only(.android),
      (tester) async {
        final page = await tester.runAsync(listed);
        expect(page!['AndroidX'], contains('Apache License'));
        expect(page['OkHttp'], contains('Public Suffix List'));
        expect(page.keys, isNot(contains('Swift OpenAPI Runtime')));
      },
    );

    testWidgets(
      'on iOS: the Swift packages with their NOTICE',
      variant: TargetPlatformVariant.only(.iOS),
      (tester) async {
        final page = await tester.runAsync(listed);
        expect(
          page!['Swift OpenAPI Runtime'],
          allOf(
            contains('The SwiftOpenAPIGenerator Project'),
            contains('Apache License'),
          ),
        );
        expect(page.keys, isNot(contains('AndroidX')));
        expect(page.keys, contains('SQLite'));
      },
    );
  });
}
