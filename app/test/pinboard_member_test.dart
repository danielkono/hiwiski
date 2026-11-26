import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/wiki/pinboard.dart';
import 'package:hiwiski/features/wiki/pinboard/view/pinboard_color_sheet.dart';
import 'package:hiwiski/features/wiki/pinboard/view/pinboard_keys.dart';
import 'package:hiwiski/features/wiki/view/pinboard/pinboard_members.dart';
import 'package:hiwiski/features/wiki/view/pinboard/pinboard_scene.dart';

/// A member element's ring is the element's colour itself — see-through where the
/// colour is, as the colour sheet's opacity strip makes it.
void main() {
  Future<Color?> ringOf(WidgetTester tester, String? color) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: HiwiskiTheme.light(),
        localizationsDelegates: L.localizationsDelegates,
        home: PinboardMembers(
          members: const {},
          child: Center(
            child: SizedBox.square(
              dimension: 120,
              child: PinboardElementView(
                node: PinboardNode(
                  id: 'a',
                  ownerId: 'anna',
                  version: 1,
                  pageId: 'page',
                  kind: PinboardKinds.member,
                  x: 0,
                  y: 0,
                  width: 120,
                  height: 120,
                  layer: 1,
                  text: '',
                  target: memberAddressOf('ben'),
                  color: color,
                ),
                linkTarget: (_) => null,
              ),
            ),
          ),
        ),
      ),
    );
    final ring = tester.widget<Container>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is ShapeDecoration &&
            (widget.decoration! as ShapeDecoration).shape is CircleBorder,
      ),
    );
    return (ring.decoration! as ShapeDecoration).color;
  }

  testWidgets('a see-through colour makes a see-through ring', (tester) async {
    final ring = await ringOf(tester, '#C0392B80');

    expect(ring?.toARGB32(), equals(0x80C0392B));
  });

  testWidgets('a covering colour makes a covering ring', (tester) async {
    final ring = await ringOf(tester, '#C0392B');

    expect(ring?.toARGB32(), equals(0xFFC0392B));
  });

  testWidgets('the opacity strip makes the chosen colour see-through', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ({String? color})? chosen;
    await tester.pumpWidget(
      MaterialApp(
        theme: HiwiskiTheme.light(),
        localizationsDelegates: L.localizationsDelegates,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => chosen = await showPinboardColorSheet(
                context,
                current: '#C0392B',
                recent: const [],
              ),
              child: const Text('colour'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('colour'));
    await tester.pumpAndSettle();

    final strip = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == 'Opacity',
    );
    await tester.tap(strip);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PinboardKeys.save));
    await tester.pumpAndSettle();

    // Half way along: half see-through, of the same colour.
    expect(chosen?.color, equals('#C0392B80'));
  });
}
