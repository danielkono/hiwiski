import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/common/server_address.dart';
import 'package:hiwiski/core/ui/invite_server_dialog.dart';
import 'package:hiwiski/core/ui/ui_keys.dart';

/// An invitation link names its server; before the app switches to it, the person
/// sees where it leads.
void main() {
  late Future<bool> answer;

  Future<void> open(WidgetTester tester, String address) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: HiwiskiTheme.light(),
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: L.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => answer = confirmInviteServer(
              context,
              ServerAddress.parse(address)!,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the address is shown, and cancelling connects nowhere', (
    tester,
  ) async {
    await open(tester, 'https://evil.example');

    expect(find.byKey(CoreKeys.inviteServerDialog), findsOneWidget);
    expect(find.textContaining('evil.example'), findsOneWidget);
    expect(find.text('This connection is not encrypted'), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await answer, isFalse);
  });

  testWidgets('a server without encryption says so', (tester) async {
    await open(tester, 'http://evil.example');

    expect(find.text('This connection is not encrypted'), findsOneWidget);

    await tester.tap(find.byKey(CoreKeys.inviteServerConnect));
    await tester.pumpAndSettle();
    expect(await answer, isTrue);
  });

  testWidgets('dismissing the dialog is a no', (tester) async {
    await open(tester, 'https://evil.example');

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(await answer, isFalse);
  });
}
