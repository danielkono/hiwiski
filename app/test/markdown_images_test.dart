import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/link_index.dart';
import 'package:hiwiski/components/links/view/linked_markdown.dart';
import 'package:hiwiski/components/rich_text/view/image_stack.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/links/link_index.dart';

/// An image in a text from another server is a read receipt: it is fetched when
/// someone opens the text. It reads as a link to it instead, the reader decides.
void main() {
  /// What the app asked the browser to open.
  late List<String> opened;

  const launcher = MethodChannel('plugins.flutter.io/url_launcher');

  Future<void> pump(WidgetTester tester, String data) {
    opened = [];
    final messenger = tester.binding.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));
    messenger.setMockMethodCallHandler(launcher, (call) async {
      if (call.method == 'launch') {
        opened.add((call.arguments as Map)['url'] as String);
      }
      return true;
    });
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          linkIndexProvider.overrideWithValue(LinkIndex.from(const [])),
        ],
        child: MaterialApp(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: const [
            L.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: L.supportedLocales,
          home: Scaffold(body: LinkedMarkdown(data: data)),
        ),
      ),
    );
  }

  testWidgets('an image from another server is not loaded', (tester) async {
    await pump(
      tester,
      'Soup. ![pixel](https://tracker.example/p.png?u=anna) Enjoy.',
    );

    expect(find.byType(Image), findsNothing);
    expect(find.text('pixel'), findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets('its label shows the address on a long press, a tap opens it', (
    tester,
  ) async {
    await pump(tester, 'Search: ![google](https://google.com)');

    final label = tester.widget<Text>(find.text('google'));
    expect(
      label.style?.color,
      equals(HiwiskiTheme.light().colorScheme.primary),
    );

    await tester.longPress(find.text('google'));
    await tester.pumpAndSettle();
    expect(find.text('https://google.com'), findsOneWidget);
    expect(opened, isEmpty);

    await tester.tap(find.text('google'));
    await tester.pumpAndSettle();
    expect(opened, equals(['https://google.com']));
  });

  testWidgets('an ordinary link opens the same way', (tester) async {
    await pump(tester, 'See [the recipe](https://example.org/soup) here.');

    await tester.tap(find.text('the recipe'));
    await tester.pumpAndSettle();
    expect(opened, equals(['https://example.org/soup']));
  });

  testWidgets('a local file is not read, nor offered to open', (tester) async {
    await pump(tester, 'See ![](file:///etc/hosts)');

    expect(find.byType(Image), findsNothing);
    await tester.tap(find.textContaining('file:///etc/hosts'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
  });

  testWidgets(
    "the family's own image inside a line comes from the media store",
    (tester) async {
      await pump(tester, 'Before ![](hiwiski-image:abc-123) after');

      final stack = tester.widget<ImageStack>(find.byType(ImageStack));
      expect(stack.imageIds, equals(['abc-123']));
    },
  );
}
