import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/components/tags/view/tags_section.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **"+ Tag" stands level with the tags** in the info area — its tap target is taller
/// than a chip, and it sat below them.
void main() {
  testWidgets('"+ Tag" and a tag share their middle', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = (await tester.runAsync(LocalSettings.open))!;
    final container = ProviderContainer(
      retry: noRetry,
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);
    final id = (await tester.runAsync(
      () => container.read(tagRepositoryProvider).createTag('Garden'),
    ))!;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: L.localizationsDelegates,
          supportedLocales: L.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: TagsSection(raw: id, onChanged: (_) {}),
          ),
        ),
      ),
    );
    for (int i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      tester.getCenter(find.text('+ Tag')).dy,
      moreOrLessEquals(tester.getCenter(find.text('Garden')).dy, epsilon: 0.5),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
