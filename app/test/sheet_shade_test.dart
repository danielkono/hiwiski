import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/ui/hiwiski_sheet.dart';

/// A sheet darkens the whole screen. The areas have a navigator of their own inside
/// the shell, below the status bar and above the tab bar; a sheet opened there left
/// both bright beside the shaded content.
void main() {
  testWidgets('a sheet from inside the shell shades the status bar too', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext inner;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: L.supportedLocales,
        home: Scaffold(
          // The shell: the status bar's strip above, the areas' navigator below.
          body: Padding(
            padding: const .only(top: 47, bottom: 80),
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (context) {
                  inner = context;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      ),
    );

    final opened = showHiwiskiSheet<void>(
      context: inner,
      title: 'Sharing',
      builder: (_) => const Text('Shared with'),
    );
    await tester.pumpAndSettle();

    final shade = tester.getRect(find.byType(ModalBarrier).last);
    expect(shade.top, equals(0));
    expect(shade.bottom, equals(844));

    Navigator.of(tester.element(find.text('Shared with'))).pop();
    await tester.pumpAndSettle();
    await opened;
  });
}
