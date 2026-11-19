import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/components/rich_text/view/image_stack.dart';
import 'package:hiwiski/components/rich_text/view/rich_image.dart';
import 'package:hiwiski/components/rich_text/view/rich_text_keys.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_image_store.dart';
import 'package:hiwiski/core/sync/outbox.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/data/media/media_repository.dart';

import 'support/fakes.dart';

/// **A group of images lies stacked** and is clicked or swiped through.
void main() {
  // A 1×1 transparent PNG.
  final pixel = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
    0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  late _Media media;

  Future<void> pump(WidgetTester tester, List<String> ids) async {
    media = _Media(pixel);
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
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
          home: Scaffold(body: ImageStack(imageIds: ids)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a click brings the next image to the front', (tester) async {
    await pump(tester, ['a', 'b', 'c']);
    expect(find.text('1/3'), findsOneWidget);

    await tester.tap(find.byKey(RichTextKeys.imageStack));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
  });

  // Like a pile of cards: a swipe either way takes the top card off — the side is
  // only where it flies. Swiped right, the pile used to turn back and the card
  // below seemed swapped for another.
  testWidgets('a swipe either way goes on, a short one springs back', (
    tester,
  ) async {
    await pump(tester, ['a', 'b', 'c']);
    final stack = find.byKey(RichTextKeys.imageStack);

    await tester.drag(stack, const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);

    await tester.drag(stack, const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(find.text('3/3'), findsOneWidget);

    await tester.timedDrag(
      stack,
      const Offset(-20, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(find.text('3/3'), findsOneWidget);
  });

  testWidgets('swiped right, the top card flies off to the right', (
    tester,
  ) async {
    await pump(tester, ['a', 'b', 'c']);
    final image = find.descendant(
      of: find.byKey(const ValueKey('a')),
      matching: find.byType(Material),
    );
    final start = tester.getRect(image.first);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(RichTextKeys.imageStack)),
    );
    for (int i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // Out to the right, not to the left — and the card below came up.
    expect(tester.getRect(image.first).left, greaterThan(start.left + 100));
    expect(find.text('2/3'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  // What is about to show is loaded before it does — the visible pile and the next
  // card — and no more: a long group of full photos cost every frame on a phone.
  testWidgets('a group loads the pile and the next cards, not all', (
    tester,
  ) async {
    await pump(tester, ['a', 'b', 'c', 'd', 'e', 'f', 'g']);
    expect(media.asked.toSet(), equals({'a', 'b', 'c', 'd'}));

    await tester.tap(find.byKey(RichTextKeys.imageStack));
    await tester.pumpAndSettle();
    expect(media.asked.toSet(), equals({'a', 'b', 'c', 'd', 'e'}));
  });

  // A phone's photo is up to 24 megapixels: one per card took the browser's memory.
  testWidgets('only the front card asks for the original', (tester) async {
    await pump(tester, ['a', 'b', 'c', 'd']);
    expect(media.originals.toSet(), equals({'a'}));

    await tester.tap(find.byKey(RichTextKeys.imageStack));
    await tester.pumpAndSettle();
    expect(media.originals.toSet(), equals({'a', 'b'}));
  });

  // A clip on a turned card was cut out in every frame: Safari on the iPhone took
  // about 100 ms per frame with it, 8 ms without.
  testWidgets('no card clips its image; the image rounds its own corners', (
    tester,
  ) async {
    await pump(tester, ['a', 'b', 'c']);
    final pile = find.byKey(RichTextKeys.imageStack);
    final cards = tester.widgetList<Material>(
      find.descendant(of: pile, matching: find.byType(Material)),
    );
    expect(cards, isNotEmpty);
    expect(cards.map((m) => m.clipBehavior).toSet(), equals({Clip.none}));
    expect(
      find.descendant(of: pile, matching: find.byType(ClipRRect)),
      findsNothing,
    );
    final images = tester.widgetList<RichImage>(
      find.descendant(of: pile, matching: find.byType(RichImage)),
    );
    expect(images.map((i) => i.radius).toSet(), isNot(contains(null)));
  });

  // Decoded at the card's size, not the photo's.
  testWidgets('a card decodes its image at the card\'s size', (tester) async {
    await pump(tester, ['a', 'b']);

    final image = tester.widget<RichImage>(find.byType(RichImage).first);
    expect(image.decodeWidth, isNotNull);
    expect(image.decodeWidth, lessThanOrEqualTo(600));
  });

  // A pile of cards, not images swapped between fixed places: the front card flies
  // off to the side and slides in at the back, staying the same card.
  testWidgets('the front card flies off and slides in at the back', (
    tester,
  ) async {
    await pump(tester, ['a', 'b', 'c']);
    final card = find.byKey(const ValueKey('a'));
    // The image inside the card: the card moves by a transform, its own box does not.
    final image = find.descendant(of: card, matching: find.byType(Material));
    final element = tester.element(card);
    final start = tester.getRect(image.first);

    await tester.tap(find.byKey(RichTextKeys.imageStack));
    // The animation's clock starts with the next frame.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    // Mid-way it is out to the side.
    expect(tester.getRect(image.first).left, lessThan(start.left - 100));

    await tester.pumpAndSettle();
    expect(tester.element(card), same(element));
    // At rest it lies at the back of the pile: two steps to the right, turned a
    // little — the turn takes its centre back by about one step.
    expect(
      tester.getRect(image.first).center.dx,
      greaterThan(start.center.dx + 4),
    );
    expect(find.text('2/3'), findsOneWidget);
  });

  testWidgets('a single image has no counter', (tester) async {
    await pump(tester, ['a']);
    expect(find.textContaining('/'), findsNothing);
    expect(find.byKey(RichTextKeys.imageStack), findsNothing);
  });

  testWidgets('large, a swipe down closes; a short one springs back', (
    tester,
  ) async {
    await pump(tester, ['a', 'b', 'c']);
    await tester.tap(find.byTooltip('Show large'));
    await tester.pumpAndSettle();
    final gallery = find.byKey(RichTextKeys.imageGallery);
    expect(gallery, findsOneWidget);

    // A short, slow pull: the image comes back up, the gallery stays.
    await tester.timedDrag(
      gallery,
      const Offset(0, 40),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(gallery, findsOneWidget);
    expect(
      tester.getCenter(find.byType(PageView)),
      equals(tester.getCenter(find.byType(Scaffold))),
    );

    // Far enough, it closes, and the image flies back onto the pile.
    await tester.timedDrag(
      gallery,
      const Offset(0, 300),
      const Duration(milliseconds: 600),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Hero), findsWidgets);
    await tester.pumpAndSettle();
    expect(gallery, findsNothing);
    expect(find.text('1/3'), findsOneWidget);
  });

  testWidgets('large, the group is swiped through; closed, the pile follows', (
    tester,
  ) async {
    await pump(tester, ['a', 'b', 'c']);
    expect(find.byType(Hero), findsOneWidget);

    await tester.tap(find.byTooltip('Show large'));
    await tester.pump();
    // The front image flies into the large view.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Hero), findsWidgets);
    await tester.pumpAndSettle();
    expect(find.byKey(RichTextKeys.imageGallery), findsOneWidget);
    expect(find.text('1/3'), findsWidgets);

    await tester.drag(
      find.byKey(RichTextKeys.imageGallery),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsWidgets);

    await tester.tap(find.byKey(RichTextKeys.imageGalleryClose));
    await tester.pumpAndSettle();
    expect(find.byKey(RichTextKeys.imageGallery), findsNothing);
    // The image last shown is the pile's front now.
    expect(find.text('2/3'), findsOneWidget);
  });

  // The flight ends on the image, not on the screen: the large view lays the image
  // out at its shape — the cards' 4:3 until it is decoded, which a widget test's
  // clock does not do — not the whole screen.
  testWidgets('large, the image takes its own shape in the middle', (
    tester,
  ) async {
    await pump(tester, ['a', 'b']);
    await tester.tap(find.byTooltip('Show large'));
    await tester.pumpAndSettle();

    final hero = find.descendant(
      of: find.byKey(RichTextKeys.imageGallery),
      matching: find.byType(Hero),
    );
    final rect = tester.getRect(hero.first);
    expect(rect.width / rect.height, moreOrLessEquals(4 / 3, epsilon: 0.01));
    expect(rect.width, moreOrLessEquals(600, epsilon: 1));
    expect(rect.center.dy, moreOrLessEquals(400, epsilon: 1));
  });

  // Opening flew the image to the middle of the screen at once: the flight went to
  // the whole screen, not to the image. It now leaves the card where the card is and
  // grows from there, both ways.
  testWidgets('the flight starts on the card and ends on the image', (
    tester,
  ) async {
    await pump(tester, ['a', 'b']);
    final card = tester.getRect(
      find
          .descendant(
            of: find.byKey(const ValueKey('a')),
            matching: find.byType(Material),
          )
          .first,
    );

    await tester.tap(find.byTooltip('Show large'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    final start = tester.getRect(find.byType(ClipRRect).last);
    expect(start.center.dx, moreOrLessEquals(card.center.dx, epsilon: 4));
    expect(start.center.dy, moreOrLessEquals(card.center.dy, epsilon: 4));
    expect(start.width, moreOrLessEquals(card.width, epsilon: 4));

    await tester.pump(const Duration(milliseconds: 160));
    final middle = tester.getRect(find.byType(ClipRRect).last);
    expect(middle.width, greaterThan(card.width));
    await tester.pumpAndSettle();

    // And back: from the large image into the card.
    await tester.tap(find.byKey(RichTextKeys.imageGalleryClose));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    final leaving = tester.getRect(find.byType(ClipRRect).last);
    expect(leaving.width, greaterThan(card.width));
    await tester.pumpAndSettle();
    expect(find.byKey(RichTextKeys.imageGallery), findsNothing);
  });
}

class _Media extends MediaRepository {
  _Media(this._bytes)
    : super(
        HiwiskiApi(tokens: NoTokens(), baseUrl: 'http://hiwiski.test'),
        localImages: LocalImageStore(_unused),
        outbox: Outbox(_unused),
        serverless: false,
      );

  /// Never opened: the fake answers every image itself.
  static final _unused = HiwiskiDatabase(NativeDatabase.memory());

  final Uint8List _bytes;

  /// The images asked for, in order.
  final asked = <String>[];

  /// The images whose original was asked for, not only the preview.
  final originals = <String>[];

  @override
  Stream<Uint8List> watchImage(String id, {required bool preview}) {
    asked.add(id);
    if (!preview) originals.add(id);
    return .value(_bytes);
  }
}
