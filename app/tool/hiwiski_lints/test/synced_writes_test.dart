import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:hiwiski_lints/src/synced_writes.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(SyncedWritesTest);
  });

  test('the sync, the database and generated code are exempt', () {
    expect(writesHere('data/todo/todo_repository.dart'), isTrue);
    expect(writesHere('app/repositories.dart'), isTrue);
    expect(writesHere('features/todo/list/list_view_model.dart'), isTrue);
    expect(writesHere('core/sync/local_writes.dart'), isFalse);
    expect(writesHere('core/db/hiwiski_database.dart'), isFalse);
    expect(writesHere('app/repositories.g.dart'), isFalse);
  });
}

@reflectiveTest
class SyncedWritesTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = SyncedWrites();
    newPackage('drift').addFile('lib/drift.dart', r'''
abstract class Table {}
mixin TableInfo<T extends Table, D> on Table {}
class InsertStatement {
  Future<int> insert(Object row) async => 0;
}
class UpdateStatement {
  Future<int> write(Object row) async => 0;
  Future<bool> replace(Object row) async => true;
}
class DeleteStatement {
  Future<int> go() async => 0;
}
class Batch {
  void insert<T extends Table, D>(TableInfo<T, D> table, Object row) {}
  void deleteWhere<T extends Table, D>(TableInfo<T, D> table, Object f) {}
}
abstract class DatabaseConnectionUser {
  InsertStatement into<T extends Table, D>(TableInfo<T, D> table) =>
      InsertStatement();
  UpdateStatement update<T extends Table, D>(TableInfo<T, D> table) =>
      UpdateStatement();
  DeleteStatement delete<T extends Table, D>(TableInfo<T, D> table) =>
      DeleteStatement();
  Object select<T extends Table, D>(TableInfo<T, D> table) => Object();
  Future<void> customStatement(String sql) async {}
  Future<T> transaction<T>(Future<T> Function() body) => body();
}
extension TableStatements<T extends Table, D> on TableInfo<T, D> {
  Future<int> insertOne(Object row) async => 0;
  Future<int> deleteAll() async => 0;
  Object all() => Object();
}
''');
    super.setUp();
    _write('core/db/tables.dart', r'''
import 'package:drift/drift.dart';
mixin SyncedItem on Table {}
class Todos extends Table with SyncedItem {}
class Aisles extends Table {}
class OutboxEntries extends Table {}
''');
    _write('core/db/hiwiski_database.dart', r'''
import 'package:drift/drift.dart';
import 'tables.dart';
class $TodosTable extends Todos with TableInfo<$TodosTable, Object> {}
class $AislesTable extends Aisles with TableInfo<$AislesTable, Object> {}
class $OutboxEntriesTable extends OutboxEntries
    with TableInfo<$OutboxEntriesTable, Object> {}
class HiwiskiDatabase extends DatabaseConnectionUser {
  final todos = $TodosTable();
  final aisles = $AislesTable();
  final outboxEntries = $OutboxEntriesTable();
}
''');
    _write('core/sync/outbox.dart', r'''
class Outbox {
  Future<String> add() async => '';
  Future<void> retryAll() async {}
}
''');
    _write('core/sync/entity_codec.dart', 'const entityCodecs = <Object>[];');
  }

  String _write(String path, String content) {
    final file = '$testPackageLibPath/$path';
    newFile(file, content);
    return file;
  }

  static const _imports = '''
import 'package:drift/drift.dart';
import '../../core/db/hiwiski_database.dart';
import '../../core/db/tables.dart';
typedef Used = (Table, SyncedItem);
''';

  /// Where the first [name] after [after] starts in [content].
  static int _offset(String content, String name, {String after = ''}) =>
      content.indexOf(name, content.indexOf(after));

  Future<void> test_syncedTableThroughTheDatabase() async {
    const content =
        '''
$_imports
Future<void> f(HiwiskiDatabase db) async {
  await db.into(db.todos).insert(1);
  await db.update(db.todos).write(1);
  await db.delete(db.todos).go();
}
''';
    await assertDiagnosticsInFile(_write('data/todo/r.dart', content), [
      lint(_offset(content, 'into'), 4),
      lint(_offset(content, 'update'), 6),
      lint(_offset(content, 'delete', after: 'write'), 6),
    ]);
  }

  Future<void> test_theOutboxTable() async {
    const content =
        '''
$_imports
Future<void> f(HiwiskiDatabase db) => db.delete(db.outboxEntries).go();
''';
    await assertDiagnosticsInFile(_write('data/sync/r.dart', content), [
      lint(_offset(content, 'delete'), 6),
    ]);
  }

  Future<void> test_syncedTableItself() async {
    const content =
        '''
$_imports
Future<void> f(HiwiskiDatabase db) async {
  await db.todos.insertOne(1);
  await db.todos.deleteAll();
}
''';
    await assertDiagnosticsInFile(_write('data/todo/r.dart', content), [
      lint(_offset(content, 'insertOne'), 9),
      lint(_offset(content, 'deleteAll'), 9),
    ]);
  }

  Future<void> test_batch() async {
    const content =
        '''
$_imports
void f(HiwiskiDatabase db, Batch batch) {
  batch.insert(db.todos, 1);
  batch.insert(db.aisles, 1);
}
''';
    await assertDiagnosticsInFile(_write('data/todo/r.dart', content), [
      lint(_offset(content, 'insert'), 6),
    ]);
  }

  Future<void> test_genericSyncedTable() async {
    const content =
        '''
$_imports
Future<void> f<T extends SyncedItem, D>(HiwiskiDatabase db, TableInfo<T, D> t) =>
    db.update(t).write(1);
''';
    await assertDiagnosticsInFile(_write('data/todo/r.dart', content), [
      lint(_offset(content, 'update'), 6),
    ]);
  }

  Future<void> test_tableThatDoesNotSay() async {
    const content =
        '''
$_imports
Future<void> f(HiwiskiDatabase db) async {
  final TableInfo<Table, Object?> table = db.todos;
  await db.into(table).insert(1);
}
''';
    await assertDiagnosticsInFile(_write('data/todo/r.dart', content), [
      error(SyncedWrites.unknownTable, content.indexOf('into'), 4),
    ]);
  }

  Future<void> test_rawSql() async {
    const content =
        '''
$_imports
Future<void> f(HiwiskiDatabase db) => db.customStatement('DELETE FROM todos');
''';
    await assertDiagnosticsInFile(_write('data/todo/r.dart', content), [
      error(
        SyncedWrites.rawSql,
        content.indexOf('customStatement'),
        'customStatement'.length,
      ),
    ]);
  }

  Future<void> test_outboxAdd() async {
    const content = '''
import '../../core/sync/outbox.dart';
Future<void> f(Outbox outbox) async {
  await outbox.add();
  await outbox.retryAll();
}
''';
    await assertDiagnosticsInFile(_write('data/sync/r.dart', content), [
      error(SyncedWrites.outboxAdd, content.indexOf('add'), 3),
    ]);
  }

  Future<void> test_codecs() async {
    const content = '''
import '../../core/sync/entity_codec.dart';
final n = entityCodecs.length;
''';
    await assertDiagnosticsInFile(_write('data/board/r.dart', content), [
      error(
        SyncedWrites.codecs,
        content.indexOf("'"),
        "'../../core/sync/entity_codec.dart'".length,
      ),
    ]);
  }

  Future<void> test_tablesThatAreNotSynced() async {
    const content =
        '''
$_imports
Future<void> f(HiwiskiDatabase db) async {
  await db.into(db.aisles).insert(1);
  await db.update(db.aisles).replace(1);
  await db.delete(db.aisles).go();
  await db.aisles.deleteAll();
}
''';
    await assertNoDiagnosticsInFile(_write('data/catalog/r.dart', content));
  }

  Future<void> test_reads() async {
    const content =
        '''
$_imports
Future<void> f(HiwiskiDatabase db) async {
  db.select(db.todos);
  db.todos.all();
  await db.transaction(() async {});
}
''';
    await assertNoDiagnosticsInFile(_write('data/todo/r.dart', content));
  }

  Future<void> test_othersNamedLikeWrites() async {
    const content = '''
class ListViewModel {
  Future<void> delete(Object item) async {}
  Future<void> update(Object item) async {}
}
Future<void> f(ListViewModel vm) async {
  await vm.delete(1);
  await vm.update(1);
}
''';
    await assertNoDiagnosticsInFile(
      _write('features/todo/list/list_view_model.dart', content),
    );
  }

  Future<void> test_theSyncAndTheDatabaseMayWrite() async {
    const content = '''
import '../db/hiwiski_database.dart';
import 'entity_codec.dart';
import 'outbox.dart';
Future<void> f(HiwiskiDatabase db, Outbox outbox) async {
  await db.into(db.todos).insert(entityCodecs.length);
  await db.customStatement('DELETE FROM todos');
  await outbox.add();
}
''';
    await assertNoDiagnosticsInFile(
      _write('core/sync/local_writes.dart', content),
    );
  }
}
