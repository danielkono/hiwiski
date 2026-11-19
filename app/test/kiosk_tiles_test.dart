import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/data/board/kiosk_repository.dart';
import 'package:hiwiski/features/board/kiosk/view/kiosk_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **The kiosk's tiles show the board's content, not this device's data.**
/// They read the database of whoever was signed in: empty on a wall
/// tablet, someone else's lists in a browser with a session.
void main() {
  testWidgets('a list tile shows the list the board names', (tester) async {
    // The wakelock plugin has no implementation in tests.
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    final device = HiwiskiDatabase(NativeDatabase.memory());
    final tiles = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(device.close);
    addTearDown(tiles.close);
    final kiosk = _FakeKiosk();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(device),
        kioskDatabaseProvider.overrideWithValue(tiles),
        localSettingsProvider.overrideWithValue(settings),
        deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
        kioskRepositoryProvider.overrideWithValue(kiosk),
      ],
    );
    kiosk.container = container;
    addTearDown(container.dispose);
    // Someone is signed in on this browser, with a list of their own.
    await tester.runAsync(
      () => container
          .read(todoRepositoryProvider)
          .createList(name: 'Private', kind: ListKinds.standard),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Family chores'), findsWidgets);
    expect(find.text('Private'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

class _FakeKiosk implements KioskRepository {
  late ProviderContainer container;

  @override
  Future<BoardView> publicBoard(String token) async => const BoardView(
    boardId: 'b1',
    ownerId: 'anna',
    layout: .grid,
    columns: 4,
    widgets: [
      WidgetView(
        id: 'w1',
        kind: 'TODO_LISTS',
        gridX: 0,
        gridY: 0,
        gridW: 4,
        gridH: 2,
        position: 0,
      ),
    ],
  );

  /// What the server would send: written through the kiosk's own repositories.
  @override
  Future<void> refreshTiles(String token) async {
    final tiles = container.read(kioskTileContainerProvider);
    await tiles
        .read(todoRepositoryProvider)
        .createList(name: 'Family chores', kind: ListKinds.standard);
  }

  @override
  Stream<int> changes(String token) => const .empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
