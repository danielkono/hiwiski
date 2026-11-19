import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/domain/todo/overview_view.dart';
import 'package:hiwiski/features/todo/overview/todo_overview_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **Lists are sorted on the overview by drag and drop**: a card dropped on another
/// takes its place, and the order is written as positions that sync.
void main() {
  Future<ProviderContainer> start() async {
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
    return container;
  }

  Future<List<String>> names(ProviderContainer container) async => [
    for (final summary in (await container.read(
      todoOverviewViewModelProvider.future,
    )).lists)
      summary.list.name,
  ];

  test('a list dropped on another takes its place', () async {
    final container = await start();
    final todos = container.read(todoRepositoryProvider);
    final ids = <String, String>{};
    for (final name in ['A', 'B', 'C']) {
      ids[name] = await todos.createList(name: name, kind: ListKinds.standard);
    }
    final subscription = container.listen(
      todoOverviewViewModelProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    expect(await names(container), equals(['A', 'B', 'C']));

    await container
        .read(todoOverviewViewModelProvider.notifier)
        .move(ids['A']!, ids['C']!);
    await pumpEventQueue();
    expect(await names(container), equals(['B', 'C', 'A']));

    await container
        .read(todoOverviewViewModelProvider.notifier)
        .move(ids['A']!, ids['B']!);
    await pumpEventQueue();
    expect(await names(container), equals(['A', 'B', 'C']));
  });

  // The order is the member's own: the lists' shared positions stay as they were —
  // sorting used to need write access and sorted for everyone.
  test(
    'sorting writes the member\'s order, not the lists\' positions',
    () async {
      final container = await start();
      final todos = container.read(todoRepositoryProvider);
      final a = await todos.createList(name: 'A', kind: ListKinds.standard);
      final b = await todos.createList(name: 'B', kind: ListKinds.standard);
      final subscription = container.listen(
        todoOverviewViewModelProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.read(todoOverviewViewModelProvider.future);
      final before = {
        for (final summary in await todos.watchLists().first)
          summary.list.id: summary.list.position,
      };

      await container.read(todoOverviewViewModelProvider.notifier).move(b, a);
      await pumpEventQueue();

      expect(await names(container), equals(['B', 'A']));
      expect(await todos.watchListOrder().first, equals([b, a]));
      expect({
        for (final summary in await todos.watchLists().first)
          summary.list.id: summary.list.position,
      }, equals(before));
    },
  );

  test('a list new since sorting comes after the sorted ones', () async {
    final container = await start();
    final todos = container.read(todoRepositoryProvider);
    final a = await todos.createList(name: 'A', kind: ListKinds.standard);
    final b = await todos.createList(name: 'B', kind: ListKinds.standard);
    await todos.setListOrder([b, a]);
    await todos.createList(name: 'C', kind: ListKinds.standard);
    final subscription = container.listen(
      todoOverviewViewModelProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);

    expect(await names(container), equals(['B', 'A', 'C']));
  });

  test('a tag filter does not stop the sorting', () async {
    final container = await start();
    final todos = container.read(todoRepositoryProvider);
    final a = await todos.createList(name: 'A', kind: ListKinds.standard);
    final b = await todos.createList(name: 'B', kind: ListKinds.standard);
    final c = await todos.createList(name: 'C', kind: ListKinds.standard);
    final subscription = container.listen(
      todoOverviewViewModelProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    await container.read(todoOverviewViewModelProvider.future);
    container.read(todoOverviewViewModelProvider.notifier).toggleTag('t');
    await pumpEventQueue();
    await container.read(todoOverviewViewModelProvider.future);

    // B is hidden by the filter; C dropped on A still keeps B in its place.
    await container.read(todoOverviewViewModelProvider.notifier).move(c, a);
    await pumpEventQueue();

    expect(await todos.watchListOrder().first, equals([c, a, b]));
  });

  test('by kind: tasks, shopping, Kanban, each in its order', () async {
    final container = await start();
    final todos = container.read(todoRepositoryProvider);
    await todos.createList(name: 'Groceries', kind: ListKinds.shopping);
    await todos.createList(name: 'Chores', kind: ListKinds.standard);
    await todos.createList(name: 'Move', kind: ListKinds.kanban);
    await todos.createList(name: 'Hardware', kind: ListKinds.shopping);
    final subscription = container.listen(
      todoOverviewViewModelProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);

    await container
        .read(todoOverviewViewModelProvider.notifier)
        .setMode(TodoViewMode.byKind);
    final state = await container.read(todoOverviewViewModelProvider.future);

    expect(state.mode, equals(TodoViewMode.byKind));
    expect(
      [
        for (final group in state.groups)
          '${group.kind}: ${[for (final s in group.lists) s.list.name].join(', ')}',
      ],
      equals([
        'STANDARD: Chores',
        'SHOPPING: Groceries, Hardware',
        'KANBAN: Move',
      ]),
    );
  });

  test('the sidebar opens the first list until another is chosen', () async {
    final container = await start();
    final todos = container.read(todoRepositoryProvider);
    final first = await todos.createList(name: 'A', kind: ListKinds.standard);
    final second = await todos.createList(name: 'B', kind: ListKinds.standard);
    final subscription = container.listen(
      todoOverviewViewModelProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    expect(
      (await container.read(todoOverviewViewModelProvider.future)).selectedId,
      equals(first),
    );

    container.read(todoOverviewViewModelProvider.notifier).select(second);

    expect(
      (await container.read(todoOverviewViewModelProvider.future)).selectedId,
      equals(second),
    );
    // The choice is the device's, the view mode too: it survives a new screen.
    await container
        .read(todoOverviewViewModelProvider.notifier)
        .setMode(TodoViewMode.sidebar);
    expect(container.read(localSettingsProvider).todoView, equals('SIDEBAR'));
  });
}
