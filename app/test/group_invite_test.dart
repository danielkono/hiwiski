import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/data/family/family_repository.dart';
import 'package:hiwiski/features/family/view/group_sheet.dart';

import 'support/fakes.dart';

/// **"Invite a new person and add them right away" adds them to the group.** It
/// closed the sheet and opened a blank invitation: a new group was never created,
/// and the invitee joined nothing.
void main() {
  testWidgets('a new group is saved first and preselected', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final family = _FakeFamily();
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
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showGroupSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Grandparents');

    await tester.tap(find.text('Invite a new person and add them right away'));
    await tester.pumpAndSettle();

    expect(family.saved?.name, equals('Grandparents'));
    final chip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Grandparents'),
    );
    expect(chip.selected, isTrue);
  });

  // One mis-tap on the red "Delete" removed the group, and every share to it.
  testWidgets('deleting a group asks first', (tester) async {
    final family = _FakeFamily();
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
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showGroupSheet(
                  context,
                  group: const Group(
                    id: 'g1',
                    name: 'Kids',
                    position: 0,
                    memberIds: [],
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete “Kids”?'), findsOneWidget);
    expect(family.deleted, isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(family.deleted, equals('g1'));
  });
}

class _FakeFamily implements FamilyRepository {
  WriteGroupRequest? saved;
  String? deleted;
  final _changed = StreamController<void>.broadcast();

  @override
  Future<void> deleteGroup(String id) async {
    deleted = id;
    _changed.add(null);
  }

  @override
  Future<Group> saveGroup(WriteGroupRequest group, {String? id}) async {
    saved = group;
    _changed.add(null);
    return Group(id: 'g1', name: group.name, position: 0, memberIds: const []);
  }

  Stream<T> _watch<T>(Future<T> Function() fetch) async* {
    yield await fetch();
    await for (final _ in _changed.stream) {
      yield await fetch();
    }
  }

  @override
  Stream<List<Group>> watchGroups() => _watch(groups);

  @override
  Stream<List<Member>> watchMembers() => _watch(members);

  @override
  Stream<List<Invitation>> watchInvitations() => _watch(invitations);

  @override
  Future<List<Group>> groups() async => [
    if (saved case final group?)
      Group(id: 'g1', name: group.name, position: 0, memberIds: const []),
  ];

  @override
  Future<List<Member>> members() async => const [];

  @override
  Future<List<Invitation>> invitations() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
