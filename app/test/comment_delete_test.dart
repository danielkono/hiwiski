import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/components/comments/view/comment_list.dart';
import 'package:hiwiski/components/comments/view/comments_keys.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/core/ui/undo_snack_bar.dart';
import 'package:hiwiski/domain/common/item_ref.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// **A comment is deleted like a task from its row**: held, not tapped, and "Undo"
/// brings it back.
void main() {
  late HiwiskiDatabase db;
  late LocalSettings settings;
  const item = ItemRef.wikiPage('page-1');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await LocalSettings.open();
    db = HiwiskiDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  List<Override> overrides() => [
    databaseProvider.overrideWithValue(db),
    localSettingsProvider.overrideWithValue(settings),
    sessionAt(signedInAnna),
  ];

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(() async {
      final container = ProviderContainer(overrides: overrides());
      await container
          .read(wikiRepositoryProvider)
          .addComment(
            itemType: EntityTypes.wikiPage,
            itemId: item.id,
            body: 'Lecker!',
          );
      container.dispose();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
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
          home: const Scaffold(
            body: SingleChildScrollView(child: CommentList(item: item)),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Lecker!'), findsOneWidget);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pump(UndoWindow.fallback + const Duration(seconds: 1));
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  testWidgets('a tap only says to hold', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(CommentsKeys.commentDelete));
    await settle(tester);
    expect(find.text('Lecker!'), findsOneWidget);
    expect(find.text('Hold to delete'), findsOneWidget);
    await close(tester);
  });

  testWidgets('held, it goes; undo brings it back', (tester) async {
    await open(tester);
    final press = await tester.startGesture(
      tester.getCenter(find.byKey(CommentsKeys.commentDelete)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await press.up();
    await settle(tester);
    expect(find.text('Lecker!'), findsNothing);
    expect(find.text('Comment deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(find.text('Lecker!'), findsOneWidget);
    await close(tester);
  });
}
