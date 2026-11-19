import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/data/family/family_repository.dart';
import 'package:hiwiski/features/family/view/family_keys.dart';
import 'package:hiwiski/features/family/view/family_screen.dart';

import 'support/fakes.dart';

final _grandma = Invitation(
  id: 'inv-1',
  displayName: 'Grandma',
  expiresAt: DateTime.utc(2100),
);

/// **An open invitation can be withdrawn.** One handed to the wrong person opened a
/// family account for whoever had its code until it ran out, and nothing in the app
/// could stop it.
void main() {
  late _Family family;

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    family = _Family();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyRepositoryProvider.overrideWithValue(family),
          sessionAt(signedInAnna),
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
          home: const FamilyScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('withdrawing asks first, and only "Withdraw" withdraws', (
    tester,
  ) async {
    await open(tester);
    expect(find.byTooltip('Withdraw the invitation for Grandma'), findsOne);

    await tester.tap(find.byKey(FamilyKeys.revoke(_grandma.id)));
    await tester.pumpAndSettle();
    expect(find.text('Withdraw the invitation?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(family.revoked, isEmpty);

    await tester.tap(find.byKey(FamilyKeys.revoke(_grandma.id)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FamilyKeys.revokeConfirm));
    await tester.pumpAndSettle();
    expect(family.revoked, equals([_grandma.id]));
  });
}

class _Family implements FamilyRepository {
  final revoked = <String>[];

  @override
  Stream<List<Member>> watchMembers() => .value([signedInAnna.session!.member]);

  @override
  Stream<List<Group>> watchGroups() => .value(const []);

  @override
  Stream<List<Invitation>> watchInvitations() => .value([_grandma]);

  @override
  Future<void> revokeInvitation(String id) async => revoked.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
