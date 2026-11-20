import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/link_index.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/components/rich_text/view/markdown_field.dart';
import 'package:hiwiski/components/rich_text/view/markdown_text_controller.dart';
import 'package:hiwiski/components/rich_text/view/rich_image.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_image_store.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/sync/outbox.dart';
import 'package:hiwiski/core/theme/hiwiski_metrics.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/data/media/media_repository.dart';
import 'package:hiwiski/domain/links/link_index.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// **An image in a formatted text** stands on a line of its own that grows with it,
/// as a thumbnail as wide as the image's shape makes it.
void main() {
  Future<Uint8List> png(int width, int height) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFF336699),
    );
    final image = await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: .png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  Finder thumbnail(String id) =>
      find.byWidgetPredicate((w) => w is RichImage && w.imageId == id);

  Future<MarkdownTextController> pump(WidgetTester tester, String text) async {
    SharedPreferences.setMockInitialValues(const {});
    final local = (await tester.runAsync(LocalSettings.open))!;
    final images = (await tester.runAsync(
      () async => {
        'wide': await png(200, 100),
        'tall': await png(90, 120),
        'panorama': await png(400, 50),
        'screenshot': await png(30, 120),
      },
    ))!;
    final controller = MarkdownTextController(text: text);
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        overrides: [
          localSettingsProvider.overrideWithValue(local),
          linkIndexProvider.overrideWithValue(LinkIndex.from(const [])),
          mediaRepositoryProvider.overrideWithValue(_Media(images)),
        ],
        child: MaterialApp(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: L.localizationsDelegates,
          supportedLocales: L.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MarkdownField(controller: controller, focusNode: focus),
            ),
          ),
        ),
      ),
    );
    // Decoding runs outside the test's fake clock; the shapes come with it.
    for (final id in images.keys) {
      if (!text.contains(id)) continue;
      for (int i = 0; i < 50; i++) {
        if (tester.getSize(thumbnail(id)).width !=
            HiwiskiMetrics.editorImageHeight) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
    }
    return controller;
  }

  testWidgets('a thumbnail is as wide as its image, between the bounds', (
    tester,
  ) async {
    await pump(
      tester,
      '![](hiwiski-image:wide)\n![](hiwiski-image:tall)\n'
      '![](hiwiski-image:panorama)\n![](hiwiski-image:screenshot)',
    );
    const height = HiwiskiMetrics.editorImageHeight;
    expect(tester.getSize(thumbnail('wide')), equals(const Size(192, height)));
    expect(tester.getSize(thumbnail('tall')), equals(const Size(72, height)));
    expect(
      tester.getSize(thumbnail('panorama')),
      equals(const Size(HiwiskiMetrics.editorImageMaxWidth, height)),
    );
    expect(
      tester.getSize(thumbnail('screenshot')),
      equals(const Size(HiwiskiMetrics.editorImageMinWidth, height)),
    );
  });

  // A field forces its lines to the height of its text unless it is told otherwise:
  // the image was drawn over the line above, and the next line ran under it.
  testWidgets('an image line grows: nothing is drawn over the text around it', (
    tester,
  ) async {
    const text = 'Shopping\n![](hiwiski-image:wide)\nmilk';
    await pump(tester, text);
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    Rect line(String word) {
      final start = text.indexOf(word);
      final boxes = editable.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + word.length),
      );
      final local = boxes
          .map((box) => box.toRect())
          .reduce((a, b) => a.expandToInclude(b));
      return local.shift(editable.localToGlobal(Offset.zero));
    }

    final image = tester.getRect(thumbnail('wide'));
    // The middle of a line: its glyph boxes reach into the leading of the next.
    expect(line('Shopping').center.dy, lessThan(image.top));
    expect(line('milk').center.dy, greaterThan(image.bottom));
  });

  testWidgets('a thumbnail keeps its shape when the text is drawn anew', (
    tester,
  ) async {
    final controller = await pump(tester, 'Shopping\n![](hiwiski-image:wide)');
    // Back from the source, the thumbnail is a new one: it starts with the shape
    // known, not square.
    controller.toggleFormatted();
    await tester.pump();
    expect(thumbnail('wide'), findsNothing);
    controller.toggleFormatted();
    await tester.pump();
    expect(tester.getSize(thumbnail('wide')).width, equals(192));
  });
}

class _Media extends MediaRepository {
  _Media(this._images)
    : super(
        HiwiskiApi(tokens: NoTokens(), baseUrl: 'http://hiwiski.test'),
        localImages: LocalImageStore(_unused),
        outbox: Outbox(_unused),
        serverless: false,
      );

  /// Never opened: the fake answers every image itself.
  static final _unused = HiwiskiDatabase(NativeDatabase.memory());

  final Map<String, Uint8List> _images;

  @override
  Stream<Uint8List> watchImage(String id, {required bool preview}) =>
      .value(_images[id]!);
}
