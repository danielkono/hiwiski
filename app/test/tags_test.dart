import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/domain/tags/tag.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tags: what stays and what counts.
void main() {
  // The lists stayed filtered by a deleted tag that no chip showed any more.
  test('deleting a tag removes it from every filter', () async {
    SharedPreferences.setMockInitialValues({});
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(await LocalSettings.open()),
      ],
    );
    addTearDown(container.dispose);
    final tags = container.read(tagRepositoryProvider);
    final work = await tags.createTag('Work');
    for (final area in TagFilterAreas.all) {
      container.read(tagFilterStoreProvider).toggle(area, work);
    }
    final tag = (await tags.watchTags().first).single;

    await tags.deleteTag(tag);

    for (final area in TagFilterAreas.all) {
      expect(container.read(tagFilterStoreProvider).of(area), isEmpty);
    }
  });

  // A tag set only on a calendar showed as unused, and could be deleted as such.
  test("a calendar's tag counts as used", () async {
    SharedPreferences.setMockInitialValues({});
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(await LocalSettings.open()),
      ],
    );
    addTearDown(container.dispose);
    final family = await container
        .read(tagRepositoryProvider)
        .createTag('Family');
    await db
        .into(db.calendars)
        .insert(
          CalendarsCompanion.insert(
            id: 'c1',
            ownerId: 'anna',
            name: const Value('Family'),
            tags: Value(family),
          ),
        );

    final usage = await container
        .read(tagRepositoryProvider)
        .watchUsage()
        .first;

    expect(usage[family], equals(1));
  });
}
