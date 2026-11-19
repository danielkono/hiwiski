import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/ui/content_width.dart';
import 'package:hiwiski/core/ui/info_bar.dart';

/// The info bar stands beside the content only while the content keeps its reading
/// width next to it. On an iPad upright the window is wide, but the drawer and the
/// wiki's tree left the article a column of 190, and "Servings" broke into one
/// letter per line.
void main() {
  /// Whether the bar would stand beside the content in a window [window] wide, in an
  /// area [area] wide; without [area] nothing measures it.
  Future<bool> besideAt(
    WidgetTester tester, {
    required double window,
    double? area,
  }) async {
    tester.view.physicalSize = Size(window, 1376);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late bool beside;
    final probe = Builder(
      builder: (context) {
        beside = InfoBar.besideContent(context);
        return const SizedBox.shrink();
      },
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: .ltr,
        child: Align(
          alignment: .topLeft,
          child: area == null
              ? probe
              : SizedBox(
                  width: area,
                  child: ContentWidth(child: probe),
                ),
        ),
      ),
    );
    return beside;
  }

  testWidgets('a wide window with room to spare: beside', (tester) async {
    expect(await besideAt(tester, window: 1440, area: 1180), isTrue);
  });

  testWidgets('an iPad upright, the wiki beside its tree: below', (
    tester,
  ) async {
    // 1032 less the rail (80) and the tree (280).
    expect(await besideAt(tester, window: 1032, area: 671), isFalse);
  });

  testWidgets('an iPad upright, a list without a tree: beside', (tester) async {
    expect(await besideAt(tester, window: 1032, area: 952), isTrue);
  });

  testWidgets('never on a medium window, however much it has', (tester) async {
    expect(await besideAt(tester, window: 1000), isFalse);
  });

  testWidgets('nothing measured: the window counts', (tester) async {
    expect(await besideAt(tester, window: 1280), isTrue);
  });
}
