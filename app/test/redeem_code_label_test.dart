import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:hiwiski/features/redeem_invitation/view/redeem_invitation_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// **"Einladungscode" stands in one line above the code.** Given a third of the row
/// between its two lines, the word broke in the middle on a narrow phone.
void main() {
  testWidgets('the label above the code does not wrap on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionAt(
            const SessionState(
              stage: .signedOut,
              serverAddress: 'https://familie.example',
            ),
          ),
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
          locale: const Locale('de'),
          home: const RedeemInvitationScreen(),
        ),
      ),
    );

    final label = tester.renderObject<RenderParagraph>(
      find.text('Einladungscode'),
    );
    // Laid out as wide as the whole word: narrower, it would have wrapped.
    expect(
      label.size.width,
      moreOrLessEquals(label.getMaxIntrinsicWidth(double.infinity)),
    );
  });
}
