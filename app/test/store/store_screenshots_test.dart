import 'dart:io';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import '../scenes/scene_app.dart';
import '../scenes/scene_shots.dart';
import 'feature_graphic.dart';
import 'store_shot.dart';
import 'store_texts.dart';

/// The store pictures: the app's screens as each device shows them, put into the
/// design's frame with a label, a headline and a line below it — six per device,
/// light only, in German and English — and the Play feature graphic.
///
/// **They are golden files**, at a quarter of their size (`goldens/`): a change to
/// the app that shows in a store picture fails here, and the pictures in the stores
/// are due for an update. Fonts render a little differently on every system, so the
/// goldens are made and compared on Linux only, as CI runs them; on a Mac,
/// `tool/store_shots.sh` runs them in a Linux container.
///
/// With `STORE_OUT` set, the pictures are also written at full size, and the raw
/// screens next to them:
///
/// ```sh
/// STORE_OUT=build/store flutter test test/store
/// ```
///
/// written as `<STORE_OUT>/<lang>/<device>/<nn>-<scene>.png` and
/// `<STORE_OUT>/raw/<lang>/<device>/<nn>-<scene>.png`.
void main() {
  final out = Platform.environment['STORE_OUT'];
  final goldens =
      Platform.isLinux || Platform.environment.containsKey('STORE_GOLDENS');
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tzdata.initializeTimeZones();
    await loadSceneFonts();
  });

  for (final language in const ['de', 'en']) {
    for (final device in StoreDevice.values) {
      for (final (index, name) in storeScenes.indexed) {
        final shot = _onDevice(
          sceneShots.firstWhere((shot) => shot.name == name),
          language,
        );
        final number = '${index + 1}'.padLeft(2, '0');
        final path = '$language/${device.name}/$number-$name.png';
        // One folder, a name of its own: a failed golden leaves its differences in
        // failures/ under the golden's file name, and equal names overwrote each
        // other.
        final golden = 'goldens/$language-${device.name}-$number-$name.png';
        testWidgets(
          '$name · ${device.name} · $language',
          (tester) => withClock(_ticking(storeDay), () async {
            final screen = await renderScene(
              tester,
              shot,
              language: language,
              brightness: .light,
              screen: device.screen,
              file: out == null ? null : File('$out/raw/$path'),
              framed: false,
              // A store picture shows the app as it is used, not on its first day.
              learned: true,
            );
            try {
              await _picture(
                tester,
                StoreShot(
                  size: device.picture,
                  tokens: device.tokens,
                  text: storeTexts[language]![index],
                  accent: storeAccents[index],
                  screen: screen,
                ),
                size: device.picture,
                golden: goldens ? golden : null,
                file: out == null ? null : File('$out/$path'),
              );
            } finally {
              screen.dispose();
            }
          }),
          // Neither compared nor written: on a Mac without STORE_OUT.
          // ignore: many_lints/avoid_skipped_tests
          skip: !goldens && out == null,
        );
      }
    }

    testWidgets(
      'feature graphic · $language',
      (tester) async {
        final icon = (await tester.runAsync(() async {
          final bytes = File('assets/brand/hiwiski_icon.png').readAsBytesSync();
          final codec = await ui.instantiateImageCodec(bytes);
          return (await codec.getNextFrame()).image;
        }))!;
        final texts = featureTexts[language]!;
        try {
          await _picture(
            tester,
            FeatureGraphic(
              icon: icon,
              tagline: texts.tagline,
              areas: texts.areas,
            ),
            size: FeatureGraphic.size,
            golden: goldens ? 'goldens/$language-feature-graphic.png' : null,
            file: out == null
                ? null
                : File('$out/$language/feature-graphic.png'),
          );
        } finally {
          icon.dispose();
        }
      },
      // ignore: many_lints/avoid_skipped_tests
      skip: !goldens && out == null,
    );
  }
}

/// The goldens' scale: a quarter of each side. Enough to see any change to a screen,
/// small enough to keep in the repository.
const _goldenScale = 0.25;

final _pictureKey = GlobalKey();

