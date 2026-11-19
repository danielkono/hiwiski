import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/components/account_avatar/view/account_avatar.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_symbols.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/core/ui/embedded_page.dart';
import 'package:hiwiski/core/ui/page_header.dart';
import 'package:hiwiski/core/ui/panel_reopen.dart';

import 'support/fakes.dart';

/// **Switching between the areas does not move the content.** The areas sit side by
/// side in the navigation; a header that is taller on one of them makes everything
/// below it jump on every switch.
///
/// One-letter titles: the test font is wide, and a title that wraps would measure the
/// font, not the header.
void main() {
  Future<double> heightOf(
    WidgetTester tester,
    Widget header, {
    required double width,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionAt(signedInAnna)],
        child: MaterialApp(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: const [
            L.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: L.supportedLocales,
          home: Scaffold(
            body: Align(alignment: .topCenter, child: header),
          ),
        ),
      ),
    );
    return tester.getSize(find.byType(PageHeader)).height;
  }

  for (final (name, width) in [('phone', 390.0), ('desktop', 1280.0)]) {
    testWidgets('$name: a kicker does not make the header taller', (
      tester,
    ) async {
      final plain = await heightOf(
        tester,
        const PageHeader(title: 'T'),
        width: width,
      );
      final withKicker = await heightOf(
        tester,
        const PageHeader(title: 'G', kicker: 'Sunday'),
        width: width,
      );
      expect(withKicker, equals(plain));
    });

    testWidgets('$name: actions next to the avatar do not either', (
      tester,
    ) async {
      final plain = await heightOf(
        tester,
        const PageHeader(title: 'T'),
        width: width,
      );
      final withActions = await heightOf(
        tester,
        PageHeader(
          title: 'C',
          trailing: [
            // The calendar's: on the phone the view menu is a symbol, from 600 a pill.
            if (width < 600)
              IconButton(icon: const Icon(Icons.view_list), onPressed: () {})
            else
              ActionChip(label: const Text('Month'), onPressed: () {}),
            IconButton(icon: const Icon(Icons.settings), onPressed: () {}),
          ],
        ),
        width: width,
      );
      expect(withActions, equals(plain));
    });

    testWidgets('$name: a subpage is as high with a key as without', (
      tester,
    ) async {
      final withKey = await heightOf(
        tester,
        PageHeader(title: 'F', detail: '3 · 1', onBack: () {}),
        width: width,
      );
      final without = await heightOf(
        tester,
        PageHeader(title: 'F', onBack: () {}),
        width: width,
      );
      expect(without, equals(withKey));
    });
  }

  // The drawer puts family (a subpage) right next to settings (a top level).
  // No line is kept free under the title of an area: it has nothing to put there,
  // and the room stood empty between the title and the filter.
  testWidgets('desktop: an area keeps no room for an item line', (
    tester,
  ) async {
    final top = await heightOf(
      tester,
      const PageHeader(title: 'S'),
      width: 1280,
    );
    final sub = await heightOf(
      tester,
      PageHeader(title: 'F', detail: '3 · 1', onBack: () {}),
      width: 1280,
    );
    expect(top, lessThan(sub));
  });

  // The browser goes back on its own.
  for (final (name, width) in [('phone', 390.0), ('desktop', 1280.0)]) {
    testWidgets('$name, web: no back arrow, and no jump without it', (
      tester,
    ) async {
      final plain = await heightOf(
        tester,
        PageHeader(title: 'E', entityKey: 'EV-1', onBack: () {}, web: true),
        width: width,
      );
      expect(find.byIcon(HiwiskiSymbols.arrowBack), findsNothing);
      final withEdit = await heightOf(
        tester,
        PageHeader(
          title: 'E',
          entityKey: 'EV-1',
          onBack: () {},
          web: true,
          trailing: [FilledButton(onPressed: () {}, child: const Text('E'))],
        ),
        width: width,
      );
      expect(withEdit, equals(plain));
    });
  }

  testWidgets('outside the browser the back arrow is there', (tester) async {
    await heightOf(
      tester,
      PageHeader(title: 'E', onBack: () {}, web: false),
      width: 390,
    );
    expect(find.byIcon(HiwiskiSymbols.arrowBack), findsOneWidget);
  });

  testWidgets(
    'desktop: a list open next to the overview shows no second avatar',
    (tester) async {
      await heightOf(
        tester,
        PageHeader(title: 'L', onBack: () {}, web: false),
        width: 1280,
      );
      expect(find.byType(AccountAvatar), findsOneWidget);
      expect(find.byIcon(HiwiskiSymbols.arrowBack), findsOneWidget);

      await heightOf(
        tester,
        EmbeddedPage(
          child: PageHeader(title: 'L', onBack: () {}, web: false),
        ),
        width: 1280,
      );
      expect(find.byType(AccountAvatar), findsNothing);
      expect(find.byIcon(HiwiskiSymbols.arrowBack), findsNothing);
    },
  );

  // A list and the task opened from it: the content below must not jump between them.
  for (final (name, width) in [('phone', 390.0), ('desktop', 1280.0)]) {
    testWidgets(
      '$name: a link in the item line does not make the header taller',
      (tester) async {
        final plain = await heightOf(
          tester,
          PageHeader(
            title: 'L',
            entityKey: 'LST-1',
            detail: '5',
            onBack: () {},
          ),
          width: width,
        );
        final withCrumb = await heightOf(
          tester,
          PageHeader(
            title: 'T',
            entityKey: 'TD-1',
            crumbs: [HeaderCrumb(label: 'L', onTap: () {})],
            onBack: () {},
          ),
          width: width,
        );
        expect(withCrumb, equals(plain));
      },
    );
  }

  testWidgets(
    'the item line reads key, container, context — and the link works',
    (tester) async {
      int opened = 0;
      await heightOf(
        tester,
        PageHeader(
          title: 'T',
          entityKey: 'TD-14',
          crumbs: [HeaderCrumb(label: 'Household', onTap: () => opened++)],
          detail: '5 open',
          onBack: () {},
        ),
        width: 1280,
      );
      final key = tester.getTopLeft(find.text('TD-14')).dx;
      final crumb = tester.getTopLeft(find.text('Household')).dx;
      final detail = tester.getTopLeft(find.text('5 open')).dx;
      expect(key, lessThan(crumb));
      expect(crumb, lessThan(detail));

      await tester.tap(find.text('Household'));
      expect(opened, equals(1));
    },
  );

  // From 600 the search is in the navigation rail beside the page.
  testWidgets('the search is in the header on the phone only', (tester) async {
    await heightOf(tester, const PageHeader(title: 'T'), width: 390);
    expect(find.byIcon(HiwiskiSymbols.search), findsOneWidget);
    await heightOf(tester, const PageHeader(title: 'T'), width: 800);
    expect(find.byIcon(HiwiskiSymbols.search), findsNothing);
  });

  testWidgets('phone: a subpage has the title size of a top-level area', (
    tester,
  ) async {
    await heightOf(tester, const PageHeader(title: 'Top'), width: 390);
    final top = tester.widget<Text>(find.text('Top')).style?.fontSize;
    await heightOf(tester, PageHeader(title: 'Sub', onBack: () {}), width: 390);
    final sub = tester.widget<Text>(find.text('Sub')).style?.fontSize;
    expect(sub, equals(top));
  });

  // A task's title stands where the title of its area stood, in a header as high.
  for (final width in [390.0, 800.0, 1280.0]) {
    testWidgets('$width: a subpage has its title where an area has it', (
      tester,
    ) async {
      await heightOf(
        tester,
        const PageHeader(title: 'T', trailing: [Text('act')]),
        width: width,
      );
      final top = tester.getTopLeft(find.text('T'));
      final topAction = tester.getCenter(find.text('act')).dy;
      await heightOf(
        tester,
        PageHeader(
          title: 'S',
          entityKey: 'TD-1',
          onBack: () {},
          web: true,
          trailing: const [Text('act')],
        ),
        width: width,
      );
      final subAction = tester.getCenter(find.text('act')).dy;
      final sub = tester.getTopLeft(find.text('S'));
      expect(sub, equals(top));
      // And what stands beside the title is level with it on both.
      expect(subAction, equals(topAction));
    });
  }

  // The panel beside an embedded screen is put away by the first button of the row
  // above it; the button that brings it back has to stand at the same place.
  testWidgets('embedded: the panel button stands in the top left corner', (
    tester,
  ) async {
    await heightOf(
      tester,
      EmbeddedPage(
        child: PanelReopen(
          button: IconButton(
            icon: const Icon(HiwiskiSymbols.leftPanelOpen),
            onPressed: () {},
          ),
          child: PageHeader(title: 'T', entityKey: 'LST-1', onBack: () {}),
        ),
      ),
      width: 1280,
    );
    final header = tester.getTopLeft(find.byType(PageHeader));
    final button = tester.getRect(find.byType(IconButton));
    expect(button.top, equals(header.dy));
    expect(button.left, equals(header.dx + PanelReopen.inset));
    // The title is level with the button, not below it.
    expect(tester.getCenter(find.text('T')).dy, equals(button.center.dy));
  });
}
