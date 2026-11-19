import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/features/todo/overview/todo_overview_view_model.dart';
import 'package:hiwiski/domain/tags/tag.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **A tag filter lasts as long as the page that holds it** — no list of routes decides
/// it. Subpages stack on top of their area's page, so the filter stays inside the area
/// and goes when navigation replaces it.
void main() {
  late ProviderContainer container;
  const area = TagFilterAreas.areas;

  late HiwiskiDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = await LocalSettings.open();
    container = ProviderContainer(
      overrides: [
        localSettingsProvider.overrideWithValue(settings),
        databaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);
  });

  Set<String> filter() => container.read(tagFilterStoreProvider).of(area);
  void pick(String id) =>
      container.read(tagFilterStoreProvider).toggle(area, id);
  ProviderSubscription<void> hold(String page) =>
      container.listen(tagFilterHoldProvider(area, page), (_, _) {});

  // The filter went with every tap: the ViewModel's build released it on each rebuild.
  test('it stays while its page holds it, tap after tap', () async {
    hold('tasks');
    pick('tag-1');
    await pumpEventQueue();
    pick('tag-2');
    await pumpEventQueue();

    expect(filter(), equals({'tag-1', 'tag-2'}));
  });

  test('a ViewModel that rebuilds on every tap keeps it', () async {
    final overview = container.listen(todoOverviewViewModelProvider, (_, _) {});
    addTearDown(overview.close);
    final viewModel = container.read(todoOverviewViewModelProvider.notifier);

    viewModel.toggleTag('tag-1');
    await pumpEventQueue();
    viewModel.toggleTag('tag-2');
    await pumpEventQueue();

    final state = await container.read(todoOverviewViewModelProvider.future);
    expect(state.filter, equals({'tag-1', 'tag-2'}));
  });

  test('it goes when its page goes', () async {
    final tasks = hold('tasks');
    pick('tag-1');

    tasks.close();
    await pumpEventQueue();

    expect(filter(), isEmpty);
  });

  // Tasks to wiki: both filter, but leaving an area's page ends its filter.
  test('another page holding it does not keep it', () async {
    final tasks = hold('tasks');
    pick('tag-1');
    hold('wiki');

    tasks.close();
    await pumpEventQueue();

    expect(filter(), isEmpty);
  });

  test('it stays when the device keeps filters', () async {
    await container.read(preferencesStoreProvider).setKeepFilters(true);
    final tasks = hold('tasks');
    pick('tag-1');

    tasks.close();
    await pumpEventQueue();

    expect(filter(), equals({'tag-1'}));
  });

  // Unmounting the app disposes the store with it: nothing is left to release.
  test('going away with the whole app releases nothing', () async {
    hold('tasks');
    container.read(tagFilterStoreProvider);

    container.dispose();
    await pumpEventQueue();
  });
}
