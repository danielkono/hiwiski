import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/data/family/family_repository.dart';
import 'package:hiwiski/features/redeem_invitation/view/redeem_invitation_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **The invitation preview is the one for the code in the field.** An answer for a
/// code that was changed meanwhile was shown, and Join redeemed the other code.
void main() {
  testWidgets('an answer for an older code is not shown', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final family = _FakeFamily();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyRepositoryProvider.overrideWithValue(family),
          localSettingsProvider.overrideWithValue(await LocalSettings.open()),
        ],
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
          home: const RedeemInvitationScreen(),
        ),
      ),
    );
    final code = find.byType(TextField).first;
    await tester.enterText(code, 'ABCDEFG');
    await tester.pump();
    await tester.enterText(code, 'ABCDEFH');
    await tester.pump();

    family.answer('ABCDEFG', 'The Gs');
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('The Gs'), findsNothing);

    family.answer('ABCDEFH', 'The Hs');
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('The Hs'), findsWidgets);
  });
}

class _FakeFamily implements FamilyRepository {
  final _pending = <String, Completer<InvitationPreview>>{};

  void answer(String code, String family) => _pending[code]!.complete(
    InvitationPreview(
      familyName: family,
      invitedBy: 'Anna',
      expiresAt: DateTime(2030),
    ),
  );

  @override
  Future<InvitationPreview> previewInvitation(String code) =>
      (_pending[code] = Completer<InvitationPreview>()).future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
