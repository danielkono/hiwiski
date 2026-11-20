import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/data/sync/sync_repository.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:hiwiski/features/account/view/account_keys.dart';
import 'package:hiwiski/features/account/account/view/account_screen.dart';

import 'a11y/a11y_world.dart';
import 'a11y/screens_a11y_test.dart' show settle, unmount;
import 'support/fakes.dart';

/// "Sign out anyway", with changes the server could not take: one more try, **shown
/// in the dialog**. The sign-out used to make it after the dialog had closed — away
/// from home, the start screen stood there signed in for a connection timeout, and
/// nothing said why.
void main() {
  setUp(mockPlugins);
  tearDown(unmockPlugins);

  testWidgets('the last try runs in the open dialog, and only once', (
    tester,
  ) async {
    final world = (await tester.runAsync(A11yWorld.create))!;
    final sync = _Sync();
    addTearDown(() async {
      await unmount(tester);
      await tester.runAsync(world.close);
    });
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      a11yApp(overrides: _overrides(world, sync), home: const AccountScreen()),
    );
    await settle(tester);
    final l = await L.delegate.load(const Locale('en'));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AccountScreen)),
    );
    SessionStage stage() => container.read(sessionProvider).stage;

    await tester.tap(find.text(l.accountSignOut));
    await settle(tester);
    expect(find.text(l.accountSignOutLost(2)), findsOneWidget);

    await tester.tap(find.byKey(AccountKeys.signOutAcknowledge));
    await tester.pump();
    final lastTry = sync.hold = Completer<void>();
    await tester.tap(find.byKey(AccountKeys.signOutConfirm));
    await settle(tester);

    expect(find.text(l.accountSignOutRetrying), findsOneWidget);
    expect(stage(), equals(SessionStage.signedIn));
    expect(sync.runs, equals(2));

    lastTry.complete();
    await settle(tester);

    expect(find.text(l.accountSignOutRetrying), findsNothing);
    expect(stage(), equals(SessionStage.signedOut));
    expect(sync.runs, equals(2), reason: 'the sign-out did not try again');
    await unmount(tester);
  });
}

/// The test world, with a session that can sign out and a sync that waits when told
/// to.
List<Override> _overrides(A11yWorld world, _Sync sync) => [
  databaseProvider.overrideWithValue(world.db),
  localSettingsProvider.overrideWithValue(world.settings),
  A11yWorld.hiwikiApi(world.api),
  deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
  // No keychain in a test: the sign-out reads and drops the token here.
  tokenStoreProvider.overrideWithValue(NoTokens()),
  sessionFrom(annaSession),
  syncRepositoryProvider.overrideWithValue(sync),
  ...quietSync,
];

/// Two changes wait, and the server takes none of them. Each run counts; one may be
/// held back to stand for a server that does not answer.
class _Sync implements SyncRepository {
  int runs = 0;
  Completer<void>? hold;

  @override
  Future<void> syncLast() async {
    runs++;
    final waiting = hold;
    hold = null;
    await waiting?.future;
  }

  @override
  Future<void> stop() async {}

  @override
  Stream<int> watchPendingCount() => .value(2);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
