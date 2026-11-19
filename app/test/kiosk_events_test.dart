import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/data/board/kiosk_repository.dart';
import 'package:hiwiski/features/board/kiosk/view/kiosk_screen.dart';

/// **The kiosk keeps one event stream.** Every change event used to load the board
/// and then reconnect; two events close together left a connection behind each time.
void main() {
  testWidgets('change events reload the board without reconnecting', (
    tester,
  ) async {
    // The wakelock plugin has no implementation in tests.
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
    final kiosk = _FakeKiosk();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [kioskRepositoryProvider.overrideWithValue(kiosk)],
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
          home: const KioskScreen(token: 't'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    kiosk.events.add(1);
    kiosk.events.add(2);
    await tester.pump();
    await tester.pump();

    expect(kiosk.loads, equals(3));
    expect(kiosk.subscriptions, equals(1));
    await tester.pumpWidget(const SizedBox());
  });
}

class _FakeKiosk implements KioskRepository {
  int loads = 0;
  int subscriptions = 0;
  final events = StreamController<int>.broadcast();

  @override
  Future<BoardView> publicBoard(String token) async {
    loads++;
    return const BoardView(
      boardId: 'b1',
      ownerId: 'anna',
      layout: .grid,
      columns: 4,
      widgets: [],
    );
  }

  @override
  Future<void> refreshTiles(String token) async {}

  @override
  Stream<int> changes(String token) {
    subscriptions++;
    return events.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
