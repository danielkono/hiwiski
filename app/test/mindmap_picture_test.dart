import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/api/hiwiski_failure.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_image_store.dart';
import 'package:hiwiski/core/sync/outbox.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/components/rich_text/view/rich_image.dart';
import 'package:hiwiski/data/media/media_repository.dart';
import 'package:hiwiski/domain/wiki/mindmap.dart';
import 'package:hiwiski/domain/wiki/page_images.dart';
import 'package:hiwiski/features/wiki/view/mindmap/mindmap_picture.dart';
import 'package:hiwiski/features/wiki/view/mindmap/mindmap_scene.dart';

import 'support/fakes.dart';

/// **A mind map drawn into a file** shows its pictures as they are, or as missing —
/// never as the spinner that stands for one on its way.
void main() {
  late _Media media;

  /// The drawing, as the screen around it would hand it on.
  Future<MindmapDrawing> drawing(WidgetTester tester) async {
    late MindmapDrawing draw;
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        overrides: [mediaRepositoryProvider.overrideWithValue(media)],
        child: MaterialApp(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: const [
            L.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              draw = mindmapDrawingOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return draw;
  }

  /// One picture element, the whole map.
  final picture = (
    title: 'Urlaub',
    map: Mindmap(
      nodes: [
        MindmapNode(
          id: 'picture',
          ownerId: 'anna',
          version: 1,
          pageId: 'page',
          kind: MindmapKinds.image,
          x: 0,
          y: 0,
          width: 200,
          height: 200,
          layer: 1,
          text: imageMarkdown('red'),
        ),
      ],
      edges: const [],
    ),
    members: const <String, Never>{},
    targets: const <String, Never>{},
  );

  testWidgets('a picture on its way is waited for, and drawn', (tester) async {
    media = _Media(
      bytes: (await tester.runAsync(_redPng))!,
      after: const Duration(milliseconds: 800),
    );
    final draw = await drawing(tester);

    final png = (await tester.runAsync(() => draw(picture)))!;

    expect((await tester.runAsync(() => _middleOf(png)))!, equals(_red));
  });

  testWidgets('a picture that is gone does not hold the drawing up', (
    tester,
  ) async {
    media = _Media();
    final draw = await drawing(tester);
    final took = Stopwatch()..start();

    final png = (await tester.runAsync(() => draw(picture)))!;

    expect(took.elapsed, lessThan(const Duration(seconds: 3)));
    expect((await tester.runAsync(() => _middleOf(png)))!, isNot(_red));
  });

  testWidgets('the tree a map is drawn in is taken down after it', (
    tester,
  ) async {
    media = _Media(bytes: (await tester.runAsync(_redPng))!);
    final draw = await drawing(tester);
    // What the drawing builds of its own and does not dispose of.
    final left = <Object>{};
    void track(ObjectEvent event) => switch (event) {
      ObjectCreated(:final object, :final className)
          when className == _renderObject || className == _layer =>
        left.add(object),
      ObjectDisposed(:final object) => left.remove(object),
      _ => null,
    };
    FlutterMemoryAllocations.instance.addListener(track);
    addTearDown(() => FlutterMemoryAllocations.instance.removeListener(track));

    await tester.runAsync(() => draw(picture));

    expect(left, isEmpty);
  });

  /// The picture element shown at [zoom], 200 wide, on a screen of two pixels per
  /// point — and which of its images are asked for: the preview, the original.
  Future<({bool preview, bool original})> shownAt(
    WidgetTester tester, {
    required double zoom,
    double? detail,
    bool scene = false,
  }) async {
    final node = picture.map.nodes.single;
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        overrides: [mediaRepositoryProvider.overrideWithValue(media)],
        child: MaterialApp(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: L.localizationsDelegates,
          home: Center(
            child: scene
                ? MindmapScene(
                    map: picture.map,
                    area: MindmapScene.areaOf(picture.map),
                    linkTarget: (_) => null,
                    zoom: zoom,
                    detail: detail,
                  )
                : SizedBox(
                    width: node.width.toDouble(),
                    height: node.height.toDouble(),
                    child: MindmapElementView(
                      node: node,
                      linkTarget: (_) => null,
                      zoom: zoom,
                    ),
                  ),
          ),
        ),
      ),
    );
    final images = tester.widgetList<RichImage>(find.byType(RichImage));
    return (
      preview: images.any((image) => image.preview),
      original: images.any((image) => !image.preview),
    );
  }

  testWidgets('a picture shows its preview until it is seen larger', (
    tester,
  ) async {
    media = _Media(bytes: (await tester.runAsync(_redPng))!);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // 200 points wide, 400 pixels: the preview, 640 at most, is enough.
    expect(
      await shownAt(tester, zoom: 1),
      equals((preview: true, original: false)),
    );
    // Zoomed in to 1600 pixels: the original over the preview, until it is there.
    expect(
      await shownAt(tester, zoom: 4),
      equals((preview: true, original: true)),
    );
    // A little back out, still above the preview: kept, not dropped and reloaded.
    expect((await shownAt(tester, zoom: 1.4)).original, isTrue);
    // Well below the preview's size: the preview alone again.
    expect(
      await shownAt(tester, zoom: 0.5),
      equals((preview: true, original: false)),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('once the original is there, the preview under it goes', (
    tester,
  ) async {
    media = _Media(bytes: (await tester.runAsync(_redPng))!);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // Fetched and decoded for real: neither waits on the test's clock.
    await tester.runAsync(() async {
      await shownAt(tester, zoom: 4);
      for (int i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pump();

    final images = tester.widgetList<RichImage>(find.byType(RichImage));
    expect(images.map((image) => image.preview), equals([false]));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a map shown smaller than its zoom loads only previews', (
    tester,
  ) async {
    media = _Media(bytes: (await tester.runAsync(_redPng))!);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // As the page's card fits the map: drawn at its own size, shown at a tenth.
    expect(
      await shownAt(tester, zoom: 4, detail: 0.1, scene: true),
      equals((preview: true, original: false)),
    );
    expect((await shownAt(tester, zoom: 4, scene: true)).original, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a picture resized a little is not decoded anew', (tester) async {
    media = _Media(bytes: (await tester.runAsync(_redPng))!);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    Future<int?> decodedAt(int width) async {
      await tester.pumpWidget(
        ProviderScope(
          retry: noRetry,
          overrides: [mediaRepositoryProvider.overrideWithValue(media)],
          child: MaterialApp(
            theme: HiwiskiTheme.light(),
            localizationsDelegates: L.localizationsDelegates,
            home: Center(
              child: SizedBox(
                width: width.toDouble(),
                height: 100,
                child: MindmapElementView(
                  node: picture.map.nodes.single.changed(width: width),
                  linkTarget: (_) => null,
                ),
              ),
            ),
          ),
        ),
      );
      return tester.widget<RichImage>(find.byType(RichImage)).decodeWidth;
    }

    // A drag on its corner, frame by frame: one width to decode at, sharp at each.
    final widths = {
      for (int width = 300; width <= 320; width += 4) await decodedAt(width),
    };
    expect(widths, hasLength(1));
    expect(widths.single, greaterThanOrEqualTo(320 * 2));
    expect(widths.single, lessThan(320 * 2 * 1.5));
    // Taken down, and what was still on its way let out.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

const _red = 0xFFFF0000;

/// What the render tree reports of itself, as it is made and disposed of.
const _renderObject = 'RenderObject';
const _layer = 'Layer';

/// A red picture of one pixel.
Future<Uint8List> _redPng() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 1, 1),
    Paint()..color = const Color(_red),
  );
  final image = await recorder.endRecording().toImage(1, 1);
  final bytes = await image.toByteData(format: .png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// The colour in the middle of [png], as `0xAARRGGBB`.
Future<int> _middleOf(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  final pixels = (await image.toByteData())!;
  final at = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
  final rgba = pixels.getUint32(at);
  image.dispose();
  return (rgba & 0xFF) << 24 | rgba >> 8;
}

/// Pictures from a server that takes [after] to answer, with [bytes] — or that no
/// longer has them.
class _Media extends MediaRepository {
  _Media({this.bytes, this.after = Duration.zero})
    : super(
        HiwiskiApi(tokens: NoTokens(), baseUrl: 'http://hiwiski.test'),
        localImages: LocalImageStore(_unused),
        outbox: Outbox(_unused),
        serverless: false,
      );

  /// Never opened: the fake answers every image itself.
  static final _unused = HiwiskiDatabase(NativeDatabase.memory());

  final Uint8List? bytes;
  final Duration after;

  @override
  Future<Uint8List> image(String id, {required bool preview}) async {
    await Future<void>.delayed(after);
    return bytes ??
        (throw const HiwiskiFailure(
          code: FailureCodes.mediaImageNotFound,
          status: 404,
        ));
  }
}