/// Lays out [picture] at [size] — its pixels — and compares it with [golden] at a
/// quarter of its size, writing it to [file] at full size.
Future<void> _picture(
  WidgetTester tester,
  Widget picture, {
  required Size size,
  String? golden,
  File? file,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // flutter_test draws shadows without their blur, so that widget goldens agree
  // across systems; the frame's soft shadow is part of the design. Put back before
  // the test ends, where flutter_test checks it.
  debugDisableShadows = false;
  try {
    await _draw(tester, picture, golden: golden, file: file);
  } finally {
    debugDisableShadows = true;
  }
}

Future<void> _draw(
  WidgetTester tester,
  Widget picture, {
  String? golden,
  File? file,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: .ltr,
      child: Center(
        child: RepaintBoundary(key: _pictureKey, child: picture),
      ),
    ),
  );
  await tester.pump();
  final boundary =
      tester.renderObject(find.byKey(_pictureKey)) as RenderRepaintBoundary;
  final small = (await tester.runAsync(() async {
    if (file != null) {
      final full = await boundary.toImage();
      await writePng(full, file);
      full.dispose();
    }
    return boundary.toImage(pixelRatio: _goldenScale);
  }))!;
  if (golden != null) await expectLater(small, matchesGoldenFile(golden));
  small.dispose();
}

/// The scenes of the store pictures, in the order the stores show them: the first
/// three are what a visitor sees without scrolling.
const storeScenes = [
  'start-board',
  'kanban-board',
  'calendar-week',
  'recipe',
  'sharing',
  'settings-backup',
];

/// [shot] as the store shows it, where that differs from the website.
///
/// The kanban board: a phone shows one column at a time and opens on the first, the
/// ideas, which say least about the board. The quotes have a description and an
/// assignee.
SceneShot _onDevice(SceneShot shot, String language) => switch (shot.name) {
  'kanban-board' => SceneShot(
    shot.name,
    shot.height,
    shot.location,
    open: (tester, _, _) async {
      // The column's chip above the board; its title further down says the same.
      await tester.tap(
        find.text(language == 'de' ? 'Angebote' : 'Quotes').first,
      );
    },
  ),
  _ => shot,
};

/// The day the pictures show: a Wednesday morning, so the week has days behind and
/// ahead of it. Fixed, because the sample data is laid out around "today" and every
/// date on screen would otherwise change from one day to the next.
final storeDay = DateTime(2026, 5, 13, 9, 41);

/// A clock that starts at [start] and moves on by a millisecond each time it is read.
///
/// Not a fixed clock: ids are UUIDv7 and sort by their time, and with one time for all
/// of them the sample data would come out in a different order on every run. The
/// same run reads the clock the same number of times, so the pictures stay the same;
/// what the screen shows is in minutes and does not move.
Clock _ticking(DateTime start) {
  int reads = 0;
  return Clock(() => start.add(Duration(milliseconds: reads++)));
}

/// The devices the stores ask pictures for: the size of the store picture and the
/// design's measures for it, and the screen inside — the logical size the app lays
/// itself out in, its pixel density and the safe area of its status bar and home
/// indicator.
enum StoreDevice {
  /// App Store, iPhone 6.9″: the screen and the picture 1320 × 2868 pixels.
  iphone(
    SceneScreen(
      Size(440, 956),
      3,
      padding: .only(top: 62, bottom: 34),
      platform: .iOS,
    ),
    Size(1320, 2868),
    phoneTokens,
  ),

  /// App Store, iPad 13″: the screen and the picture 2064 × 2752 pixels.
  ipad(
    SceneScreen(
      Size(1032, 1376),
      2,
      padding: .only(top: 24, bottom: 20),
      platform: .iOS,
    ),
    Size(2064, 2752),
    tabletTokens,
  ),

  /// Google Play, phone: a screen of 1080 × 2400 pixels, a common Android one, in a
  /// picture of 1080 × 1920 (9:16, which Play features).
  androidPhone(
    SceneScreen(
      Size(1080 / 2.625, 2400 / 2.625),
      2.625,
      padding: .only(top: 32, bottom: 24),
      platform: .android,
    ),
    Size(1080, 1920),
    phoneTokens,
  ),

  /// Google Play, 10″ tablet: the screen and the picture 1600 × 2560 pixels.
  androidTablet(
    SceneScreen(
      Size(800, 1280),
      2,
      padding: .symmetric(vertical: 24),
      platform: .android,
    ),
    Size(1600, 2560),
    tabletTokens,
  );

  const StoreDevice(this.screen, this.picture, this.tokens);

  final SceneScreen screen;

  /// The store picture's size in pixels.
  final Size picture;

  final StoreTokens tokens;
}
