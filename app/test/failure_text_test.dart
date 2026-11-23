import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/api/hiwiski_failure.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/ui/failure_text.dart';

/// **What the server refuses a change with is said in words**, in either language —
/// an unknown code shows as itself.
void main() {
  Future<List<String>> textsOf(
    WidgetTester tester,
    Locale locale,
    List<String> codes,
  ) async {
    late List<String> texts;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L.supportedLocales,
        locale: locale,
        home: Builder(
          builder: (context) {
            texts = [
              for (final code in codes) failureTextForCode(context, code),
            ];
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return texts;
  }

  testWidgets('a mind map change the server refuses says why', (tester) async {
    const codes = [
      FailureCodes.wikiNotAMindmap,
      FailureCodes.wikiMindmapElementGone,
    ];
    for (final locale in const [Locale('en'), Locale('de')]) {
      final texts = await textsOf(tester, locale, codes);
      for (final (index, code) in codes.indexed) {
        expect(texts[index], isNot(equals(code)), reason: '$locale');
      }
    }
    expect(
      await textsOf(tester, const Locale('en'), ['wiki.something_new']),
      equals(['wiki.something_new']),
    );
  });
}
