import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/domain/legal/legal_links.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:hiwiski/features/account/account/view/account_screen.dart';
import 'package:hiwiski/features/account/view/account_keys.dart';
import 'package:hiwiski/features/session/login/view/login_screen.dart';

import 'a11y/a11y_world.dart';
import 'a11y/screens_a11y_test.dart' show settle, unmount;

/// The operator's legal pages: an instance open to the public names
/// them, a family's own server does not, and the app shows exactly that.
void main() {
  final base = Uri.parse('https://demo.hiwiski.example.org/wiki');

  group('the addresses', () {
    test('absolute ones stay as they are', () {
      final links = LegalLinks.from(
        notice: 'https://hiwiski.example.org/impressum',
        privacy: null,
        base: base,
      );
      expect(
        links.notice,
        equals(Uri.parse('https://hiwiski.example.org/impressum')),
      );
      expect(links.privacy, isNull);
      expect(links.isEmpty, isFalse);
    });

    test('relative ones are read against the page — the demo moves along', () {
      final links = LegalLinks.from(
        notice: '/impressum',
        privacy: 'datenschutz',
        base: base,
      );
      expect(
        links.notice,
        equals(Uri.parse('https://demo.hiwiski.example.org/impressum')),
      );
      expect(
        links.privacy,
        equals(Uri.parse('https://demo.hiwiski.example.org/datenschutz')),
      );
    });

    // The server names these addresses.
    test('only a web page is an address', () {
      for (final address in [
        'sms:+491234',
        'tel:110',
        'intent://x#Intent;end',
        'javascript:alert(1)',
        'file:///etc/hosts',
        'https:///no-host',
      ]) {
        expect(
          LegalLinks.from(
            notice: address,
            privacy: address,
            base: base,
          ).isEmpty,
          isTrue,
          reason: address,
        );
      }
      expect(
        LegalLinks.from(
          notice: '/impressum',
          privacy: null,
          base: Uri.parse('file:///app/'),
        ).isEmpty,
        isTrue,
      );
      expect(
        LegalLinks.from(
          notice: 'HTTP://example.org',
          privacy: null,
          base: base,
        ).notice,
        isNotNull,
      );
    });

    test('empty is none', () {
      expect(
        LegalLinks.from(notice: ' ', privacy: '', base: base).isEmpty,
        isTrue,
      );
    });
  });

  group("the app's own policy", () {
    test('one page per language, English for every other', () {
      expect(
        LegalLinks.appPrivacy('de', place: ''),
        equals(Uri.parse('https://hiwiski.app/app/datenschutz')),
      );
      expect(
        LegalLinks.appPrivacy('en', place: ''),
        equals(Uri.parse('https://hiwiski.app/app/privacy')),
      );
      expect(
        LegalLinks.appPrivacy('fr', place: ''),
        equals(Uri.parse('https://hiwiski.app/app/privacy')),
      );
    });

    test('the demo keeps it next to itself — wherever it is', () {
      expect(
        LegalLinks.appPrivacy('de', place: '/app/', base: base),
        equals(Uri.parse('https://demo.hiwiski.example.org/app/datenschutz')),
      );
    });
  });

  group('the screens', () {
    setUp(mockPlugins);
    tearDown(unmockPlugins);

    Future<void> show(
      WidgetTester tester,
      SessionState session,
      Widget screen,
    ) async {
      final world = (await tester.runAsync(
        () => A11yWorld.create(session: session),
      ))!;
      addTearDown(() async {
        await unmount(tester);
        await tester.runAsync(world.close);
      });
      tester.view.physicalSize = const Size(390, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        a11yApp(overrides: world.overrides(session), home: screen),
      );
      await settle(tester);
    }

    testWidgets('a public instance shows them in the account', (tester) async {
      await show(tester, annaPublicSession, const AccountScreen());
      final l = await L.delegate.load(const Locale('en'));

      expect(find.text(l.legalTitle), findsOneWidget);
      expect(find.byKey(AccountKeys.legalNotice), findsOneWidget);
      expect(find.byKey(AccountKeys.legalPrivacy), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a family\'s own server shows none', (tester) async {
      await show(tester, annaSession, const AccountScreen());
      final l = await L.delegate.load(const Locale('en'));

      expect(find.text(l.legalTitle), findsNothing);
      expect(find.byKey(AccountKeys.legalNotice), findsNothing);
      await unmount(tester);
    });

    testWidgets('before signing in, the sign-in screen has them', (
      tester,
    ) async {
      await show(tester, signedOutPublicSession, const LoginScreen());
      final l = await L.delegate.load(const Locale('en'));

      expect(find.text(l.legalNotice), findsOneWidget);
      expect(find.text(l.legalPrivacy), findsOneWidget);
      await unmount(tester);
    });
  });
}
