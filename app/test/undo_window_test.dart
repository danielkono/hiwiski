import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/ui/archive_ui.dart';
import 'package:hiwiski/core/ui/undo_snack_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **How long "Undo" shows is the member's choice** (Account → Customize) — and the
/// deletion waits that long, so "Undo" works for as long as it shows.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'the deletion waits as long as the setting says, and a little more',
    () async {
      final db = HiwiskiDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(await LocalSettings.open()),
        ],
      );
      addTearDown(container.dispose);

      final todos = container.read(todoRepositoryProvider);
      expect(todos.deleteGrace, greaterThan(const Duration(seconds: 8)));

      await container.read(preferencesStoreProvider).setUndoSeconds(30);
      expect(todos.deleteGrace, greaterThan(const Duration(seconds: 30)));
      expect(
        container.read(wikiRepositoryProvider).deleteGrace,
        greaterThan(const Duration(seconds: 30)),
      );
      expect((await LocalSettings.open()).undoSeconds, equals(30));
    },
  );

  testWidgets('the note with "Undo" shows as long as the device says', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: L.supportedLocales,
        locale: const Locale('en'),
        builder: (context, child) => UndoWindow(
          duration: const Duration(seconds: 15),
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showUndoSnackBar(context, message: 'gone', onUndo: () {}),
              child: const Text('delete'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('delete'));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Undo'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
  });

  // With "Undo", Flutter kept the note until it was dismissed — after archiving a list
  // from the dashboard it stood over the next screen.
  testWidgets('"Archived" goes by itself', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: L.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showArchivedSnackBar(context, onUndo: () {}),
              child: const Text('archive'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('archive'));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);

    await tester.pump(UndoWindow.fallback + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
  });
}
