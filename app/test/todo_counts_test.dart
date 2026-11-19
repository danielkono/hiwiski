import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/domain/todo/todo_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **The overview's counts follow the items.** The summary watched only the lists:
/// checking off an item left the open/done counts and the progress bar stale.
void main() {
  test('checking off an item updates the counts', () async {
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
    final repository = container.read(todoRepositoryProvider);
    final listId = await repository.createList(
      name: 'Groceries',
      kind: ListKinds.shopping,
    );
    final milk = await repository.createTodo(listId: listId, title: 'Milk');
    await repository.createTodo(listId: listId, title: 'Bread');
    await repository.createList(name: 'Empty', kind: ListKinds.standard);

    final seen = <List<TodoListSummary>>[];
    final subscription = repository.watchLists().listen(seen.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(
      seen.last.map((s) => (s.list.name, s.open, s.done)),
      equals([('Empty', 0, 0), ('Groceries', 2, 0)]),
    );

    final todo = (await repository.watchTodo(milk).first)!;
    await repository.setStatus(todo, true);
    await pumpEventQueue();

    expect(seen.last.last.open, equals(1));
    expect(seen.last.last.done, equals(1));
  });
}
