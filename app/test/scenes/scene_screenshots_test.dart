import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'scene_app.dart';
import 'scene_shots.dart';

/// The website's screenshots of the scenes: every
/// scene the demo's sample data can show, light and dark, in German and English,
/// written as `<SCENES_OUT>/<lang>/<scene>-<light|dark>.png`.
///
/// Skipped unless `SCENES_OUT` is set — the release workflow sets it:
///
/// ```sh
/// SCENES_OUT=../site/static/scenes flutter test test/scenes
/// ```
void main() {
  final out = Platform.environment['SCENES_OUT'];
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tzdata.initializeTimeZones();
    if (out != null) await loadSceneFonts();
  });

  for (final language in const ['de', 'en']) {
    for (final shot in [...sceneShots, ..._tiles]) {
      for (final brightness in Brightness.values) {
        testWidgets(
          '${shot.name} · $language · ${brightness.name}',
          (tester) async => (await renderScene(
            tester,
            shot,
            language: language,
            brightness: brightness,
            screen: SceneScreen(Size(shot.width, shot.height), _pixelRatio),
            file: File('$out/$language/${shot.name}-${brightness.name}.png'),
          )).dispose(),
          // Not a test of the app: it writes the website's pictures, and only
          // when asked to.
          // ignore: many_lints/avoid_skipped_tests
          skip: out == null,
        );
      }
    }
  }
}

const _pixelRatio = 2.0;

/// The pictures of the feature overview's cards: all of one size, as on a larger
/// screen, so the cards line up (2).
const _tileScenes = {
  'tasks-overview',
  'calendar-week',
  'wiki-page',
  'start-board',
  'search',
  'sharing',
  'settings-backup',
};

Iterable<SceneShot> get _tiles => [
  for (final shot in sceneShots)
    if (_tileScenes.contains(shot.name))
      SceneShot(
        '${shot.name}-tile',
        625,
        shot.location,
        calendarView: shot.calendarView,
        prepare: shot.prepare,
        stage: shot.stage,
        width: 1000,
      ),
];
